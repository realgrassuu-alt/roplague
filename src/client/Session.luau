--!strict
-- Port of scripts/net/session.gd (client half): match orchestration for the title attract mode, solo
-- campaigns and the shared multiplayer match. Same public API and signals as session.gd.
--
--   MODE_TITLE  local AI-only Sim (88 nations + tribes): a fast warm-up time-lapse, then TITLE_SPEED
--   MODE_SOLO   local Sim with one human, paused while help / game menu are open
--   MODE_MULTI  the server's Sim (src/server/MatchServer.luau): snapshot then per-tick deltas
--
-- session.gd built and stepped local sims on a worker thread. Roblox gives game scripts no worker
-- threads, so here:
--   * match construction (Sim.new, add_human, snapshot, GameState load) and multiplayer snapshot
--     decoding run in a Coop job (Net/Coop.luau) resumed every frame with BUILD_BUDGET_S — the previous
--     world keeps animating meanwhile, and nothing blocks a frame as long as the Core loops call
--     Coop.check();
--   * local stepping is budgeted: a tick's step is itself a Coop job (the Sim's loops call
--     Coop.check()), resumed every frame with STEP_BUDGET_S until it completes, then further ticks
--     while the budget lasts. A time-lapse that can't keep up slows down instead of stalling frames
--     (the accumulator is capped exactly like session.gd's MAX_STEPS_PER_TASK).
--
-- The environment is injectable (`Session.new(env)`) so tests drive the multiplayer path headless
-- against MatchServer (tests/net_session.luau). On Roblox `Session.new()` builds the real environment.
--
-- Maps: local matches run on config.map_id (start_solo's optional map id; the title uses the default
-- map); a multiplayer mirror uses the snapshot's map_id. A map that is not available locally (only
-- the default map is replicated) is downloaded first (env.fetch_map_async → Net/MapFetch) while the
-- build / join job waits; the lobby info's map_id is prefetched.

-- Roblox: ReplicatedStorage.Airfront; Lune: the source tree.
local Shared: any = if (game :: any) ~= nil
	then (game :: any):GetService("ReplicatedStorage"):WaitForChild("Airfront")
	else nil
local Coop = if Shared then require(Shared.Net.Coop) else require("../shared/Net/Coop")
local Protocol = if Shared then require(Shared.Net.Protocol) else require("../shared/Net/Protocol")
local Settings = if Shared then require(Shared.Net.Settings) else require("../shared/Net/Settings")
local Signal = if Shared then require(Shared.Core.Signal) else require("../shared/Core/Signal")
local MapFetch: any = if Shared then require(Shared.Net.MapFetch) else nil
local Stars: any = if Shared then require(Shared.Data.Stars) else require("../shared/Data/Stars")
local Arsenal: any = if Shared then require(Shared.Data.Arsenal) else require("../shared/Data/Arsenal")

local Session = {}
Session.__index = Session

Session.MODE_TITLE = 0
Session.MODE_SOLO = 1
Session.MODE_MULTI = 2

Session.STAGE_IDLE = "idle"
Session.STAGE_LOBBY = "lobby"
Session.STAGE_SPAWN = "spawn"
Session.STAGE_PLAYING = "playing"
Session.STAGE_OVER = "over"

Session.TICK_RATE = 10
Session.TICK_SEC = 1.0 / 10
Session.LOBBY_COUNTDOWN_SEC = 15.0
Session.REMATCH_COUNTDOWN_SEC = 12.0
Session.RESULTS_SEC = 18.0
Session.MP_TRIBES = 90
Session.MP_MAX_HUMANS = 32
Session.MP_SPAWN_TICKS = 200
Session.MP_TIME_LIMIT_S = 40 * 60
--- Tribes in a solo match (nil: Sim.default_tribes, 400)
--- and on the title backdrop (fewer: it runs on idle phones too).
Session.SOLO_TRIBES = nil :: number?
Session.TITLE_TRIBES = 150
--- Map of the title backdrop (nil: MapList.DEFAULT, replicated so it starts without a download).
Session.TITLE_MAP_ID = nil :: string?
--- The title globe opens with a fast time-lapse of the first 90 s so it is never an empty world.
Session.TITLE_WARMUP_TICKS = 900
--- A public match's waiting room shows its map behind the panel: the same AI backdrop on that map,
--- warmed up only this far so the map itself stays easy to read.
Session.WAIT_WARMUP_TICKS = 150
Session.TITLE_WARMUP_SPEED = 22.0
Session.TITLE_SPEED = 1.35
--- Phones idle on the title screen: keep the backdrop alive but spend less battery.
Session.TITLE_SPEED_MOBILE = 0.6
Session.MAX_STEPS_PER_TASK = 12

Session.NOTICE_INFO = 0
Session.NOTICE_WARNING = 1
Session.NOTICE_ERROR = 2

--- Frame budgets (seconds). The local Sim gets STEP_BUDGET_S of a frame; a tick that needs more goes on
--- in the next frame (2026-10-12, so solo matches run smoother on phones: one step
--- of a solo match's first minute was 2.4-7 ms on a Mac and several times that on a phone, which runs
--- our code without native code, all in one frame ten times a second; 59% of the Slow Frames reports
--- blamed the Sim, 70% of them on phones). While the Sim is behind (a tick already due when one is in
--- flight) it gets STEP_BUDGET_BEHIND_S, so a slow device keeps the match near real time.
Session.STEP_BUDGET_S = 0.006
Session.STEP_BUDGET_MOBILE_S = 0.004
Session.STEP_BUDGET_BEHIND_S = 0.010
Session.STEP_BUDGET_BEHIND_MOBILE_S = 0.008
Session.BUILD_BUDGET_S = 0.005
Session.BUILD_BUDGET_MOBILE_S = 0.004

--- A settings section is sent at most this often (leading edge immediately, the latest value trails).
Session.SETTINGS_SEND_GAP_S = 0.5
--- Queued for multiplayer but the server's lobby info still says we are not in: re-send JOIN after
--- this long (the server ignores a JOIN inside its cooldown, or it can be lost to the message budget).
Session.JOIN_RETRY_S = 3.0
--- A mirror that failed to decode / apply a delta asks for a fresh snapshot at most this often.
Session.RESYNC_GAP_S = 10.0
--- In multiplayer, user input is reported to the server at most this often (idle detection).
Session.ACTIVE_GAP_S = 30.0

local MODE_TITLE, MODE_SOLO, MODE_MULTI = 0, 1, 2
local PHASE_OVER = 2
local OP = Protocol.OP

-- =============================================================================================
-- Environment
-- =============================================================================================

local function roblox_env(): { [string]: any }
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local UserInputService = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	local Core = ReplicatedStorage:WaitForChild("Airfront"):WaitForChild("Core")

	local env: { [string]: any } = {}
	env.now = os.clock
	env.defer = function(fn: () -> ())
		task.defer(fn)
	end
	env.warn = warn
	env.mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		or GuiService:IsTenFootInterface()
	env.display_name = function(): string
		local p = Players.LocalPlayer
		if p ~= nil then
			if p.DisplayName ~= "" then
				return p.DisplayName
			end
			if p.Name ~= "" then
				return p.Name
			end
		end
		return "Commander"
	end
	env.user_id = function(): number
		local p = Players.LocalPlayer
		return if p ~= nil then p.UserId else 0
	end
	-- Map downloads (maps other than the default live on the server): cb(ok, err) when done.
	env.fetch_map_async = function(id: string, cb: (boolean, string?) -> ())
		task.spawn(function()
			local ok, err = MapFetch.fetch(id)
			cb(ok, err)
		end)
	end
	-- Core modules are required lazily: a missing module must never break boot.
	env.require_core = function(name: string): any
		-- "Plague/PlagueSim": a module in a folder under Core
		local m: Instance? = Core
		for part in string.gmatch(name, "[^/]+") do
			m = if m ~= nil then m:FindFirstChild(part) else nil
		end
		if m == nil then
			return nil
		end
		return (require :: any)(m)
	end
	-- Network: the server creates ReplicatedStorage.AirfrontNet; connect once it replicates.
	-- The server answers HELLO with the player's saved settings (SETTINGS): saves wait for them.
	local net: { [string]: any } = { connected = false, sends_settings = true, busy_s = 0.0 }
	local handler: ((number, ...any) -> ())? = nil
	local to_server: RemoteEvent? = nil
	net.send = function(op: number, ...: any)
		if to_server ~= nil then
			to_server:FireServer(op, ...)
		end
	end
	net.listen = function(fn: (number, ...any) -> ())
		handler = fn
	end
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("AirfrontNet", math.huge)
		local ts = folder:WaitForChild("ToServer") :: RemoteEvent
		local tc = folder:WaitForChild("ToClient") :: RemoteEvent
		tc.OnClientEvent:Connect(function(op: any, ...: any)
			if type(op) == "number" and handler ~= nil then
				-- (timed: applying the server's updates is most of a public match's script, and it runs
				-- here, outside every per-frame step; UI/Telemetry "slow" reads net.busy_s)
				local t0 = os.clock()
				handler(op, ...)
				net.busy_s += os.clock() - t0
			end
		end)
		to_server = ts
		net.connected = true
		ts:FireServer(OP.HELLO)
	end)
	env.net = net
	return env
end

-- =============================================================================================
-- Construction
-- =============================================================================================

Session.IS_STUDIO = (game :: any) ~= nil and game:GetService("RunService"):IsStudio()

function Session.new(env: { [string]: any }?)
	local self: any = setmetatable({}, Session)
	self.env = env or roblox_env()
	self.state_ready = Signal.new() -- (state)
	self.mode_changed = Signal.new() -- (mode)
	self.lobby_updated = Signal.new() -- (info)
	--- (list) the game-wide public lobbies (hub servers; LobbyRules.public_view rows)
	self.lobbies_updated = Signal.new()
	--- (reason) a join_lobby that did not teleport
	self.join_failed = Signal.new()
	self.lobbies = nil :: { any }?
	--- the kinds of public match Quick Play offers on this hub ("ffa", "world", "team"; nil: not a hub)
	self.lobby_kinds = nil :: { string }?
	--- (state) Quick Play: { state = "joining" | "line" | "going" | "idle", mode, info } (PUBLIC_STATE)
	self.public_changed = Signal.new()
	--- RoPlague: the Plague Race changed (started, standings, over, or nil: no race any more)
	self.race_changed = Signal.new()
	self.public = { state = "idle" } :: { [string]: any }
	--- Game admins only (the server sends it to nobody else): owner id → true for bot players.
	self.admin_bots = nil :: { [number]: boolean }?
	self.admin_changed = Signal.new()
	--- the mode `state` belongs to (MODE_TITLE for the title backdrop even while queued)
	self.state_mode = MODE_TITLE
	self._auto_joined = false
	self.joined_owner = Signal.new() -- (owner_id)
	--- Short player-facing notices from the session (connection lost, match closed...).
	self.notice = Signal.new() -- (text, severity)
	--- A local match (title/solo) is being prepared; state_ready follows.
	self.building_started = Signal.new() -- (mode)
	--- Saved per-player settings arrived from the server (load_settings has data from now on).
	self.settings_loaded = Signal.new()
	--- Bought, unspent credits (Data/Products kind -> count) from the server (server/Purchases).
	self.credits = {} :: { [string]: number }
	self.credits_changed = Signal.new() -- (credits)
	self.credit_result = Signal.new() -- (kind, ok, reason?) the answer to use_credit
	--- (owner_id) solo: the player took over the nation that eliminated them
	self.took_over = Signal.new()
	--- Cosmetics (Data/Cosmetics) from the server: owned (set), equipped { skin?, flag? },
	--- crates_bought, crates_allowed (false where paid random items are restricted, or not checked yet).
	--- The Arsenal (Data/Arsenal): `stars` = the Stars balance (Data/Stars), `unlocks` = the items
	--- unlocked (set), `loaded` once the server's inventory arrived. `starter`: the starter pack's offer
	--- (Session._starter_of; false = none).
	self.inventory = {
		owned = {},
		equipped = {},
		crates_bought = 0,
		crates_allowed = false,
		stars = 0,
		unlocks = {},
		loaded = false,
		starter = false,
	}
	self.inventory_changed = Signal.new() -- (inventory)
	--- ({ lines = { { key, amount } }, total, balance, mode }) Stars paid for a match (server/Rewards)
	self.stars_awarded = Signal.new()
	--- the last payout of the match on screen (nil until one arrives; cleared when a match starts)
	self.last_award = nil :: any
	--- (key, ok, reason?) the answer to buy_unlock
	self.unlock_result = Signal.new()
	--- (going: boolean) the answer to hop_solo: true = a teleport to a fresh server is on its way
	self.hop_result = Signal.new()
	--- (key) an Arsenal item was just unlocked (Stars or Robux)
	self.unlocked = Signal.new()
	--- solo: the match's results for its Stars (Stars.Tracker), and whether this life was reported
	self._tracker = nil :: any
	self._solo_reported = false
	self.crate_result = Signal.new() -- (ok, item_id | reason) an open_crate's answer
	--- RoWorld General (Data/Subscription; server/General): subscribed, as the server last said
	self.general = false
	--- (on: boolean, given: { crate?, stars?, skin? }?) the server's word: subscribed or not, and what
	--- the day's perks just gave
	self.general_changed = Signal.new()
	--- (state) the player's party (server/Party.state; team games on: staging only for now)
	self.party_changed = Signal.new()
	--- the last party state (nil: parties are off on this server)
	self.party = nil :: any
	--- the last COSMETICS map of the public match (who wears what), applied to every rebuilt mirror
	self._cosmetics_map = {} :: { [any]: any }

	self.mode = MODE_TITLE
	self.state = nil :: any
	self.difficulty = 1
	--- Last lobby info received from the server.
	self.lobby = {
		available = false,
		stage = Session.STAGE_IDLE,
		countdown_s = 0.0,
		elapsed_s = 0.0,
		players = {},
		in_match = false,
	}
	--- When false, local matches are built and stepped synchronously (tests).
	self.threaded = true
	--- Local sim speed multiplier (title attract mode runs a little faster).
	self.local_speed = 1.0
	--- Solo only: freezes the local simulation (help / game menu open).
	self.paused = false
	self.mobile = self.env.mobile == true
	self.step_budget_s = if self.mobile then Session.STEP_BUDGET_MOBILE_S else Session.STEP_BUDGET_S
	self.step_budget_behind_s = if self.mobile then Session.STEP_BUDGET_BEHIND_MOBILE_S else Session.STEP_BUDGET_BEHIND_S
	self.build_budget_s = if self.mobile then Session.BUILD_BUDGET_MOBILE_S else Session.BUILD_BUDGET_S

	self._warming = false
	--- the waiting room's backdrop map (public match) and its shorter warm-up
	self._wait_map = nil :: string?
	self._wait_warmup = false
	self._warm_target = Session.TITLE_WARMUP_TICKS
	--- Map ids being downloaded (see _fetch_map).
	self._map_fetching = {} :: { [string]: boolean }
	--- Map id of the last solo match started (nil = default).
	self.map_id = nil :: string?
	self._build_job = nil :: any
	self._build_serial = 0
	self._build_mode = MODE_TITLE
	self._title_restart_pending = false

	-- Local (title / solo) simulation
	self._sim = nil :: any
	--- the tick in progress: the Sim's step as a Coop job (see _local_process), and the time it took
	self._step_job = nil :: any
	self._step_spent = 0.0
	self._acc = 0.0
	self._queued = {} :: { any }
	self._last_delta = self.env.now()

	-- Multiplayer (client side)
	self._mp_waiting = false
	--- Left a multiplayer match; the title world being built must switch the mode back to TITLE.
	--- (session.gd kept MODE_MULTI after leaving a match, so its UI showed the HUD over the title
	--- globe; fixed here.)
	self._mp_leaving = false
	self._join_job = nil :: any
	self._join_owner = 0
	self._join_deltas = {} :: { any }
	self._net_warned = false
	--- When the last JOIN was sent (JOIN_RETRY_S).
	self._join_sent_at = -math.huge
	--- When the last RESYNC was requested (RESYNC_GAP_S); a mirror refresh is awaited while set.
	self._resync_at = -math.huge
	self._resync_pending = false
	--- True when the state last announced (state_ready) replaced the same match's after a resync.
	self.state_is_resync = false
	self._active_sent_at = -math.huge

	-- Settings (persisted by the server per account; see ServerMain)
	self._settings = {} :: { [string]: { [string]: any } }
	self.settings_ready = false
	--- section -> time of the last SETTING sent; sections whose latest value still has to go out.
	self._settings_sent_at = {} :: { [string]: number }
	self._settings_dirty = {} :: { [string]: boolean }

	-- Instrumentation (dev harness / tests)
	--- (process_s: all of process(), the local Sim's steps among it)
	self.perf = {
		steps = 0,
		step_s = 0.0,
		step_s_max = 0.0, -- a whole tick's step (over the frames it took)
		step_slice_max = 0.0, -- the most one frame spent on the Sim
		build_s = 0.0,
		build_frames = 0,
		build_slice_max = 0.0,
		process_s = 0.0,
	}

	local net = self.env.net
	if net ~= nil then
		net.listen(function(op: number, ...: any)
			self:_on_net(op, ...)
		end)
	end
	return self
end

--- Roblox: drive the session from the render loop (priority First, so views read a fresh render_tick).
function Session.bind(self: any)
	local RunService = game:GetService("RunService")
	-- (the frame's dt: a Studio film steps it, Map/FrameClock)
	local FrameClock = require((script :: any).Parent:WaitForChild("Map"):WaitForChild("FrameClock")) :: any
	RunService:BindToRenderStep("AirfrontSession", Enum.RenderPriority.First.Value, function(dt: number)
		local t0 = os.clock()
		self:process(FrameClock.dt(dt))
		self.perf.process_s += os.clock() - t0
	end)
end

-- =============================================================================================
-- Public API
-- =============================================================================================

--- Starts (asynchronously) the title attract simulation; state_ready fires when it is live.
function Session.start_title(self: any)
	self:_leave_multiplayer_if_needed()
	self._trailer = false
	self._wait_map = nil
	-- RoPlague: the backdrop is a plague spreading across the real world by itself (a bot plays it)
	self:_start_local(MODE_TITLE, {
		seed = self:_rand_seed(),
		difficulty = 1,
		max_humans = 0,
		time_limit_s = 0,
		map_id = nil,
		auto = true,
		strategy = "balanced",
		zero_after = 0,
	}, "")
end

--- Public-match waiting room: rebuild the backdrop on the lobby's map `map_id` (the AI backdrop,
--- shortly warmed up) so players see what they are about to play. Stays in the multiplayer flow.
function Session._show_wait_map(self: any, map_id: string)
	if self._wait_map == map_id then
		return
	end
	self._wait_map = map_id
	self._wait_warmup = true
	self:_start_local(MODE_TITLE, {
		seed = self:_rand_seed(),
		difficulty = 1,
		tribes = Session.TITLE_TRIBES,
		max_humans = 0,
		time_limit_s = 0,
		map_id = map_id,
	}, "")
end

--- Starts (asynchronously) a solo campaign on map `map_id` (MapList id; nil = the default map);
--- state_ready then joined_owner fire when it is live (after downloading the map if needed).
--- `opts.tribes`: how many tribes the map gets; `opts.countdown_ticks`: ticks from placing the capital
--- to the start (the tutorial's match has fewer tribes and starts at once: Data/Tutorial).
function Session.start_solo(self: any, p_difficulty: number, map_id: string?, opts: any?)
	self:_leave_multiplayer_if_needed()
	self._trailer = false
	self.difficulty = math.clamp(math.floor(tonumber(p_difficulty) or 1), 0, 2)
	-- (RoPlague: the World map carries the country layer, so every solo match plays on it)
	self.map_id = nil
	local _ = map_id
	local tribes = if type(opts) == "table" and type(opts.tribes) == "number" then opts.tribes else Session.SOLO_TRIBES
	local countdown = if type(opts) == "table" and type(opts.countdown_ticks) == "number"
		then opts.countdown_ticks
		else nil
	-- RoPlague: the strain's starting evolution and the plague's name (the player's nation)
	local plague_name = if type(opts) == "table" and type(opts.name) == "string" and opts.name ~= ""
		then opts.name
		else self:local_display_name()
	self:_start_local(MODE_SOLO, {
		-- (a Plague Race: every racer's world from the same seed)
		seed = if type(opts) == "table" and type(opts.seed) == "number" then opts.seed else self:_rand_seed(),
		difficulty = self.difficulty,
		tribes = tribes,
		solo_countdown_ticks = countdown,
		max_humans = 1,
		time_limit_s = 0,
		map_id = self.map_id,
		strain_start = if type(opts) == "table" then opts.strain_start else nil,
		cure = if type(opts) == "table" and opts.tutorial == true then false else nil,
		name = plague_name,
		-- RoPlague: the shop's perks the player owns (Data/Arsenal), applied by PlagueSim
		perks = table.clone(self.inventory.unlocks or {}),
	}, plague_name)
	self.solo_speed = 1.0
end

--- RoPlague: the in-game trailer's match (Trailer/Director, 2026-10-31). A local shared world like a Plague
--- Race's: the player's plague and a rival the trailer plays itself (`plagues` = their specs, the player's
--- first). It plays like a solo match but earns nothing: no Stars tracker, no solo report.
function Session.start_trailer(self: any, opts: { [string]: any })
	self:_leave_multiplayer_if_needed()
	self.difficulty = 1
	self.map_id = nil
	self._trailer = true
	local name = if type(opts.name) == "string" and opts.name ~= "" then opts.name else self:local_display_name()
	self:_start_local(MODE_SOLO, {
		seed = if type(opts.seed) == "number" then opts.seed else self:_rand_seed(),
		difficulty = 1,
		tribes = Session.SOLO_TRIBES,
		max_humans = 1,
		time_limit_s = 0,
		map_id = nil,
		mode = "race",
		name = name,
		plagues = opts.plagues,
		perks = {},
	}, name)
	self.solo_speed = 1.0
end

--- The trailer's match only (Trailer/Director): runs fn(sim) between ticks (PlagueSim.dev_delta) and mirrors
--- the result. False when there is no trailer match.
function Session.trailer_apply(self: any, fn: (any) -> ()): boolean
	local sim = self._sim
	local state = self.state
	if not self._trailer or self.mode ~= MODE_SOLO or sim == nil or state == nil or type(sim.dev_delta) ~= "function" then
		return false
	end
	self:_settle_step()
	if self._sim ~= sim then
		return false
	end
	self:_apply(state, sim:dev_delta(fn))
	return true
end

--- RoPlague: applies an intent to the local match at once, even while it is paused (the Evolve
--- screen), and mirrors the result. Falls back to the normal queue when there is no local match.
function Session.send_now(self: any, intent: { [string]: any }): boolean
	local sim = self._sim
	local state = self.state
	if self.mode ~= MODE_SOLO or sim == nil or state == nil or type(sim.apply_now) ~= "function" then
		self:send_intent(intent)
		return false
	end
	self:_settle_step()
	if self._sim ~= sim then
		return false
	end
	self:_apply(state, sim:apply_now(state.local_owner, intent))
	return true
end

--- RoPlague: renames the plague of the running solo match (the name was already filtered by
--- server/PlagueRename). Later snapshots and news carry it.
function Session.rename_plague(self: any, name: string)
	local sim = self._sim
	local state = self.state
	if self.mode ~= MODE_SOLO or type(name) ~= "string" or name == "" then
		return
	end
	if sim ~= nil and sim.plague_name ~= nil then
		sim.plague_name = name
	end
	local pl = if state ~= nil then state.plague else nil
	if pl ~= nil then
		pl.name = name
		local o = state.owners[pl.pid]
		if o ~= nil then
			o.name = name
		end
		state.plague_changed:Fire()
	end
end

--- RoPlague: the solo match's speed (0 pauses; 1, 2 or 4 times). The title backdrop ignores it.
function Session.set_speed(self: any, speed: number)
	speed = math.clamp(tonumber(speed) or 1, 0, 8)
	-- (a Plague Race runs at everyone's same speed, and doesn't stop)
	if self.race ~= nil then
		return
	end
	self.solo_speed = speed
	if self.mode == MODE_SOLO and self.state_mode == MODE_SOLO then
		self.local_speed = math.max(speed, 0)
	end
end

--- Starts downloading map `id` unless it is available locally or already on its way. Build / join
--- jobs wait while self._map_fetching[id] is set.
function Session._fetch_map(self: any, id: string?)
	if type(id) ~= "string" or self._map_fetching[id] then
		return
	end
	local fetch = self.env.fetch_map_async
	local WorldMap = self:_core("WorldMap")
	if fetch == nil or WorldMap == nil or WorldMap.available(id) then
		return
	end
	self._map_fetching[id] = true
	fetch(id, function(ok: boolean, err: string?)
		self._map_fetching[id] = nil
		if not ok then
			self:_warn_once("[Session] could not download map " .. id .. ": " .. tostring(err))
		end
	end)
end

--- Loads map `id`'s data module (nil = the default map) outside the Coop jobs — requiring can
--- yield under Lune, which a job coroutine must not. Server-only maps load later (downloads).
function Session._preload_map(self: any, id: string?)
	local WorldMap = self:_core("WorldMap")
	if WorldMap ~= nil then
		pcall(WorldMap.load_data, if type(id) == "string" then id else WorldMap.DEFAULT)
	end
end

--- Inside a Coop job: waits (yielding frames) until map `id` is available; the map, or an error.
function Session._await_map(self: any, WorldMap: any, id: string?): any
	if type(id) == "string" and not WorldMap.available(id) then
		self:_fetch_map(id)
		while self._map_fetching[id] do
			coroutine.yield()
		end
	end
	return WorldMap.get(id)
end

--- True while a local match is being prepared (UI can show a "Deploying…" state).
function Session.is_building(self: any): boolean
	return self._build_job ~= nil
end

function Session.set_paused(self: any, on: boolean)
	-- (a Plague Race never pauses: the other racers' worlds don't)
	self.paused = on and self.race == nil
end

--- The player's equipped cosmetics on owner `id` of the local match (solo).
function Session._apply_own_cosmetics(self: any, id: number)
	local st = self.state
	if st == nil or type(st.set_cosmetics) ~= "function" then
		return
	end
	local eq = self.inventory.equipped or {}
	-- (and their own head shot beside their name, as in a public match)
	local uid = if type(self.env.user_id) == "function" then self.env.user_id() else 0
	-- (RoPlague: and the infection colour their plague wears, an item id "shop_<strain key>")
	st:set_cosmetics({ [id] = { skin = eq.skin, flag = eq.flag, face = uid, color = eq.color } }, true)
end

--- Does the player have Arsenal item `key`?
function Session.has_unlock(self: any, key: string): boolean
	return self.inventory.unlocks[key] == true
end

--- Unlock Arsenal item `key` with Stars (the answer comes as unlock_result; the inventory follows).
function Session.buy_unlock(self: any, key: string): boolean
	local net = self.env.net
	if net == nil or not net.connected or type(net.send) ~= "function" then
		return false
	end
	net.send(OP.BUY_UNLOCK, key)
	return true
end

--- The starter pack's offer from an INVENTORY payload (server/Purchases.starter_state): false, or
--- { state = "ready" } (not shown yet), or { state = "active", ends_at = os.clock() when it ends }.
function Session._starter_of(v: any): any
	if type(v) ~= "table" then
		return false
	end
	if v.state == "ready" then
		return { state = "ready" }
	end
	local left = tonumber(v.left)
	if v.state == "active" and left ~= nil and left == left and left > 0 then
		return { state = "active", ends_at = os.clock() + left }
	end
	return false
end

--- The starter pack's offer is on the player's screen: the server starts its clock (once). The
--- inventory that follows carries it as active.
function Session.starter_seen(self: any): boolean
	local net = self.env.net
	if net == nil or not net.connected or type(net.send) ~= "function" then
		return false
	end
	net.send(OP.STARTER_SEEN)
	return true
end

--- Rofront Staging, and game admins on production (the server refuses it from anyone else): be a
--- new player again — no match counted, the tutorial's Stars and the first crate's price on offer
--- again (2026-10-04, the menu's "Replay as new player").
function Session.new_player(self: any): boolean
	local net = self.env.net
	if net == nil or not net.connected or type(net.send) ~= "function" then
		return false
	end
	net.send(OP.NEW_PLAYER)
	return true
end

--- Hub: this server is outdated and a solo match is about to start: ask to be sent to a fresh
--- server to play it there (server/FreshServers; answered with hop_result). False when the server
--- can't be asked.
function Session.hop_solo(self: any, difficulty: number, map_id: string?): boolean
	local net = self.env.net
	if net == nil or not net.connected or type(net.send) ~= "function" then
		return false
	end
	net.send(OP.SOLO_HOP, difficulty, map_id)
	return true
end

--- Solo: the local player's nation plays with the Arsenal they have unlocked.
function Session._apply_own_unlocks(self: any)
	local sim = self._sim
	local st = self.state
	if self.mode ~= MODE_SOLO or sim == nil or st == nil or (st.local_owner or 0) == 0 then
		return
	end
	if type(sim.set_unlocks) == "function" then
		self:_settle_step()
		if self._sim ~= sim then
			return
		end
		sim:set_unlocks(st.local_owner, Arsenal.mask(self.inventory.unlocks))
	end
end

--- Solo: report this life's result for its Stars, once (server/Rewards answers with STARS). `left` =
--- the player is walking away from a match that goes on.
function Session._solo_report(self: any, left: boolean)
	local tracker = self._tracker
	local st = self.state
	if tracker == nil or self._solo_reported or st == nil or (st.local_owner or 0) == 0 then
		return
	end
	local result = tracker:result(st.local_owner, left)
	if not result.spawned then
		return
	end
	self._solo_reported = true
	local net = self.env.net
	if net ~= nil and net.connected and type(net.send) == "function" then
		net.send(OP.SOLO_RESULT, result)
	end
end

--- Open one bought crate (the answer comes as crate_result; the inventory follows).
function Session.open_crate(self: any): boolean
	local net = self.env.net
	if net == nil or not net.connected or type(net.send) ~= "function" then
		return false
	end
	net.send(OP.OPEN_CRATE)
	return true
end

--- Wear an owned cosmetic in `slot` ("skin" / "flag"), or none (id false).
function Session.equip(self: any, slot: string, id: string | false): boolean
	local net = self.env.net
	if net == nil or not net.connected or type(net.send) ~= "function" then
		return false
	end
	net.send(OP.EQUIP, slot, id)
	return true
end

--- Ask the server to spend one bought `kind` credit (the answer comes as credit_result). `target`:
--- a public match's takeover, which the server makes itself.
function Session.use_credit(self: any, kind: string, target: number?): boolean
	local net = self.env.net
	if net == nil or not net.connected or type(net.send) ~= "function" then
		return false
	end
	net.send(OP.USE_CREDIT, kind, target)
	return true
end

--- Could the fallen player take over nation `target` now? Solo: the local Sim decides
--- (Sim.can_take_over). A public match: this client's mirror says so (the server checks again).
function Session.can_take_over(self: any, target: number): boolean
	local st = self.state
	if st == nil then
		return false
	end
	if self.mode == MODE_SOLO then
		local sim = self._sim
		return sim ~= nil and type(sim.can_take_over) == "function" and sim:can_take_over(st.local_owner or 0, target)
	end
	if self.mode ~= MODE_MULTI or self.state_mode ~= MODE_MULTI then
		return false
	end
	local me = st.owners[st.local_owner or 0]
	local o = st.owners[target]
	return me ~= nil
		and not me.alive
		and o ~= nil
		and o.alive
		and o.kind == 0 -- Defs.KIND_NATION: never a tribe or a (bot) player
		and (o.tiles or 0) > 0
		and st.phase == 1 -- Defs.PHASE_PLAYING
end

--- Solo: the fallen player takes command of `target` (after its credit was spent). True when done.
function Session.take_over(self: any, target: number): boolean
	if not self:can_take_over(target) then
		return false
	end
	local st = self.state
	self:_settle_step()
	if self._sim == nil or not self._sim:take_over(st.local_owner, target) then
		return false
	end
	-- a new life: its Stars are counted from here (the first was reported when it fell)
	if self._tracker ~= nil then
		self._tracker:adopt(st.local_owner, target)
		self._solo_reported = false
	end
	self.last_award = nil
	st.local_owner = target
	table.clear(self._queued)
	self:_apply_own_cosmetics(target)
	self:_emit("took_over", target)
	return true
end

function Session.join_multiplayer(self: any)
	if not self:multiplayer_available() then
		self:_emit("notice", "Multiplayer is unavailable right now. Try again in a moment.", Session.NOTICE_WARNING)
		return
	end
	self._mp_waiting = true
	self._mp_leaving = false
	self:_set_mode(MODE_MULTI)
	self:_send_join()
end

--- Public lobby: ask the hub to teleport us to that lobby's match server.
function Session.join_lobby(self: any, id: string)
	if not self:multiplayer_available() then
		self:_emit("notice", "Multiplayer is unavailable right now. Try again in a moment.", Session.NOTICE_WARNING)
		self:_emit("join_failed", "offline")
		return
	end
	self.env.net.send(OP.JOIN_LOBBY, id)
end

--- Quick Play: a seat in the soonest public match of `mode` ("ffa" | "team" | "world"; a party leader: for the
--- party). The hub answers with PUBLIC_STATE (in line while every match of the kind is full).
--- RoPlague: `mode` is one of its multiplayer modes (Data/PlagueModes); `role` a 1v1's side.
function Session.join_public(self: any, mode: string, role: string?)
	if not self:multiplayer_available() then
		self:_emit("notice", "Multiplayer is unavailable right now. Try again in a moment.", Session.NOTICE_WARNING)
		self:_emit("join_failed", "offline")
		return
	end
	self.env.net.send(OP.JOIN_PUBLIC, mode, role)
end

--- RoPlague: true for one of its multiplayer modes' keys (Data/PlagueModes).
function Session._plague_mode(m: any): boolean
	return m == "coop" or m == "race" or m == "duel" or m == "teams"
end

-- =============================================================================================
-- RoPlague's Plague Race (Data/PlagueModes "race"; server/PlagueMatch.Race): every racer plays the same
-- world (one seed) here on their own client; the server shows the standings and calls the winner.
-- self.race = { seed, racers, standings, over (winner + standings) | nil, done (sent) }
-- =============================================================================================

--- Seconds between progress reports.
Session.RACE_REPORT_S = 1.0

function Session._on_race(self: any, what: any, data: any)
	if what == "start" and type(data) == "table" then
		local seed = math.floor(tonumber(data.seed) or 1)
		if self.race ~= nil and self.race.seed == seed and self.mode == MODE_SOLO then
			return -- (sent again after a reconnect: the race is on here already)
		end
		self.race = {
			seed = seed,
			racers = if type(data.racers) == "table" then data.racers else {},
			standings = {},
			over = nil,
			done = false,
			report_t = 0,
		}
		self:start_solo(1, nil, { seed = seed, name = self._race_name, race = true })
		self:_emit("race_changed", self.race)
	elseif what == "standings" and self.race ~= nil and type(data) == "table" then
		self.race.standings = data
		self:_emit("race_changed", self.race)
	elseif what == "over" and self.race ~= nil and type(data) == "table" then
		self.race.over = data
		self.race.standings = if type(data.standings) == "table" then data.standings else self.race.standings
		-- (everyone's world stops: the race is decided)
		self.local_speed = 0
		self.solo_speed = 0
		self:_emit("race_changed", self.race)
	elseif what == "home" then
		-- (Studio: the race is over, back to the title here)
		self.race = nil
		self:start_title()
		self:_emit("race_changed", nil)
	end
end

--- In a race: the local match's progress to the server once a second, and its end once.
function Session._race_report(self: any, dt: number)
	local race = self.race
	local st = self.state
	if race == nil or self.mode ~= MODE_SOLO or st == nil or st.plague == nil or race.over ~= nil then
		return
	end
	local net = self.env.net
	if net == nil then
		return
	end
	local p = st.plague
	local world = math.max(1, (p.H or 0) + (p.I or 0) + (p.D or 0))
	race.report_t += dt
	if race.report_t >= Session.RACE_REPORT_S then
		race.report_t = 0
		local countries = 0
		for _, r in p.countries or {} do
			if (r.I or 0) >= 1 or (r.D or 0) >= 1 then
				countries += 1
			end
		end
		net.send(OP.RACE, "report", {
			dead = (p.D or 0) / world,
			infected = (p.I or 0) / world,
			cure = p.cure or 0,
			countries = countries,
		})
	end
	if not race.done and st.phase == 3 then
		race.done = true
		local reason = st.over_reason
		local Defs = self:_core("Defs")
		local why = if Defs ~= nil and reason == Defs.OVER_EXTINCT
			then "extinct"
			elseif Defs ~= nil and reason == Defs.OVER_CURED then "cured"
			else "burnout"
		net.send(OP.RACE, "done", why)
	end
end

--- RoPlague: leaving a race (or any match on the online place) goes back to the lobby place.
function Session.leave_race(self: any)
	local net = self.env.net
	if net ~= nil then
		net.send(OP.RACE, "leave")
	end
end

--- Quick Play: leave the line.
function Session.leave_line(self: any)
	if self:multiplayer_available() then
		self.env.net.send(OP.JOIN_PUBLIC, false)
	end
end

--- Public-match waiting room: toggle our vote to start early (more than half of the players).
function Session.vote_start(self: any)
	if self:multiplayer_available() then
		self.env.net.send(OP.VOTE_START)
	end
end

--- Parties (server/Party; team games on): `action` "invite" | "accept" | "decline" | "kick" (with a
--- user id) or "leave".
function Session.party_action(self: any, action: string, user_id: number?)
	if self.party ~= nil and self:multiplayer_available() then
		self.env.net.send(OP.PARTY, action, user_id)
	end
end

--- In a party (with others), and whether this player leads it (it picks the match).
function Session.in_party(self: any): (boolean, boolean)
	local p = self.party
	if p == nil or type(p.members) ~= "table" or #p.members < 2 then
		return false, true
	end
	return true, p.leader == true
end

--- A Creator Dashboard milestone (UI/Telemetry → server/Analytics). False when it could not be sent
--- (not connected yet).
function Session.report(self: any, kind: string, a: any?, b: any?, c: any?): boolean
	local net = self.env.net
	if net == nil or not net.connected or type(net.send) ~= "function" then
		return false
	end
	net.send(OP.ANALYTICS, kind, a, b, c)
	return true
end

--- Hub: watch a running public match (the server teleports us there as a spectator).
function Session.spectate_lobby(self: any, id: string)
	if not self:multiplayer_available() then
		self:_emit("notice", "Multiplayer is unavailable right now. Try again in a moment.", Session.NOTICE_WARNING)
		self:_emit("join_failed", "offline")
		return
	end
	self.env.net.send(OP.SPECTATE_LOBBY, id)
end

function Session._send_join(self: any)
	self._join_sent_at = self.env.now()
	self.env.net.send(OP.JOIN, self:local_display_name())
end

--- The player touched the controls (Main calls this on user input). In multiplayer the server hears
--- about it at most every ACTIVE_GAP_S, so a player who is watching is not dropped as idle at the
--- rematch (session.gd only counted intents).
function Session.note_activity(self: any)
	if self.mode ~= MODE_MULTI then
		return
	end
	local now = self.env.now()
	if now - self._active_sent_at < Session.ACTIVE_GAP_S or not self:multiplayer_available() then
		return
	end
	self._active_sent_at = now
	self.env.net.send(OP.ACTIVE)
end

function Session.leave_match(self: any)
	-- never auto-join this server's public match again after leaving it (Studio plays lobbies on the
	-- hub server itself, which would otherwise queue us straight back in)
	self._auto_joined = true
	-- Leaving the multiplayer queue while the title globe is still simulating: keep that world.
	if self.mode == MODE_MULTI and self._sim ~= nil and self.state ~= nil and self.state.local_owner == 0 then
		self:_leave_multiplayer_if_needed()
		self:_set_mode(MODE_TITLE)
		return
	end
	self:start_title()
end

function Session.send_intent(self: any, intent: { [string]: any })
	if self.mode == MODE_MULTI then
		if self:multiplayer_available() and self.state ~= nil and self.state.local_owner ~= 0 and self._sim == nil then
			local b = Protocol.encode_intent(intent)
			if b ~= nil then
				self.env.net.send(OP.INTENT, b)
			end
		end
		return
	end
	if self.mode == MODE_SOLO and self._sim ~= nil then
		table.insert(self._queued, intent)
	end
end

function Session.multiplayer_available(self: any): boolean
	local net = self.env.net
	return net ~= nil and net.connected == true and self.lobby.available == true
end

--- "connected", "connecting" or "offline" — for the title screen's multiplayer card.
function Session.multiplayer_status(self: any): string
	local net = self.env.net
	if net == nil then
		return "offline"
	end
	if self:multiplayer_available() then
		return "connected"
	end
	if net.connected and self.lobby.closed then
		return "offline"
	end
	return "connecting"
end

function Session.local_display_name(self: any): string
	local f = self.env.display_name
	local n = if f then f() else nil
	if type(n) == "string" and n ~= "" then
		return n
	end
	return "Commander"
end

--- Current local sim (title/solo only; nil in multiplayer). Tests, tools and the tutorial; a tick in
--- progress is finished first, so a caller may change the Sim.
function Session.local_sim(self: any): any
	self:_settle_step()
	return self._sim
end

-- ---------------------------------------------------------------------------------------------
-- Settings (session.gd's user://settings.cfg sections; Roblox has no client files, so the server
-- keeps them per account in a DataStore)
-- ---------------------------------------------------------------------------------------------

--- A copy of a saved settings section ({} until the server's copy arrives; see settings_loaded).
--- Nested tables (e.g. [ui] tips_seen) are copied too, so callers may modify what they get.
function Session.load_settings(self: any, section: string): { [string]: any }
	return Settings.copy_section(self._settings[section])
end

--- Saves a settings section: booleans, numbers, short strings and one nested level of those (e.g.
--- [ui] tips_seen = {expand = true, ...}); see Net/Settings for the limits. The server keeps exactly
--- what is kept here. Sends are throttled per section (the first at once, the latest value trails).
function Session.save_settings(self: any, section: string, values: { [string]: any })
	if not Settings.valid_name(section, Settings.MAX_SECTION_NAME) or type(values) ~= "table" then
		return
	end
	local clean = Settings.clean_section(values) :: { [string]: any }
	if self._settings[section] == nil then
		local n = 0
		for _ in self._settings do
			n += 1
		end
		if n >= Settings.MAX_SECTIONS then
			return
		end
	end
	self._settings[section] = clean
	self._settings_dirty[section] = true
	self:_flush_settings(false)
end

--- Sends every changed section whose throttle gap has passed (`force`: all of them now). With a
--- transport that delivers the saved settings (net.sends_settings), nothing is sent before they have
--- arrived: a section saved that early holds only this session's defaults + changes and would replace
--- the stored one; _on_settings merges it over the stored section first.
function Session._flush_settings(self: any, force: boolean)
	local net = self.env.net
	if net == nil or not net.connected or next(self._settings_dirty) == nil then
		return
	end
	if net.sends_settings == true and not self.settings_ready then
		return
	end
	local now = self.env.now()
	for section in self._settings_dirty do
		local last = self._settings_sent_at[section]
		if force or last == nil or now - last >= Session.SETTINGS_SEND_GAP_S then
			self._settings_dirty[section] = nil
			self._settings_sent_at[section] = now
			net.send(OP.SETTING, section, Settings.copy_section(self._settings[section]))
		end
	end
end

-- =============================================================================================
-- Frame processing
-- =============================================================================================

function Session.process(self: any, dt: number)
	if self._build_job ~= nil then
		self:_run_build()
	end
	if self._join_job ~= nil then
		self:_run_join()
	end
	if self._sim ~= nil then
		self:_local_process(dt)
	end
	if self.race ~= nil then
		self:_race_report(dt)
	end
	self:_update_render_tick(dt)
	if next(self._settings_dirty) ~= nil then
		self:_flush_settings(false)
	end
	if self._mp_waiting then
		self:_check_join()
	end
end

--- Queued, yet the server's lobby info says we are not in (our JOIN landed inside its cooldown after
--- a quick leave + re-queue, or was lost): ask again. JOIN is idempotent on the server.
function Session._check_join(self: any)
	if self.lobby.in_match == true or self._join_job ~= nil or not self:multiplayer_available() then
		return
	end
	if self.env.now() - self._join_sent_at >= Session.JOIN_RETRY_S then
		self:_send_join()
	end
end

function Session._rand_seed(_self: any): number
	return math.random(0, 2 ^ 31 - 2)
end

-- =============================================================================================
-- Local simulation
-- =============================================================================================

--- Prepares a local sim in a Coop job (see _build_local / _finish_build). The previous local world
--- keeps animating until the new one is ready. A newer request supersedes the one in flight.
function Session._start_local(self: any, new_mode: number, config: { [string]: any }, human_name: string)
	-- a solo match being left: its Stars so far
	if self.mode == MODE_SOLO and self.state_mode == MODE_SOLO then
		self:_solo_report(true)
	end
	self._tracker = nil
	if new_mode ~= MODE_TITLE or self.mobile then
		-- the old world stops while the new one is built (its last frame stays on screen): two
		-- worlds at once ran phones out of memory ("could not build the match: not enough memory")
		self:_stop_local()
	end
	self:_preload_map(config.map_id)
	self._build_serial += 1
	self._build_mode = new_mode
	self:_emit("building_started", new_mode)
	local serial = self._build_serial
	local job = Coop.job(function()
		return self:_build_local(config, human_name, serial)
	end)
	self._build_job = job
	if not self.threaded then
		job:finish()
		self:_run_build()
	end
end

--- Core modules in dependency order: the first build requires them one per Coop slice (each is a
--- few ms to load) instead of all at once inside `require(Sim)`.
Session.WARM_MODULES = {
	"Signal",
	"Defs",
	"Ev",
	"Rng",
	"Rules",
	"WorldMap",
	"SimColors",
	"SimNav",
	"SimState",
	"SimAttacks",
	"SimStructures",
	"SimNaval",
	"SimWarships",
	"SimNukes",
	"SimAIEconomy",
	"SimAI",
	"GameState",
	"Sim",
	"Plague/PlagueRules",
	"Plague/Countries",
	"Plague/Reach",
	"Plague/PlagueBot",
	"Plague/PlagueSim",
	"Plague/PlagueStars",
}
--- RoPlague: the simulation local matches (solo and the title backdrop) run. Multiplayer keeps RoWorld's
--- server-side Sim.
Session.SIM_MODULE = "Plague/PlagueSim"

--- Builds the Sim, the optional human and the client mirror. Runs inside a Coop job.
function Session._build_local(self: any, config: { [string]: any }, human_name: string, serial: number)
	if not self._warm then
		for _, name in Session.WARM_MODULES do
			self:_core(name)
			Coop.check()
		end
	end
	local Sim = self:_core(Session.SIM_MODULE) or self:_core("Sim")
	local GameState = self:_core("GameState")
	local WorldMap = self:_core("WorldMap")
	if Sim == nil or GameState == nil or WorldMap == nil then
		return { missing = true, serial = serial }
	end
	local map = self:_await_map(WorldMap, config.map_id)
	Coop.check()
	if not self._warm then
		-- The water-navigation regions (~30 ms) are a shared cache Sim.new would build in one go.
		local SimNav = self:_core("SimNav")
		if SimNav ~= nil and type(SimNav.shared) == "function" then
			SimNav.shared(map)
		end
		-- the country layer (decoded once per map)
		local Countries = self:_core("Plague/Countries")
		if Countries ~= nil then
			Countries.get(map)
		end
		self._warm = true
		Coop.check()
	end
	local sim = Sim.new(map, config)
	Coop.check()
	local id = 0
	if human_name ~= "" then
		id = sim:add_human("local", human_name)
		if type(config.strain_start) == "string" and type(sim.grant_evolution) == "function" then
			sim:grant_evolution(id, config.strain_start)
		end
	end
	local snap = sim:snapshot()
	Coop.check()
	local gs = GameState.new(map)
	gs:load_snapshot(snap)
	gs.local_owner = id
	return { sim = sim, state = gs, id = id, serial = serial }
end

function Session._core(self: any, name: string): any
	local f = self.env.require_core
	if f == nil then
		return nil
	end
	local ok, m = pcall(f, name)
	if ok then
		return m
	end
	return nil
end

function Session._run_build(self: any)
	local job = self._build_job
	local t0 = self.env.now()
	if not job.done then
		job:step(self.build_budget_s)
	end
	local slice = self.env.now() - t0
	local perf = self.perf
	perf.build_s += slice
	perf.build_frames += 1
	perf.build_slice_max = math.max(perf.build_slice_max, slice)
	job.time_s = (job.time_s or 0) + slice
	job.slice_max = math.max(job.slice_max or 0, slice)
	if not job.done then
		return
	end
	self._build_job = nil
	perf.last_build = { ms = job.time_s * 1000, frames = job.slices, slice_max_ms = job.slice_max * 1000 }
	if not job.ok then
		self:_warn_once("[Session] could not build the match: " .. tostring(job.err))
		self:_emit("notice", "Something went wrong starting the match. Please try again.", Session.NOTICE_ERROR)
		if self._build_mode ~= MODE_TITLE and self._sim == nil then
			self:start_title() -- (the old world was stopped for the build: bring the title back)
		end
		return
	end
	local r = job.result
	if r.missing then
		-- Sim / GameState not present yet (development builds): stay on the title with no world.
		self:_warn_once("[Session] Core Sim modules are not available; no local world")
		return
	end
	self:_finish_build(r)
end

--- Swaps in the freshly built local match.
function Session._finish_build(self: any, r: { [string]: any })
	self._title_restart_pending = false
	if r.serial ~= self._build_serial then
		return
	end
	table.clear(self._queued)
	self._acc = 0.0
	self.paused = false
	self._step_job = nil
	self._sim = r.sim
	self.state = r.state
	self._last_delta = self.env.now()
	if self._build_mode == MODE_TITLE then
		self.local_speed = Session.TITLE_WARMUP_SPEED
		self._warming = true
		self._warm_target = if self._wait_warmup then Session.WAIT_WARMUP_TICKS else Session.TITLE_WARMUP_TICKS
		self._wait_warmup = false
	else
		self.local_speed = if self._build_mode == MODE_SOLO then (self.solo_speed or 1.0) else 1.0
		self._warming = false
	end
	-- A title world that finishes building while the player is already queued for multiplayer
	-- only replaces the backdrop; it must not pull them out of the multiplayer flow.
	local queued_mp = self._mp_waiting or (self.mode == MODE_MULTI and not self._mp_leaving)
	if not (self._build_mode == MODE_TITLE and queued_mp) then
		self._mp_leaving = false
		self:_set_mode(self._build_mode)
	end
	-- the mode this state belongs to: a title world that lands while we wait for a multiplayer
	-- match stays a title backdrop (the UI must not take it for the match)
	self.state_mode = self._build_mode
	self.state_is_resync = false
	-- a solo match: the player wears their own cosmetics, plays with their own Arsenal, and the
	-- match is followed for its Stars
	self._tracker = nil
	self._solo_reported = false
	self.last_award = nil
	if self._build_mode == MODE_SOLO and r.id ~= 0 then
		self:_apply_own_cosmetics(r.id)
		self:_apply_own_unlocks()
	end
	-- (the trailer's match earns nothing: Session.start_trailer)
	if self._build_mode == MODE_SOLO and r.id ~= 0 and not self._trailer then
		-- (RoWorld's Stars tracker reads the war Sim's events; a plague match is followed by its own)
		if r.sim.cs == nil then
			self._tracker = Stars.Tracker.new(r.sim)
			self._tracker:watch(r.id)
		else
			local PlagueStars = self:_core("Plague/PlagueStars")
			if PlagueStars ~= nil then
				self._tracker = PlagueStars.new(r.sim)
				self._tracker:watch(r.id)
			end
		end
	end
	self:_emit("state_ready", self.state)
	local id = r.id
	if id ~= 0 then
		self:_emit("joined_owner", id)
	end
end

function Session._local_process(self: any, dt: number)
	local env = self.env
	if self.paused and self.mode == MODE_SOLO then
		self._last_delta = env.now()
		return
	end
	local state = self.state
	-- (a title backdrop behind the multiplayer waiting room warms up too, then slows down like the
	-- title's: it used to keep the 22x warm-up speed while the player waited)
	if self._warming and state ~= nil and state.tick >= (self._warm_target or Session.TITLE_WARMUP_TICKS) then
		self._warming = false
		self.local_speed = if self.mobile then Session.TITLE_SPEED_MOBILE else Session.TITLE_SPEED
	end
	local tick_sec = Session.TICK_SEC
	local cap = tick_sec * Session.MAX_STEPS_PER_TASK
	-- Studio only: workspace attribute AF_DEV_SPEED fast-forwards local matches (screenshots, tests)
	local dev_speed = 1.0
	if Session.IS_STUDIO then
		dev_speed = math.clamp(tonumber(workspace:GetAttribute("AF_DEV_SPEED")) or 1.0, 0.1, 20.0)
	end
	self._acc = math.min(self._acc + dt * self.local_speed * dev_speed, cap * dev_speed)
	if self._step_job == nil and self._acc < tick_sec then
		return
	end
	-- behind: a tick is in flight and the next is due already (or a time-lapse is owed two)
	local behind = self._acc >= tick_sec * (if self._step_job ~= nil then 1 else 2)
	local budget = if not self.threaded
		then math.huge
		elseif behind then self.step_budget_behind_s
		else self.step_budget_s
	local sim = self._sim
	local perf = self.perf
	local t0 = env.now()
	local done_ticks = 0
	while self._sim == sim do
		local job = self._step_job
		if job == nil then
			-- the next tick, while time is owed and the budget lasts
			if self._acc < tick_sec or done_ticks >= Session.MAX_STEPS_PER_TASK then
				break
			end
			if done_ticks > 0 and env.now() - t0 >= budget then
				break -- (the owed time stays in _acc, capped: a time-lapse slows down)
			end
			self._acc -= tick_sec
			if state ~= nil and state.local_owner ~= 0 then
				for _, intent in self._queued do
					sim:submit(state.local_owner, intent)
				end
			end
			table.clear(self._queued)
			job = Coop.job(sim.step, sim)
			self._step_job = job
			self._step_spent = 0.0
		end
		local left = budget - (env.now() - t0)
		if left <= 0 then
			break -- (it goes on next frame)
		end
		local s0 = env.now()
		local finished = job:step(left)
		local spent = env.now() - s0
		self._step_spent += spent
		perf.step_s += spent
		perf.step_slice_max = math.max(perf.step_slice_max or 0.0, spent)
		if not finished then
			break -- (next frame)
		end
		self._step_job = nil
		done_ticks += 1
		if not self:_step_done(job, sim) then
			break
		end
	end
end

--- A tick's step finished (job): its delta goes to the state. False when stepping must stop for this
--- frame (the title world ended, or the Sim was replaced).
function Session._step_done(self: any, job: any, sim: any): boolean
	if not job.ok then
		error(job.err, 0)
	end
	local perf = self.perf
	perf.steps += 1
	perf.step_s_max = math.max(perf.step_s_max, self._step_spent)
	local d = job.result
	local state = self.state
	local tracker = self._tracker
	if tracker ~= nil and state ~= nil then
		tracker:step(d.ev)
		if not self._solo_reported and tracker:final(state.local_owner) then
			self:_solo_report(false)
		end
	end
	if self:_apply_local_delta(d) then
		return false
	end
	return self._sim == sim
end

--- Finishes the tick in progress now (one long frame), so the caller may change the Sim: a take-over,
--- the player's Arsenal, the tutorial's gold. Nothing else may touch the Sim while its step is
--- suspended between frames.
function Session._settle_step(self: any)
	local job = self._step_job
	local sim = self._sim
	if job == nil or sim == nil then
		return
	end
	local s0 = self.env.now()
	job:finish()
	self._step_spent += self.env.now() - s0
	self.perf.step_s += self.env.now() - s0
	self._step_job = nil
	self:_step_done(job, sim)
end

--- Applies one local delta; true when the title world ended and a fresh one is being prepared.
function Session._apply_local_delta(self: any, d: { [string]: any }?): boolean
	local state = self.state
	if state == nil or d == nil then
		return false
	end
	self:_apply(state, d)
	self._last_delta = self.env.now()
	-- The title globe is an endless showcase: begin a fresh world when one is conquered.
	if self.mode == MODE_TITLE and state.phase == PHASE_OVER and not self._title_restart_pending then
		self._title_restart_pending = true
		local defer = self.env.defer
		if defer then
			defer(function()
				self:start_title()
			end)
		else
			self:start_title()
		end
		return true
	end
	return false
end

function Session._stop_local(self: any)
	self._sim = nil
	self._step_job = nil
	table.clear(self._queued)
end

function Session._update_render_tick(self: any, dt: number)
	local state = self.state
	if state == nil then
		return
	end
	local since = self.env.now() - self._last_delta
	local speed = if self.mode ~= MODE_MULTI then self.local_speed else 1.0
	local tick = state.tick
	local target = tick + math.clamp(since * Session.TICK_RATE * speed, 0.0, 1.25)
	local rt = state.render_tick
	if rt < tick - 5.0 or rt > target + 2.0 then
		state.render_tick = tick
	else
		local a = math.clamp(dt * 12.0, 0.0, 1.0)
		state.render_tick = math.max(rt, rt + (target - rt) * a)
	end
end

function Session._set_mode(self: any, new_mode: number)
	if self.mode == new_mode then
		return
	end
	self.mode = new_mode
	self:_emit("mode_changed", new_mode)
end

function Session._on_server_lost(self: any)
	-- Not in multiplayer, or already on the way back to the title (e.g. MATCH_CLOSED came first).
	if (self.mode ~= MODE_MULTI or self._mp_leaving) and not self._mp_waiting then
		return
	end
	self._mp_waiting = false
	self:_cancel_join()
	self:_emit("notice", "Lost connection to the game server. You're back at the title screen.", Session.NOTICE_ERROR)
	self:start_title()
end

function Session._leave_multiplayer_if_needed(self: any)
	if self.mode == MODE_MULTI or self._mp_waiting then
		self._mp_waiting = false
		self._mp_leaving = self.mode == MODE_MULTI
		self:_cancel_join()
		if self:multiplayer_available() then
			self.env.net.send(OP.LEAVE)
		end
	end
end

--- Fires one of our signals. A handler error (a view or UI bug) is reported once per signal and never
--- aborts the Session's own state change (Godot logs a handler error and carries on). Note: Core/Signal
--- stops at the first failing handler, so later handlers of that emission are skipped.
function Session._emit(self: any, name: string, ...: any)
	local sig = self[name]
	local ok, err = xpcall(sig.Fire, debug.traceback, sig, ...)
	if not ok then
		self._emit_warned = self._emit_warned or {}
		if not self._emit_warned[name] then
			self._emit_warned[name] = true
			local w = self.env.warn
			if w then
				w("[Session] a " .. name .. " handler failed: " .. tostring(err))
			end
		end
	end
end

--- Applies a delta to the mirror; a failing GameState signal handler is reported once and does not
--- stop the Session. Returns false when apply_delta raised (the mirror may be partly updated).
function Session._apply(self: any, state: any, d: { [string]: any }): boolean
	local ok, err = xpcall(state.apply_delta, debug.traceback, state, d)
	if not ok and not self._apply_warned then
		self._apply_warned = true
		local w = self.env.warn
		if w then
			w("[Session] applying a delta failed: " .. tostring(err))
		end
	end
	return ok
end

--- The multiplayer mirror missed or half-applied a delta: from here on it may diverge from the
--- server (wrong owners, phantom units) for the rest of the match, so ask for a fresh snapshot. The
--- server answers with its normal snapshot path (_on_snapshot handles one mid-match). Rate-limited
--- here and on the server.
function Session._request_resync(self: any)
	if self.mode ~= MODE_MULTI or self.state == nil or self._join_job ~= nil then
		return
	end
	local now = self.env.now()
	if now - self._resync_at < Session.RESYNC_GAP_S or not self:multiplayer_available() then
		return
	end
	self._resync_at = now
	self._resync_pending = true
	self.env.net.send(OP.RESYNC)
end

function Session._warn_once(self: any, text: string)
	if self._net_warned then
		return
	end
	self._net_warned = true
	local w = self.env.warn
	if w then
		w(text)
	end
end

-- =============================================================================================
-- Multiplayer — server messages
-- =============================================================================================

function Session._on_net(self: any, op: number, ...: any)
	if op == OP.DELTA then
		self:_on_delta(...)
	elseif op == OP.LOBBY then
		self:_on_lobby(...)
	elseif op == OP.SNAPSHOT then
		self:_on_snapshot(...)
	elseif op == OP.NOTICE then
		local text, severity = ...
		if type(text) == "string" then
			self:_emit("notice", text, tonumber(severity) or Session.NOTICE_INFO)
		end
	elseif op == OP.MATCH_CLOSED then
		self:_on_match_closed(...)
	elseif op == OP.SETTINGS then
		self:_on_settings(...)
	elseif op == OP.LOBBIES then
		local list, kinds = ...
		if type(list) == "table" then
			self.lobbies = list
			if type(kinds) == "table" then
				local k = {}
				for _, m in kinds do
					-- (RoPlague: the title's cards are its multiplayer modes, Data/PlagueModes)
					if m == "ffa" or m == "team" or m == "world" or Session._plague_mode(m) then
						table.insert(k, m)
					end
				end
				self.lobby_kinds = k
			end
			self:_emit("lobbies_updated", list)
		end
	elseif op == OP.PUBLIC_STATE then
		local st, mode, info = ...
		if st == "joining" or st == "line" or st == "going" or st == "idle" then
			self.public = {
				state = st,
				mode = if mode == "ffa" or mode == "team" or mode == "world" or Session._plague_mode(mode)
					then mode
					else nil,
				info = if type(info) == "table" then info else nil,
			}
			self:_emit("public_changed", self.public)
		end
	elseif op == OP.RACE then
		self:_on_race(...)
	elseif op == OP.JOIN_RESULT then
		local ok, reason = ...
		if ok ~= true then
			self:_emit("join_failed", if type(reason) == "string" then reason else "")
		end
	elseif op == OP.CREDITS then
		local c = ...
		local clean = {}
		if type(c) == "table" then
			for k, v in c do
				if type(k) == "string" and type(v) == "number" then
					clean[k] = v
				end
			end
		end
		self.credits = clean
		self:_emit("credits_changed", clean)
	elseif op == OP.INVENTORY then
		local inv = ...
		if type(inv) == "table" then
			local owned = {}
			for _, id in (if type(inv.owned) == "table" then inv.owned else {}) do
				if type(id) == "string" then
					owned[id] = true
				end
			end
			local eq = if type(inv.equipped) == "table" then inv.equipped else {}
			self.inventory = {
				owned = owned,
				equipped = {
					skin = if type(eq.skin) == "string" then eq.skin else nil,
					flag = if type(eq.flag) == "string" then eq.flag else nil,
					color = if type(eq.color) == "string" then eq.color else nil,
				},
				crates_bought = tonumber(inv.crates_bought) or 0,
				crates_allowed = inv.crates_allowed == true,
				stars = math.max(0, math.floor(tonumber(inv.stars) or 0)),
				unlocks = {},
				loaded = true,
				starter = Session._starter_of(inv.starter),
			}
			local was = self._unlocks_seen
			local fresh = {}
			for _, key in (if type(inv.unlocks) == "table" then inv.unlocks else {}) do
				if type(key) == "string" and Arsenal.item(key) ~= nil then
					self.inventory.unlocks[key] = true
					if was ~= nil and not was[key] then
						table.insert(fresh, key)
					end
				end
			end
			self._unlocks_seen = self.inventory.unlocks
			-- a solo match in progress shows a change of skin / flag at once, and a new unlock works
			if self.mode == MODE_SOLO and self.state ~= nil and (self.state.local_owner or 0) ~= 0 then
				self:_apply_own_cosmetics(self.state.local_owner)
				self:_apply_own_unlocks()
			end
			self:_emit("inventory_changed", self.inventory)
			for _, key in fresh do
				self:_emit("unlocked", key)
			end
		end
	elseif op == OP.GENERAL then
		local st = ...
		if type(st) == "table" then
			self.general = st.on == true
			local g = if type(st.given) == "table" then st.given else nil
			local given = if g ~= nil
				then {
					crate = g.crate == true,
					stars = if type(g.stars) == "number" then g.stars else nil,
					skin = if type(g.skin) == "string" then g.skin else nil,
				}
				else nil
			self:_emit("general_changed", self.general, given)
		end
	elseif op == OP.CRATE_RESULT then
		local ok, res = ...
		self:_emit("crate_result", ok == true, if type(res) == "string" then res else "")
	elseif op == OP.STARS then
		local p = ...
		if type(p) == "table" and type(p.total) == "number" then
			local lines = {}
			for _, l in (if type(p.lines) == "table" then p.lines else {}) do
				if type(l) == "table" and type(l[1]) == "string" and type(l[2]) == "number" then
					table.insert(lines, { l[1], l[2] })
				end
			end
			local award = {
				lines = lines,
				total = p.total,
				balance = tonumber(p.balance) or 0,
				mode = if type(p.mode) == "string" then p.mode else "public",
			}
			self.last_award = award
			self:_emit("stars_awarded", award)
		end
	elseif op == OP.UNLOCK_RESULT then
		local key, ok, reason = ...
		if type(key) == "string" then
			self:_emit("unlock_result", key, ok == true, if type(reason) == "string" then reason else nil)
		end
	elseif op == OP.HOP_RESULT then
		local going = ...
		self:_emit("hop_result", going == true)
	elseif op == OP.PARTY_STATE then
		local st = ...
		if type(st) == "table" then
			self.party = st
			self:_emit("party_changed", st)
		end
	elseif op == OP.COSMETICS then
		local map = ...
		if type(map) == "table" then
			self._cosmetics_map = map
			if self.mode == MODE_MULTI and self.state_mode == MODE_MULTI and self.state ~= nil then
				self.state:set_cosmetics(map, true)
			end
		end
	elseif op == OP.OWNER_CHANGED then
		-- a public match: the takeover happened on the server; this player commands `id` now
		local id = ...
		if type(id) == "number" and self.mode == MODE_MULTI and self.state ~= nil then
			self.state.local_owner = id
			table.clear(self._queued)
			self:_emit("took_over", id)
		end
	elseif op == OP.CREDIT_RESULT then
		local kind, ok, reason = ...
		if type(kind) == "string" then
			self:_emit("credit_result", kind, ok == true, if type(reason) == "string" then reason else nil)
		end
	elseif op == OP.ADMIN_BOTS then
		local ids = ...
		if type(ids) == "table" then
			local set = {}
			for _, id in ids do
				if type(id) == "number" then
					set[id] = true
				end
			end
			self.admin_bots = set
			self:_emit("admin_changed")
		end
	end
end

function Session._on_lobby(self: any, info: any)
	if type(info) ~= "table" then
		return
	end
	local was_available = self.lobby.available
	self.lobby = info
	if info.available == nil then
		info.available = true
	end
	-- Download the (next) match's map ahead of the snapshot.
	if type(info.map_id) == "string" then
		self:_fetch_map(info.map_id)
	end
	if info.available == false then
		info.closed = true
	end
	-- A public lobby's own server: the waiting room shows the match's map behind it.
	if
		info.kind == "match"
		and type(info.map_id) == "string"
		and (info.stage == "lobby" or info.stage == "idle")
		and (self._mp_waiting or self.mode ~= MODE_MULTI)
	then
		self:_show_wait_map(info.map_id)
	end
	-- A public lobby's match server: everyone here came to play it — join at once (and the
	-- Studio stand-in, where the hub server joined us itself, puts us in the waiting room).
	if info.kind == "match" and info.available ~= false and self.mode ~= MODE_MULTI then
		if info.in_match == true then
			self._mp_waiting = true
			self._mp_leaving = false
			self:_set_mode(MODE_MULTI)
		elseif not self._auto_joined then
			self._auto_joined = true
			self:join_multiplayer()
		end
	end
	self:_emit("lobby_updated", info)
	if was_available and info.available == false then
		self:_on_server_lost()
	end
end

function Session._on_snapshot(self: any, owner_id: any, msg: any)
	if self.mode ~= MODE_MULTI or type(owner_id) ~= "number" or type(msg) ~= "buffer" then
		return
	end
	-- Sent before the server processed our LEAVE (e.g. a rematch starting): we are on our way out.
	if self._mp_leaving and not self._mp_waiting then
		return
	end
	-- Discard any local (title) world still being prepared; the match takes over — and stop the one
	-- on screen now, so its memory is free before the match's state is built.
	self._build_serial += 1
	self._build_job = nil
	self:_stop_local()
	self._join_owner = owner_id
	table.clear(self._join_deltas)
	local GameState = self:_core("GameState")
	local WorldMap = self:_core("WorldMap")
	self:_preload_map(nil)
	self:_preload_map(self.lobby.map_id)
	local job = Coop.job(function()
		local snap = Protocol.decode_snapshot(msg)
		Coop.check()
		local gs = GameState.new(self:_await_map(WorldMap, snap.map_id))
		gs:load_snapshot(snap)
		gs.local_owner = owner_id
		return gs
	end)
	self._join_job = job
	if not self.threaded then
		job:finish()
		self:_run_join()
	end
end

function Session._run_join(self: any)
	local job = self._join_job
	if not job.done then
		job:step(self.build_budget_s)
		if not job.done then
			return
		end
	end
	self._join_job = nil
	if not job.ok then
		self:_warn_once("[Session] bad snapshot: " .. tostring(job.err))
		self._mp_waiting = false
		self:_emit("notice", "Couldn't load the match. You're back at the title screen.", Session.NOTICE_ERROR)
		self.env.net.send(OP.LEAVE)
		self:start_title()
		return
	end
	if self.mode ~= MODE_MULTI then
		return
	end
	self:_stop_local()
	self._mp_waiting = false
	--- (for the UI: this state replaces the same match's after a failed delta, it starts nothing)
	self.state_is_resync = self._resync_pending == true
	self._resync_pending = false
	local state = job.result
	self.state = state
	self.state_mode = MODE_MULTI
	self._last_delta = self.env.now()
	-- Deltas that arrived while the snapshot was loading, in order.
	local queued = self._join_deltas
	self._join_deltas = {}
	state:set_cosmetics(self._cosmetics_map, true)
	self:_emit("state_ready", state)
	self:_emit("joined_owner", self._join_owner)
	for _, q in queued do
		self:_apply_remote(q[1], q[2])
	end
end

function Session._cancel_join(self: any)
	self._join_job = nil
	table.clear(self._join_deltas)
end

function Session._on_delta(self: any, msg: any, tail: any)
	if type(msg) ~= "buffer" or (tail ~= nil and type(tail) ~= "buffer") then
		return
	end
	if self._join_job ~= nil then
		table.insert(self._join_deltas, { msg, tail })
		return
	end
	self:_apply_remote(msg, tail)
end

function Session._apply_remote(self: any, msg: buffer, tail: buffer?)
	local state = self.state
	if self.mode ~= MODE_MULTI or self._sim ~= nil or state == nil then
		return
	end
	local ok, d = pcall(Protocol.decode_delta, msg, tail)
	if not ok then
		self:_warn_once("[Session] bad delta: " .. tostring(d))
		self:_request_resync()
		return
	end
	-- Deltas already contained in the snapshot we loaded are skipped.
	if d.t ~= nil and d.t <= state.tick then
		return
	end
	if not self:_apply(state, d) then
		self:_request_resync()
	end
	self._last_delta = self.env.now()
end

function Session._on_match_closed(self: any, reason: any)
	-- The server removed us from the match (idle between matches, or the match ended for good).
	if self.mode == MODE_MULTI then
		self._mp_waiting = false
		self:_cancel_join()
		if type(reason) == "string" and reason ~= "" then
			self:_emit("notice", reason, Session.NOTICE_INFO)
		end
		self:start_title()
	end
end

function Session._on_settings(self: any, all: any)
	if type(all) ~= "table" then
		return
	end
	-- Sections saved locally before the server's copy arrived are newer, but hold only what this
	-- session touched: merge them key by key over the stored section (then send the merged section).
	for section, values in Settings.clean_all(all) do
		local mine = self._settings[section]
		if mine == nil then
			self._settings[section] = values
		elseif self._settings_dirty[section] then
			local merged = Settings.copy_section(values)
			for k, v in mine do
				merged[k] = v
			end
			self._settings[section] = Settings.clean_section(merged)
		end
	end
	local first = not self.settings_ready
	self.settings_ready = true
	self:_emit("settings_loaded")
	if first then
		self:_flush_settings(true)
	end
end

return Session
