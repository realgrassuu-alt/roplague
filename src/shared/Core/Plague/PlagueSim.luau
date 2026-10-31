--!native
-- RoPlague: the authoritative plague simulation (DESIGN.md §3-§4). Pure logic, no Instances; it runs
-- the solo match and the title backdrop on the client. Same outer contract as the old Core/Sim so
-- Session and GameState drive it unchanged: PlagueSim.new(map, config), add_human, submit(owner,
-- intent), step() at 10 Hz -> delta {t, tiles, flags, ev, pl}, snapshot().
--
-- The world: each country (Plague/Countries) is a map owner, so the map draws its borders and fills.
-- Its people are three numbers, healthy / infected / dead (the truth). The red on the map is a
-- picture of those numbers: tiles turn infected from where the disease entered, then dead from the
-- oldest infected tiles (tile flags F_INF / F_DEAD on the delta's "flags" channel).
--
-- The player is the disease: owner id `pid` (count + 1), with no tiles. Intents (submit):
--   {type = "zero", tile}          pick patient zero (spawn phase only)
--   {type = "evolve", id}          buy a trait (Data/Traits)
--   {type = "devolve", id}         sell a trait back (Traits.REFUND of its base cost)
--   {type = "pop", id}             collect a bubble
--   {type = "ability", key}        the pathogen's active power
--
-- Several plagues (2026-10-30: a server-run Plague Race or team game, config.plagues): plague k is owner
-- C + k. Each has its own numbers (DNA, evolutions, effects...: PL_FIELDS) in self.P[k]; the plague
-- the sim is working for is loaded onto self (PlagueSim._use), so the single-plague code runs for each
-- in turn and solo is the same code with K = 1. A country is held by one plague at a time (holder[c]);
-- an enemy's country is taken by an attack (_attack).
local Defs = require("../Defs")
local Ev = require("../Ev")
local Rng = require("../Rng")
local SimNav = require("../SimNav")
local Coop = require("../../Net/Coop")
local Traits = require("../../Data/Traits")
local Countries = require("./Countries")
local R = require("./PlagueRules")
local PlagueBot = require("./PlagueBot")
local Reach = require("./Reach")

local readu8 = buffer.readu8
local writeu8 = buffer.writeu8
local exp = math.exp
local sqrt = math.sqrt
local floor = math.floor
local min = math.min
local max = math.max

local PlagueSim = {}
PlagueSim.__index = PlagueSim

PlagueSim.TICK_RATE = R.TICK_RATE
PlagueSim.DAY_TICKS = R.DAY_TICKS

--- Closure bits (Ev.P_CLOSE, snapshot `closed`).
PlagueSim.C_AIR = 1
PlagueSim.C_PORT = 2
PlagueSim.C_BORDER = 4
PlagueSim.C_QUARANTINE = 8
PlagueSim.C_COLLAPSE = 16
local C_AIR, C_PORT, C_BORDER, C_QUARANTINE, C_COLLAPSE = 1, 2, 4, 8, 16

--- Bubble kinds.
PlagueSim.B_DNA = 0
PlagueSim.B_CURE = 1
--- a hotspot over an uninfected neighbour (popping it infects the country)
PlagueSim.B_HOT = 2

--- DNA reasons (Ev.P_DNA).
PlagueSim.DNA_PASSIVE = 0
PlagueSim.DNA_BUBBLE = 1
PlagueSim.DNA_COUNTRY = 2
PlagueSim.DNA_DEATH = 3
PlagueSim.DNA_CURE_BUBBLE = 4

-- per-tile state
local T_NONE, T_QUEUED, T_INF, T_DEAD = 0, 1, 2, 3
local F_INF, F_DEAD = Defs.F_INF, Defs.F_DEAD

local PATHOGEN_RGBA = {}
for _, p in Traits.PATHOGENS do
	PATHOGEN_RGBA[p.id] = Defs.html_rgba(p.color)
end

-- =============================================================================================
-- Construction
-- =============================================================================================

--- config: {seed, difficulty (0..2), max_humans (0: the title backdrop), pathogen (id), name,
--- auto (a bot plays the disease: the title backdrop and the balance harness), strategy (bot),
--- zero_after (auto: ticks before the bot picks patient zero)}
function PlagueSim.new(map: any, config: { [string]: any }?): any
	local cfg = config or {}
	local cs = Countries.get(map)
	assert(cs ~= nil, "PlagueSim: this map has no country layer")
	local self: any = setmetatable({}, PlagueSim)
	self.map = map
	self.W, self.H, self.N = map.W, map.H, map.N
	self.config = cfg
	self.rng = Rng.new(cfg.seed or 1)
	self.difficulty = math.clamp(math.floor(tonumber(cfg.difficulty) or 1), 0, 2)
	self.di = self.difficulty + 1
	self.tick = 0
	self.phase = Defs.PHASE_SPAWN
	self.winner = 0
	self.over_reason = -1
	self.playing_since = -1
	self.cs = cs
	local C = cs.count
	self.C = C
	self.pid = C + 1
	self.human = false
	self.human_name = ""
	-- multiplayer (Data/PlagueModes): "coop", every human plays the one plague; "duel", one player is the
	-- plague and the other the cure (cure_pid, its own owner); nil: solo
	-- "race" / "teams": a shared world, one plague per player or team (config.plagues; roles: user id -> plague)
	self.mode = if cfg.mode == "coop" or cfg.mode == "duel" or cfg.mode == "race" or cfg.mode == "teams"
		then cfg.mode
		else nil
	--- user id (string) -> "plague" | "cure" (a duel's sides, from the matchmaker)
	self.roles = if type(cfg.roles) == "table" then cfg.roles else {}
	self.map_id = map.id
	self.cure_pid = if self.mode == "duel" then C + 2 else 0
	self.cure_name = ""
	self.cure_funds = R.DUEL_FUNDS_START
	self.cure_acc = 0
	--- a server-run match picks patient zero itself after R.MP_ZERO_TICKS (-1: never)
	self.zero_deadline = if self.mode ~= nil then R.MP_ZERO_TICKS else -1

	-- countries ------------------------------------------------------------------------------
	local pop, H, I, D = {}, {}, {}, {}
	self.pop, self.Hc, self.Ic, self.Dc = pop, H, I, D
	self.closed, self.funding, self.nerve, self.alarm, self.lax = {}, {}, {}, {}, {}
	self.first_tick, self.first_death, self.beta_c, self.border_total = {}, {}, {}, {}
	self.border_tile = {} -- [country * 256 + other] = a tile of country on that border
	local world_pop = 0
	for c = 1, C do
		local cc = cs.list[c]
		pop[c] = math.max(cc.pop, 1)
		H[c], I[c], D[c] = pop[c], 0, 0
		world_pop += pop[c]
		self.closed[c] = 0
		self.funding[c] = 0
		self.nerve[c] = self.rng:randf_range(0.75, 1.3)
		-- bits of C_AIR / C_PORT this country will never close (see R.LAX_*)
		local lax = 0
		if self.rng:randf() < (R.LAX_PORT[cc.wealth] or 0) then
			lax += C_PORT
		end
		if self.rng:randf() < (R.LAX_AIR[cc.wealth] or 0) then
			lax += C_AIR
		end
		self.lax[c] = lax
		self.alarm[c] = 0
		self.first_tick[c] = -1
		self.first_death[c] = false
		local tot = 0
		for _, nb in cc.neighbors do
			tot += nb[2]
			self.border_tile[c * 256 + nb[1]] = nb[3]
		end
		self.border_total[c] = tot
	end
	self.world_pop = world_pop
	self.Hw, self.Iw, self.Dw = world_pop, 0, 0
	-- (the most infected at once, for the end screen)
	self.peak_I = 0

	-- tiles ----------------------------------------------------------------------------------
	local N = self.N
	self.tstate = buffer.create(N)
	self.flags = buffer.create(N)
	self.owner = buffer.create(N * 4)
	self.front, self.inf_list, self.inf_n, self.dead_ptr, self.dead_n, self.scan = {}, {}, {}, {}, {}, {}
	for c = 1, C do
		local cc = cs.list[c]
		local tl = cc.tile_list
		for k = 0, cc.tiles - 1 do
			buffer.writei32(self.owner, buffer.readi32(tl, k * 4) * 4, c)
		end
		self.front[c] = {}
		self.inf_list[c] = {}
		self.inf_n[c] = 0
		self.dead_ptr[c] = 1
		self.dead_n[c] = 0
		self.scan[c] = 0
		if c % 16 == 0 then
			Coop.check()
		end
	end

	-- ports and airports ---------------------------------------------------------------------
	local nav = SimNav.shared(map)
	self.nav = nav
	self.structs = {}
	self.ports, self.airports = {}, {}
	self.ports_by_body = {}
	local sid = 0
	for c = 1, C do
		local cc = cs.list[c]
		for _, t in cc.airports do
			sid += 1
			table.insert(self.airports, { sid = sid, tile = t, c = c, k = #self.airports })
			table.insert(self.structs, { sid, Defs.S_AIRFIELD, c, t, 1, 0 })
		end
		for _, t in cc.ports do
			local body = map:coast_body_of(t)
			local water = if body > 0 then nav:water_next_to(t, body) else -1
			if water >= 0 then
				sid += 1
				local p = { sid = sid, tile = t, c = c, water = water, body = body, k = #self.ports }
				table.insert(self.ports, p)
				local lst = self.ports_by_body[body]
				if lst == nil then
					lst = {}
					self.ports_by_body[body] = lst
				end
				table.insert(lst, p)
				table.insert(self.structs, { sid, Defs.S_PORT, c, t, 1, 0 })
			end
		end
	end

	-- (RoPlague v3: no port / airport plates on the map: ships sail between any two coasts)
	self.structs = {}

	-- the disease (several on a shared world: config.plagues, one record each in self.P; the plague
	-- being worked for is on self, PlagueSim._use) -----------------------------------------------
	local specs = if type(cfg.plagues) == "table" and #cfg.plagues > 0 then cfg.plagues else { cfg }
	self.K = math.min(#specs, R.MAX_PLAGUES)
	self.multi = self.K > 1
	self.P = {}
	self.cur = 1
	--- the plague (1..K) holding each country (0: none); a country just taken can't be attacked till shield
	self.holder, self.shield = {}, {}
	for c = 1, C do
		self.holder[c] = 0
		self.shield[c] = 0
	end
	for k = 1, self.K do
		self:_init_plague(specs[k], k)
		self.P[k] = {}
		self:_save_plague(k)
	end
	self.cur = 1
	self:_load_plague(1)
	--- user id -> plague (1..K) in a shared world (config.roles); plagues a player was put in
	self.taken = {}
	--- a duel's cure buildings: the country each stands in -> { [kind] = sid } (R.BUILDINGS), and how
	--- many labs / hospitals reach each country
	self.buildings = {}
	self.lab_cov, self.hosp_cov = {}, {}
	self.next_sid = 100000
	--- a shared world's attacks on other plagues' countries (PlagueSim._attack_start / _fight), and the
	--- countries being fought over (they spread no further meanwhile)
	self.attacks = {}
	self.contested = {}
	self.aware = 0
	self.research = false
	self.cure = 0
	self.cure_rate = 0

	-- transport, bubbles ---------------------------------------------------------------------
	self.ships = {} -- ordered list of {uid, from (port), to (port), infected, arrive}
	self.flights = {} -- ordered list of {uid, from (airport), to (airport), infected, launch, arrive}
	self.next_uid = 0
	self.path_cache = {}
	self.path_budget = R.PATH_BUDGET
	self.bubbles = {} -- ordered list of {id, kind, c, tile, value, expire, owner (a plague's owner id, 0: anyone)}
	self.next_bubble_id = 0
	self.next_cure_bubble_tick = 0

	-- per-tick output ------------------------------------------------------------------------
	self._intents = {}
	self._ev = {}
	self._flags = {}
	self._pl_dirty = true
	self.news_count = {}
	--- news gathered for one line a kind (PlagueSim._queue_news / _flush_news)
	self.news_q = {}
	self.next_news_tick = 0

	self.bot = if cfg.auto then PlagueBot.new(self, cfg.strategy, cfg.zero_after) else nil
	for k = self.K, 1, -1 do
		self:_use(k)
		self:_recompute()
	end
	if self.multi then
		-- (a country nobody holds yet: plague 1's numbers, replaced by its holder's when it is taken)
		for c = 1, C do
			self.beta_c[c] = self.beta_c[c] or self:_beta_of(c)
		end
	end
	return self
end

-- =============================================================================================
-- Several plagues (PlagueSim._use)
-- =============================================================================================

--- What each plague has of its own. The running plague's are on self.
local PL_FIELDS = {
	"pid", "pathogen", "plague_name", "perks", "price_mult", "sea_bonus", "perk_resist", "bubble_rate",
	"dna", "dna_earned", "dna_acc", "owned", "ability_ready", "start_c", "start_tile", "outbreak_done",
	"fx", "sev", "leth", "resist", "land_mult", "inf_m", "human", "human_name", "kills", "out", "Ik", "Dk", "near",
	"next_bubble_tick", "next_hot_tick",
}

--- Sets self up as plague k from its spec (config, or one of config.plagues).
function PlagueSim._init_plague(self: any, spec: any, k: number)
	local cfg = self.config
	self.pid = self.C + k
	self.pathogen = Traits.pathogen_by_id[tostring(spec.pathogen or cfg.pathogen or "")] or Traits.PATHOGENS[1]
	self.plague_name = if type(spec.name) == "string" and spec.name ~= "" then spec.name else self.pathogen.name
	--- the shop's perks this player owns (Data/Arsenal keys -> true)
	self.perks = if type(spec.perks) == "table" then spec.perks else {}
	local perks = self.perks
	self.price_mult = if perks.gene_bank then R.PERK_GENE_BANK else 1
	self.sea_bonus = if perks.sea_legs then R.PERK_SEA_WATER else 0
	self.perk_resist = if perks.slow_science then R.PERK_SLOW_SCIENCE else 0
	self.bubble_rate = if perks.bubble_magnet then R.PERK_BUBBLE_RATE else 1
	self.dna = R.DNA_START + (if perks.head_start then R.PERK_HEAD_START_DNA else 0)
	self.dna_earned = self.dna
	self.dna_acc = 0
	self.owned = {} :: { [string]: boolean }
	self.ability_ready = 0
	self.start_c = 0
	self.start_tile = nil
	self.outbreak_done = false
	self.human = false
	self.human_name = ""
	self.kills = 0
	self.out = false
	self.Ik, self.Dk = 0, 0
	self.near = spec.near == true
	self.next_bubble_tick = 0
	self.next_hot_tick = 0
end

function PlagueSim._save_plague(self: any, k: number)
	local rec = self.P[k]
	for _, f in PL_FIELDS do
		rec[f] = self[f]
	end
end

function PlagueSim._load_plague(self: any, k: number)
	local rec = self.P[k]
	for _, f in PL_FIELDS do
		self[f] = rec[f]
	end
end

--- Works for plague k from here on (its numbers on self).
function PlagueSim._use(self: any, k: number)
	if k == self.cur or self.P[k] == nil then
		return
	end
	self:_save_plague(self.cur)
	self:_load_plague(k)
	self.cur = k
end

--- Field `f` of plague k (the running one's is on self).
function PlagueSim._pget(self: any, k: number, f: string): any
	if k == self.cur then
		return self[f]
	end
	local rec = self.P[k]
	return if rec ~= nil then rec[f] else nil
end

function PlagueSim._pset(self: any, k: number, f: string, v: any)
	if k == self.cur then
		self[f] = v
	elseif self.P[k] ~= nil then
		self.P[k][f] = v
	end
end

--- The plague (1..K) of owner id `pid`, or nil.
function PlagueSim.plague_of(self: any, pid: number): number?
	local k = pid - self.C
	return if k >= 1 and k <= self.K then k else nil
end

--- A message for the running plague's players alone (a shared world), or for everyone (solo).
function PlagueSim._tell(self: any, cat: number, text: string)
	if self.multi then
		table.insert(self._ev, { Ev.MSG, self.pid, cat, text })
	else
		self:_news(cat, text)
	end
end

--- Tile flag bits naming the plague that holds country c (a shared world: bits 3..5).
function PlagueSim._pbits(self: any, c: number): number
	if not self.multi then
		return 0
	end
	return (math.max(self.holder[c], 1) - 1) * 8
end

--- beta of country c for the plague holding it.
function PlagueSim._beta_for(self: any, c: number): number
	local h = self.holder[c]
	if self.multi and h ~= 0 then
		self:_use(h)
	end
	return self:_beta_of(c)
end

--- A player (solo: the local one; `key` is their user id in a server-run match): returns the owner id
--- they play. Co-op: everyone plays the plague; a duel's cure side plays cure_pid.
function PlagueSim.add_human(self: any, key: string, display_name: string): number
	-- (a server-run match: the patient-zero clock starts when the first player is in, not when the
	-- match was made)
	if self.zero_deadline >= 0 and not self._zero_armed then
		self._zero_armed = true
		self.zero_deadline = self.tick + R.MP_ZERO_TICKS
	end
	if self.mode == "duel" and self.roles[tostring(key)] == "cure" then
		self.cure_name = display_name
		self._pl_dirty = true
		return self.cure_pid
	end
	if self.multi then
		-- a shared world: the player's plague (their team's), else the next one nobody plays yet
		local k = tonumber(self.roles[tostring(key)])
		if k == nil or self.P[k] == nil then
			k = nil
			for j = 1, self.K do
				if not self.taken[j] then
					k = j
					break
				end
			end
		end
		if k == nil then
			return 0
		end
		self.taken[k] = true
		if not self:_pget(k, "human") then
			self:_pset(k, "human", true)
			self:_pset(k, "human_name", display_name)
		end
		self._pl_dirty = true
		return self.C + k
	end
	self.human = true
	if self.human_name == "" or self.mode == nil then
		self.human_name = display_name
	end
	return self.pid
end

--- A player left a server-run match: it goes on (a co-op plague keeps its other players; a cure without
--- its player is the world's governments alone).
function PlagueSim.remove_human(_self: any, _owner_id: number) end

function PlagueSim.submit(self: any, owner_id: number, intent: { [string]: any })
	if self.multi then
		local k = self:plague_of(owner_id)
		if k ~= nil and not self:_pget(k, "out") then
			local it = table.clone(intent)
			it._k = k
			table.insert(self._intents, it)
		end
		return
	end
	if owner_id == self.pid then
		table.insert(self._intents, intent)
	elseif owner_id ~= 0 and owner_id == self.cure_pid then
		-- the cure's player: its own actions, and the cure bubbles
		if intent.type == "cure" or intent.type == "pop" then
			local it = table.clone(intent)
			it._cure = true
			table.insert(self._intents, it)
		end
	end
end

--- Solo: apply one intent now, between ticks (the Evolve screen buys while the game is paused).
--- Returns a delta for the mirror that does not advance time.
function PlagueSim.apply_now(self: any, owner_id: number, intent: { [string]: any }): { [string]: any }
	self._ev = {}
	self._flags = {}
	self:submit(owner_id, intent)
	self:_process_intents()
	local d = { t = self.tick, tiles = {}, flags = self._flags, ev = self._ev, pl = self:_pl_rows(false) }
	self._pl_dirty = false
	return d
end

--- The in-game trailer (client/Trailer/Director, a local match only): runs fn(self) between ticks, like
--- apply_now, and returns the delta for the mirror. No intent maps to it, so nothing over the network can
--- reach it.
function PlagueSim.dev_delta(self: any, fn: (any) -> ()): { [string]: any }
	self._ev = {}
	self._flags = {}
	fn(self)
	local d = { t = self.tick, tiles = {}, flags = self._flags, ev = self._ev, pl = self:_pl_rows(false) }
	self._pl_dirty = false
	return d
end

--- Solo convenience: pick patient zero immediately. True when accepted.
function PlagueSim.human_start(self: any, _owner_id: number, tile: number): boolean
	return self:_start(tile)
end

function PlagueSim.spawn_ticks_left(self: any): number
	return if self.phase == Defs.PHASE_SPAWN then -1 else 0
end

function PlagueSim.owner_count(self: any): number
	return math.max(self.C + self.K, self.cure_pid)
end

function PlagueSim.country_at(self: any, tile: number): number
	if tile < 0 or tile >= self.N then
		return 0
	end
	return readu8(self.cs.grid, tile)
end

-- =============================================================================================
-- Effects
-- =============================================================================================

local FX_KEYS = { "beta", "hot", "urban", "rural", "air", "water", "land", "sev", "leth", "cold", "heat", "drug", "resist", "lock", "stow" }

function PlagueSim._recompute(self: any)
	local fx = {}
	for _, k in FX_KEYS do
		fx[k] = 0
	end
	for id, on in self.owned do
		local t = Traits.by_id[id]
		if on and t ~= nil then
			for k, v in t.fx do
				fx[k] = (fx[k] or 0) + v
			end
		end
	end
	self.fx = fx
	local p = self.pathogen
	self.sev = math.max(0, fx.sev) * p.sev
	self.leth = math.max(0, fx.leth) * p.leth
	self.resist = fx.resist
	self.land_mult = (1 + fx.land) * p.land
	self.inf_m = self:meters()
	-- (a shared world: only the countries this plague holds)
	for c = 1, self.C do
		if not self.multi or self.holder[c] == self.cur then
			self.beta_c[c] = self:_beta_of(c)
		end
	end
	self._pl_dirty = true
end

function PlagueSim._beta_of(self: any, c: number): number
	local cc = self.cs.list[c]
	local fx = self.fx
	local p = self.pathogen
	local k = R.TRAIT_BETA
	local b = R.BASE_BETA + fx.beta * k
	if cc.climate == "hot" then
		b += fx.hot * k
	end
	if cc.density == "urban" then
		b += fx.urban * k
	elseif cc.density == "rural" then
		b += fx.rural * k
	end
	b = math.max(0.01, b) * p.beta
	local loss = (1 - R.CLIMATE_KEEP) * p.env
	if cc.climate == "hot" then
		b *= 1 - loss * math.max(0, 1 - 0.5 * fx.heat)
	elseif cc.climate == "cold" then
		b *= 1 - loss * math.max(0, 1 - 0.5 * fx.cold)
	end
	local w = R.WEALTH_BETA[cc.wealth] or 1
	if w < 1 then
		w = 1 - (1 - w) * math.max(0, 1 - 0.5 * fx.drug)
	end
	b *= w * (R.DENSITY_BETA[cc.density] or 1)
	if bit32.band(self.closed[c], C_QUARANTINE) ~= 0 then
		b *= R.QUARANTINE_KEEP
	end
	return b
end

--- The three headline numbers the HUD shows, 0..1 each.
function PlagueSim.meters(self: any): (number, number, number)
	local fx = self.fx
	local inf = ((R.BASE_BETA + fx.beta) * self.pathogen.beta + 0.4 * (fx.air + fx.water) + 0.2 * fx.land) / 0.9
	return math.clamp(inf, 0, 1), math.clamp(self.sev / 40, 0, 1), math.clamp(self.leth / 0.06, 0, 1)
end

-- =============================================================================================
-- Output helpers
-- =============================================================================================

function PlagueSim._emit(self: any, e: { any })
	table.insert(self._ev, e)
end

function PlagueSim._news(self: any, cat: number, text: string)
	table.insert(self._ev, { Ev.MSG, -1, cat, text })
end

function PlagueSim._gain(self: any, amount: number, tile: number, reason: number)
	if amount <= 0 then
		return
	end
	self.dna += amount
	self.dna_earned += amount
	self._pl_dirty = true
	table.insert(self._ev, { Ev.P_DNA, amount, tile, reason, self.pid })
end

-- =============================================================================================
-- Tiles (the picture)
-- =============================================================================================

function PlagueSim._set_flag(self: any, t: number, f: number)
	writeu8(self.flags, t, f)
	table.insert(self._flags, t * 256 + f)
end

function PlagueSim._infect_tile(self: any, c: number, t: number)
	local ts = self.tstate
	local st = readu8(ts, t)
	if st == T_INF or st == T_DEAD then
		return
	end
	writeu8(ts, t, T_INF)
	self:_set_flag(t, F_INF + self:_pbits(c))
	local il = self.inf_list[c]
	il[#il + 1] = t
	self.inf_n[c] += 1
	local W, N = self.W, self.N
	local grid = self.cs.grid
	local front = self.front[c]
	local x = t % W
	-- west, east, north, south: same country, untouched -> queued
	if x > 0 then
		local n = t - 1
		if readu8(ts, n) == T_NONE and readu8(grid, n) == c then
			writeu8(ts, n, T_QUEUED)
			front[#front + 1] = n
		end
	end
	if x < W - 1 then
		local n = t + 1
		if readu8(ts, n) == T_NONE and readu8(grid, n) == c then
			writeu8(ts, n, T_QUEUED)
			front[#front + 1] = n
		end
	end
	if t >= W then
		local n = t - W
		if readu8(ts, n) == T_NONE and readu8(grid, n) == c then
			writeu8(ts, n, T_QUEUED)
			front[#front + 1] = n
		end
	end
	if t + W < N then
		local n = t + W
		if readu8(ts, n) == T_NONE and readu8(grid, n) == c then
			writeu8(ts, n, T_QUEUED)
			front[#front + 1] = n
		end
	end
end

--- Next tile to turn red in country c: a random frontier tile (organic blobs), or, once the
--- frontier is empty (an island country, a closed pocket), a fresh untouched tile. -1 when none.
--- A smooth 0..1 value per tile (value noise, about FRONT_CELL tiles across), for the front's ragged edge.
local FRONT_CELL = 5
local FRONT_SAMPLES = 6
local FRONT_ROUGH = 2.5
local function fhash(x: number, y: number): number
	return (math.sin(x * 127.1 + y * 311.7) * 43758.5453) % 1
end
local function fnoise(x: number, y: number): number
	local xi, yi = math.floor(x), math.floor(y)
	local fx, fy = x - xi, y - yi
	fx = fx * fx * (3 - 2 * fx)
	fy = fy * fy * (3 - 2 * fy)
	local a = fhash(xi, yi)
	local b = fhash(xi + 1, yi)
	local cc = fhash(xi, yi + 1)
	local d = fhash(xi + 1, yi + 1)
	return a + (b - a) * fx + (cc - a) * fy + (a - b - cc + d) * fx * fy
end

--- The next tile the plague takes in country c. It grows as a solid patch with a soft, ragged edge, not as
--- coral with holes: of a few tiles drawn from the front, the one with the most infected neighbours wins
--- (holes and notches fill first), with a smooth noise term so the edge wanders.
function PlagueSim._next_tile(self: any, c: number): number
	local front = self.front[c]
	local ts = self.tstate
	local rng = self.rng
	local W = self.W
	local offs = self._front_offs
	if offs == nil then
		offs = { -1, 1, -W, W, -W - 1, -W + 1, W - 1, W + 1 }
		self._front_offs = offs
	end
	local best_j, best_s = 0, -math.huge
	local got = 0
	local tries = 0
	while #front > 0 and got < FRONT_SAMPLES and tries < FRONT_SAMPLES * 3 do
		tries += 1
		local j = rng:randi_range(1, #front)
		local t = front[j]
		if readu8(ts, t) ~= T_QUEUED then
			-- stale (taken another way): drop it; the last entry moves into its slot
			local last = #front
			front[j] = front[last]
			front[last] = nil
			if best_j == last then
				best_j = j
			end
			continue
		end
		got += 1
		local n = 0
		for _, o in offs do
			local v = t + o
			if v >= 0 and v < self.N then
				local s = readu8(ts, v)
				if s == T_INF or s == T_DEAD then
					n += 1
				end
			end
		end
		local score = n + fnoise((t % W) / FRONT_CELL, (t // W) / FRONT_CELL) * FRONT_ROUGH
		if score > best_s then
			best_j, best_s = j, score
		end
	end
	if best_j > 0 then
		local t = front[best_j]
		front[best_j] = front[#front]
		front[#front] = nil
		return t
	end
	local cc = self.cs.list[c]
	local n = cc.tiles
	if n == 0 then
		return -1
	end
	local tl = cc.tile_list
	for _ = 1, 8 do
		local t = buffer.readi32(tl, rng:randi_range(0, n - 1) * 4)
		if readu8(ts, t) == T_NONE then
			return t
		end
	end
	local k = self.scan[c]
	while k < n do
		local t = buffer.readi32(tl, k * 4)
		k += 1
		if readu8(ts, t) == T_NONE then
			self.scan[c] = k
			return t
		end
	end
	self.scan[c] = n
	return -1
end

function PlagueSim._tiles(self: any)
	local budget = R.TILE_BUDGET
	local C = self.C
	local list = self.cs.list
	local I, D, pop = self.Ic, self.Dc, self.pop
	local ts = self.tstate
	for k = 0, C - 1 do
		if budget <= 0 then
			break
		end
		local c = 1 + (k + self.tick) % C
		if self.first_tick[c] < 0 then
			continue
		end
		local tiles = list[c].tiles
		local frac = (I[c] + D[c]) / pop[c]
		local tgt = if frac > 0 then math.clamp(floor(tiles * frac ^ R.AREA_EXP), 1, tiles) else 0
		while self.inf_n[c] < tgt and budget > 0 do
			local t = self:_next_tile(c)
			if t < 0 then
				break
			end
			self:_infect_tile(c, t)
			budget -= 1
		end
		local dfrac = D[c] / pop[c]
		local tgt_dead = if dfrac > 0 then floor(tiles * dfrac ^ R.DEAD_EXP) else 0
		local il = self.inf_list[c]
		while self.dead_n[c] < tgt_dead and budget > 0 and self.dead_ptr[c] <= #il do
			local t = il[self.dead_ptr[c]]
			self.dead_ptr[c] += 1
			if readu8(ts, t) == T_INF then
				writeu8(ts, t, T_DEAD)
				self:_set_flag(t, F_INF + F_DEAD + self:_pbits(c))
				self.dead_n[c] += 1
				budget -= 1
			end
		end
	end
end

-- =============================================================================================
-- Seeding (the disease arrives somewhere)
-- =============================================================================================

--- Puts `hosts` infected into country c, entering at tile t. False when nobody healthy is left.
function PlagueSim._seed(self: any, c: number, t: number, hosts: number, quiet: boolean?): boolean
	local h = self.Hc[c]
	if h < 1 then
		return false
	end
	if self.multi then
		-- (a shared world: never into a country another plague holds; that takes an attack)
		local hd = self.holder[c]
		if hd ~= 0 and hd ~= self.cur then
			return false
		end
		if hd == 0 then
			self.holder[c] = self.cur
			self.beta_c[c] = self:_beta_of(c)
		end
	end
	local n = math.min(hosts, h)
	self.Hc[c] = h - n
	self.Ic[c] += n
	local cc = self.cs.list[c]
	if t < 0 or readu8(self.cs.grid, t) ~= c then
		t = cc.label
	end
	if self.first_tick[c] < 0 then
		self.first_tick[c] = self.tick
		self:_emit({ Ev.P_INFECTED, c, t, self.pid })
		if not quiet then
			self:_gain(R.DNA_NEW_COUNTRY, t, PlagueSim.DNA_COUNTRY)
			self:_add_bubble(PlagueSim.B_DNA, c, t, R.NEW_COUNTRY_BUBBLE)
			if cc.pop >= 5e6 then
				self:_queue_news("first", cc.name)
			end
		end
	end
	if t >= 0 then
		self:_infect_tile(c, t)
	end
	self._pl_dirty = true
	return true
end

function PlagueSim._start(self: any, tile: number): boolean
	if self.phase ~= Defs.PHASE_SPAWN then
		return false
	end
	local c = self:country_at(tile)
	if c == 0 then
		return false
	end
	if self.multi and (self.start_c ~= 0 or self.holder[c] ~= 0) then
		return false -- (a shared world: one start each, never in a country another plague took)
	end
	self.start_c = c
	self.start_tile = tile
	self:_emit({ Ev.SPAWNED, self.pid, tile })
	local all = true
	if self.multi then
		for k = 1, self.K do
			if k ~= self.cur and (self:_pget(k, "start_c") or 0) == 0 then
				all = false
			end
		end
	end
	if all then
		-- (a shared world: everyone's plague starts at once, when the last one is placed, and nobody's
		-- first country can be attacked for a while)
		if self.multi then
			for k = 1, self.K do
				local sc = if k == self.cur then c else (self:_pget(k, "start_c") or 0)
				if sc > 0 then
					self.shield[sc] = self.tick + R.START_SHIELD_DAYS * R.DAY_TICKS
				end
			end
		end
		self.phase = Defs.PHASE_PLAYING
		self.playing_since = self.tick
		self:_emit({ Ev.PHASE, Defs.PHASE_PLAYING, 0 })
	end
	self:_seed(c, tile, if self.perks.super_spreader then R.PERK_ZERO_HOSTS else R.ZERO_HOSTS, true)
	self.next_bubble_tick = self.tick + R.DAY_TICKS
	-- Mutagen: a free first-tier Transmission evolution
	if self.perks.mutagen then
		local pool = {}
		for _, t in Traits.list do
			if t.tree == "transmission" and t.req == nil and not self.owned[t.id] then
				table.insert(pool, t.id)
			end
		end
		if #pool > 0 then
			local id = pool[self.rng:randi_range(1, #pool)]
			self.owned[id] = true
			self:_recompute()
			self:_emit({ Ev.P_TRAIT, id, 1, 1, self.pid })
		end
	end
	self:_tell(Defs.MSG_INFO, ("Patient zero: %s"):format(self.cs.list[c].name))
	return true
end

-- =============================================================================================
-- Intents
-- =============================================================================================

function PlagueSim._process_intents(self: any)
	local q = self._intents
	if #q == 0 then
		return
	end
	self._intents = {}
	for _, it in q do
		local ty = it.type
		if it._k ~= nil then
			self:_use(it._k)
		end
		-- (off the wire a trait / ability arrives as `kind` and a bubble as `uid`: Net/Protocol)
		if ty == "zero" then
			self:_start(tonumber(it.tile) or -1)
		elseif ty == "evolve" then
			self:_evolve(tostring(it.id or it.kind))
		elseif ty == "devolve" then
			self:_devolve(tostring(it.id or it.kind))
		elseif ty == "pop" then
			self:_pop(tonumber(it.id or it.uid) or -1, it._cure == true)
		elseif ty == "ability" then
			self:_ability(tostring(it.key or it.kind))
		elseif ty == "infect" then
			self:_infect_click(tonumber(it.target) or 0)
		elseif ty == "retreat" then
			self:_retreat(tonumber(it.attack_id or it.id) or -1)
		elseif ty == "cure" and it._cure then
			self:_cure_act(tostring(it.kind), tonumber(it.target) or 0, tonumber(it.tile))
		end
	end
end

function PlagueSim.can_evolve(self: any, id: string): (boolean, number)
	if self.phase ~= Defs.PHASE_PLAYING then
		return false, 0
	end
	if not Traits.reachable(id, self.owned) then
		return false, 0
	end
	local price = Traits.price(id, self.owned, self.price_mult)
	return self.dna >= price, price
end

function PlagueSim._evolve(self: any, id: string): boolean
	local ok, price = self:can_evolve(id)
	if not ok then
		return false
	end
	self.dna -= price
	self.owned[id] = true
	self:_recompute()
	self:_emit({ Ev.P_TRAIT, id, 1, 0, self.pid })
	return true
end

function PlagueSim._devolve(self: any, id: string): boolean
	if self.phase ~= Defs.PHASE_PLAYING or not Traits.can_devolve(id, self.owned) then
		return false
	end
	local t = Traits.by_id[id]
	self.owned[id] = nil
	self.dna += floor(t.cost * Traits.REFUND)
	self:_recompute()
	self:_emit({ Ev.P_TRAIT, id, 0, 2, self.pid })
	return true
end

function PlagueSim._pop(self: any, id: number, by_cure: boolean?): boolean
	for k, b in self.bubbles do
		if b.id == id and by_cure then
			-- the cure's player (a duel): only the cure bubbles, and they speed the cure
			if b.kind ~= PlagueSim.B_CURE then
				return false
			end
			table.remove(self.bubbles, k)
			self:_emit({ Ev.P_BUBBLE_END, id, 1 })
			self.cure = math.min(1, self.cure + R.CURE_BUBBLE_CUT * (b.n or 1))
			self.cure_funds += R.DUEL_BUBBLE_FUNDS * (b.n or 1)
			self._pl_dirty = true
			return true
		end
		if b.id == id then
			-- (a shared world: a DNA bubble or a hotspot is its plague's; a cure bubble anyone's)
			if self.multi and (b.owner or 0) ~= 0 and b.owner ~= self.pid then
				return false
			end
			table.remove(self.bubbles, k)
			self:_emit({ Ev.P_BUBBLE_END, id, 1 })
			if b.kind == PlagueSim.B_HOT then
				-- a hotspot: the country catches it at once
				if self:_seed(b.c, b.tile, R.HOTSPOT_HOSTS) then
					self:_news(Defs.MSG_GOOD, ("Hotspot! %s is infected"):format(self.cs.list[b.c].name))
				end
				self:_gain(b.value, b.tile, PlagueSim.DNA_BUBBLE)
			elseif b.kind == PlagueSim.B_CURE then
				self.cure = math.max(0, self.cure - R.CURE_BUBBLE_CUT * (b.n or 1))
				self:_gain(b.value, b.tile, PlagueSim.DNA_CURE_BUBBLE)
			else
				self:_gain(b.value, b.tile, PlagueSim.DNA_BUBBLE)
				-- the spot under it catches the plague
				self:_seed(b.c, b.tile, R.BUBBLE_HOSTS * (b.n or 1), true)
			end
			return true
		end
	end
	return false
end

--- A duel's cure player acts on country `c` (R.DUEL_COSTS). True when it was done and paid for.
function PlagueSim._cure_act(self: any, kind: string, c: number, tile: number?): boolean
	if string.sub(kind, 1, 6) == "build_" then
		return self:_build(string.sub(kind, 7), c, tile)
	end
	local cost = R.DUEL_COSTS[kind]
	if self.mode ~= "duel" or self.phase ~= Defs.PHASE_PLAYING or cost == nil or self.cure_funds < cost then
		return false
	end
	local cc = if c >= 1 and c <= self.C then self.cs.list[c] else nil
	if kind == "alert" then
		if self.research then
			return false
		end
		self.aware = math.min(1, self.aware + R.DUEL_ALERT_AWARE)
		self:_news(Defs.MSG_BAD, "The cure team raises the alarm: the world is watching")
	elseif kind == "fund" then
		if cc == nil or not self.research or self.funding[c] >= 1 or bit32.band(self.closed[c], C_COLLAPSE) ~= 0 then
			return false
		end
		self.funding[c] = 1
		self:_news(Defs.MSG_BAD, ("%s funds the cure in full"):format(cc.name))
	elseif kind == "close" or kind == "quarantine" then
		if cc == nil or bit32.band(self.closed[c], C_COLLAPSE) ~= 0 then
			return false
		end
		local bits = if kind == "close" then C_BORDER + C_PORT + C_AIR else C_QUARANTINE
		local cl = self.closed[c]
		if bit32.band(cl, bits) == bits then
			return false
		end
		local nc = bit32.bor(cl, bits)
		self.closed[c] = nc
		self:_emit({ Ev.P_CLOSE, c, nc })
		if kind == "quarantine" then
			self.beta_c[c] = self:_beta_for(c)
		end
		self:_news(
			Defs.MSG_BAD,
			if kind == "close"
				then ("The cure team shuts %s's borders, ports and airports"):format(cc.name)
				else ("The cure team quarantines %s"):format(cc.name)
		)
	else
		return false
	end
	self.cure_funds -= cost
	self._pl_dirty = true
	return true
end

--- A duel's cure player builds `kind` (R.BUILDINGS) in country c, at `tile` (in c; else its label),
--- once research has started: drawn as a RoWorld structure of the cure's (Ev.STRUCT_ADD). True when
--- built and paid for.
function PlagueSim._build(self: any, kind: string, c: number, tile: number?): boolean
	local b = R.BUILDINGS[kind]
	if self.mode ~= "duel" or self.phase ~= Defs.PHASE_PLAYING or b == nil or not self.research then
		return false
	end
	-- (the tile clicked decides where it stands; a bad tile falls back to the country's centre)
	local t = -1
	if tile ~= nil and tile >= 0 and tile < self.N then
		local tc = readu8(self.cs.grid, tile)
		if tc >= 1 and tc <= self.C then
			t, c = tile, tc
		end
	end
	if c < 1 or c > self.C or self.cure_funds < b.cost or bit32.band(self.closed[c], C_COLLAPSE) ~= 0 then
		return false
	end
	local have = self.buildings[c]
	if have ~= nil and have[kind] ~= nil then
		return false
	end
	local cc = self.cs.list[c]
	if t < 0 then
		t = cc.label
	end
	self.cure_funds -= b.cost
	self.next_sid += 1
	local sid = self.next_sid
	if have == nil then
		have = {}
		self.buildings[c] = have
	end
	have[kind] = sid
	table.insert(self.structs, { sid, b.struct, self.cure_pid, t, 1, 0 })
	self:_emit({ Ev.STRUCT_ADD, sid, b.struct, self.cure_pid, t })
	-- what it does, to every country in range (the closures reuse the spread's own closed bits)
	local covered = self:_in_range(t, b.range, kind == "control")
	covered[c] = true
	local bits = if kind == "camp" then C_QUARANTINE elseif kind == "post" then C_BORDER elseif kind == "control" then C_PORT + C_AIR else 0
	local n = 0
	for x in covered do
		n += 1
		if bits ~= 0 and bit32.band(self.closed[x], C_COLLAPSE) == 0 then
			local nc = bit32.bor(self.closed[x], bits)
			if nc ~= self.closed[x] then
				self.closed[x] = nc
				self:_emit({ Ev.P_CLOSE, x, nc })
				if kind == "camp" then
					self.beta_c[x] = self:_beta_for(x)
				end
			end
		elseif kind == "lab" then
			self.funding[x] = 1
			self.lab_cov[x] = (self.lab_cov[x] or 0) + 1
		elseif kind == "hospital" then
			self.hosp_cov[x] = (self.hosp_cov[x] or 0) + 1
		end
	end
	self:_news(
		Defs.MSG_BAD,
		if n > 1
			then ("The cure team builds a %s in %s, reaching %d countries"):format(b.name, cc.name, n)
			else ("The cure team builds a %s in %s"):format(b.name, cc.name)
	)
	self._pl_dirty = true
	return true
end

--- The countries within `range` tiles of tile t: their centre in range, or (`ports`) one of their ports
--- or airports. A set.
function PlagueSim._in_range(self: any, t: number, range: number, ports: boolean): { [number]: boolean }
	local W = self.W
	local x0, y0 = t % W, t // W
	local r2 = range * range
	local function near(u: number): boolean
		local dx, dy = u % W - x0, u // W - y0
		return dx * dx + dy * dy <= r2
	end
	local out = {}
	for c = 1, self.C do
		local cc = self.cs.list[c]
		if near(cc.label) then
			out[c] = true
		elseif ports then
			for _, u in cc.ports do
				if near(u) then
					out[c] = true
					break
				end
			end
			if not out[c] then
				for _, u in cc.airports do
					if near(u) then
						out[c] = true
						break
					end
				end
			end
		end
	end
	return out
end

--- A duel: the cure's player earns research funds (R.DUEL_FUNDS_*).
function PlagueSim._cure_funds_tick(self: any, dt: number)
	if self.mode ~= "duel" then
		return
	end
	local sick = sqrt((self.Iw + self.Dw) / self.world_pop)
	self.cure_acc += (R.DUEL_FUNDS_DAY + (if self.research then R.DUEL_FUNDS_RESEARCH else 0) + R.DUEL_FUNDS_SICK * sick) * dt
	if self.cure_acc >= 1 then
		local whole = floor(self.cure_acc)
		self.cure_acc -= whole
		self.cure_funds += whole
		self._pl_dirty = true
	end
end

--- A server-run match still waiting for patient zero at R.MP_ZERO_TICKS: the most populous country.
function PlagueSim._auto_zero(self: any)
	if self.zero_deadline < 0 or self.phase ~= Defs.PHASE_SPAWN or self.tick < self.zero_deadline then
		return
	end
	-- (a shared world: each plague still unplaced, in the most populous country nobody took)
	for k = 1, self.K do
		if (self:_pget(k, "start_c") or 0) == 0 and self.phase == Defs.PHASE_SPAWN then
			self:_use(k)
			-- (the biggest free country; in a shared world first one not bordering another plague's)
			local list = self.cs.list
			local function near_held(c: number): boolean
				for _, nb in list[c].neighbors do
					if self.holder[nb[1]] ~= 0 then
						return true
					end
				end
				return false
			end
			local best, best_pop = 0, -1
			-- (a plague placed `near` (Studio's test rival) wants a border with the others instead)
			local near = self.P[k] ~= nil and self:_pget(k, "near") == true
			for pass = 1, 2 do
				for c = 1, self.C do
					if self.pop[c] > best_pop and self.holder[c] == 0 and (pass == 2 or near_held(c) == near) then
						best, best_pop = c, self.pop[c]
					end
				end
				if best > 0 then
					break
				end
			end
			if best > 0 then
				self:_start(self.cs.list[best].label)
			end
		end
	end
end

function PlagueSim._ability(self: any, key: string): boolean
	local a = Traits.ABILITIES[key]
	if a == nil or self.pathogen.ability ~= key or self.phase ~= Defs.PHASE_PLAYING then
		return false
	end
	if self.tick < self.ability_ready or self.dna < a.cost then
		return false
	end
	if key == "spores" then
		local pool = {}
		for c = 1, self.C do
			if self.Ic[c] < 1 and self.Hc[c] >= 1 and self.holder[c] == 0 then
				table.insert(pool, c)
			end
		end
		if #pool == 0 then
			return false
		end
		local c = pool[self.rng:randi_range(1, #pool)]
		self.dna -= a.cost
		self.ability_ready = self.tick + a.cooldown_days * R.DAY_TICKS
		local t = self.cs.list[c].label
		self:_seed(c, t, R.SEED_HOSTS * 2)
		self:_emit({ Ev.P_ABILITY, key, t, self.ability_ready })
		self._pl_dirty = true
		return true
	end
	return false
end

-- =============================================================================================
-- Tick
-- =============================================================================================

function PlagueSim.step(self: any): { [string]: any }
	self.tick += 1
	self._ev = {}
	self._flags = {}
	self.path_budget = R.PATH_BUDGET
	self:_process_intents()
	local bot = self.bot
	if bot ~= nil then
		bot:tick()
		self:_process_intents()
	end
	self:_auto_zero()
	if self.phase == Defs.PHASE_PLAYING then
		local dt = 1 / R.DAY_TICKS
		self:_population(dt)
		if not self.multi then
			self:_end_seed()
		end
		for k = 1, self.K do
			if not self:_pget(k, "out") then
				self:_use(k)
				self:_land()
				self:_jumps()
			end
		end
		Coop.check()
		self:_ships()
		self:_walkers()
		if self.multi then
			self:_fight()
		end
		self:_bubbles()
		self:_awareness(dt)
		self:_gov()
		self:_flush_news()
		self:_cure(dt)
		self:_cure_funds_tick(dt)
		for k = 1, self.K do
			if not self:_pget(k, "out") then
				self:_use(k)
				self:_dna(dt)
				self:_mutation()
			end
		end
		Coop.check()
		self:_tiles()
		if self.tick % 10 == 0 and self.phase == Defs.PHASE_PLAYING then
			self:_check_over()
		end
	end
	local d = { t = self.tick, tiles = {}, flags = self._flags, ev = self._ev }
	if self.tick % 5 == 0 then
		d.stats = self:_stats_rows()
	end
	if self._pl_dirty or self.tick % 5 == 0 then
		d.pl = self:_pl_rows(self.tick % 5 == 0)
		self._pl_dirty = false
	end
	return d
end

function PlagueSim._population(self: any, dt: number)
	local C = self.C
	local H, I, D, pop, beta = self.Hc, self.Ic, self.Dc, self.pop, self.beta_c
	local multi, holder, K = self.multi, self.holder, self.K
	local contested = self.contested
	local hosp = self.hosp_cov
	-- each plague's lethality and outbreak (a shared world: the holder's; solo: the one plague)
	local leth_k, start_k, done_k, kills_k, Ik, Dk = {}, {}, {}, {}, {}, {}
	local any_leth = 0
	for k = 1, K do
		leth_k[k] = self:_pget(k, "leth") or 0
		start_k[k] = self:_pget(k, "start_c") or 0
		done_k[k] = self:_pget(k, "outbreak_done") == true
		kills_k[k], Ik[k], Dk[k] = 0, 0, 0
		any_leth = math.max(any_leth, leth_k[k])
	end
	local Hw, Iw, Dw = 0, 0, 0
	-- (the end: R.END_* once most of the world is dead and the plague kills)
	local ending = any_leth > 0 and self.Dw >= R.END_WORLD_DEAD * self.world_pop
	for c = 1, C do
		local i = I[c]
		local h = H[c]
		local d = D[c]
		local hk = if multi then holder[c] else 1
		if i > 0 and hk > 0 then
			local leth = leth_k[hk]
			local alive = h + i
			local ni = if contested[c] then 0 else beta[c] * i * h / alive * dt
			-- some get better (healthy again)
			local nr = R.RECOVER * i * dt
			if c == start_k[hk] and not done_k[hk] then
				-- the outbreak (R.ZERO_OUTBREAK): fast and nobody recovers, once; then the usual rules
				if i + d < R.ZERO_OUTBREAK * pop[c] then
					ni = math.max(ni, R.ZERO_GROWTH * i * h / alive * dt)
					nr = 0
				else
					done_k[hk] = true
					self:_pset(hk, "outbreak_done", true)
				end
			end
			if ni > h then
				ni = h
			end
			local nd = 0
			if leth > 0 then
				-- as the dead pile up, health care collapses and the dying speeds up
				nd = leth * (1 + 4 * d / pop[c]) * i * dt
				if nd > i then
					nd = i
				end
			end
			if ending then
				-- the country falls apart: nobody recovers, the survivors catch it, the sick die
				nr = 0
				ni = math.min(h, math.max(ni, R.END_SPREAD * h * dt))
				nd = math.min(i, math.max(nd, R.END_KILL * i * dt))
			end
			if hosp[c] ~= nil then
				-- (a duel: the cure's hospital)
				nr *= R.HOSPITAL_RECOVER
				nd *= R.HOSPITAL_DEATH
			end
			if nd + nr > i then
				nr = math.max(0, i - nd)
			end
			h += nr - ni
			i += ni - nd - nr
			d += nd
			if h < 1 then
				i += h
				h = 0
			end
			if ending and h + i < R.END_FLOOR + R.END_FLOOR_SHARE * pop[c] then
				-- the last few: gone
				nd += h + i
				d += h + i
				h, i = 0, 0
			end
			kills_k[hk] += nd
			if i < 0.5 then
				i = 0
				if multi and not contested[c] then
					holder[c] = 0 -- (nobody sick there any more: the country is free again)
				end
			end
			H[c], I[c], D[c] = h, i, d
			if d >= 1 and not self.first_death[c] then
				self.first_death[c] = true
				if multi then
					self:_use(hk)
				end
				self:_gain(R.DNA_FIRST_DEATH, self.cs.list[c].label, PlagueSim.DNA_DEATH)
			end
		elseif ending and h > 0 and h < R.END_FLOOR + R.END_FLOOR_SHARE * pop[c] and self.first_tick[c] >= 0 then
			-- (a few survivors the plague passed through and left: gone too)
			d += h
			h = 0
			H[c], D[c] = h, d
		end
		Hw += h
		Iw += i
		Dw += d
		local hc = if multi then holder[c] else 1
		if hc > 0 then
			Ik[hc] += i
			Dk[hc] += d
		end
	end
	self.Hw, self.Iw, self.Dw = Hw, Iw, Dw
	for k = 1, K do
		self:_pset(k, "kills", (self:_pget(k, "kills") or 0) + kills_k[k])
		self:_pset(k, "Ik", Ik[k])
		self:_pset(k, "Dk", Dk[k])
	end
	if Iw > self.peak_I then
		self.peak_I = Iw
	end
end

--- Land borders: each infected country, once a day (staggered), may seed each healthy neighbour.
function PlagueSim._land(self: any)
	local C = self.C
	local slot = self.tick % R.DAY_TICKS
	local list = self.cs.list
	local rng = self.rng
	local H, I, pop = self.Hc, self.Ic, self.pop
	local lm = self.land_mult
	local multi, holder, cur = self.multi, self.holder, self.cur
	for c = 1, C do
		if c % R.DAY_TICKS ~= slot or I[c] <= 0 or (multi and holder[c] ~= cur) then
			continue
		end
		local tot = self.border_total[c]
		if tot <= 0 then
			continue
		end
		local base = R.LAND_K * lm * (I[c] / pop[c]) ^ R.LAND_EXP
		for _, nb in list[c].neighbors do
			local n = nb[1]
			if I[n] >= 1 or H[n] < 1 or (multi and holder[n] ~= 0) then
				continue
			end
			local open = if bit32.band(self.closed[n], C_BORDER) ~= 0 then R.BORDER_LEAK else 1
			local p = 1 - exp(-base * (nb[2] / tot) * open)
			if rng:randf() < p then
				self:_seed(n, self.border_tile[n * 256 + c] or -1, R.SEED_HOSTS)
			end
		end
	end
end

local function carry(prev: number, base: number, bonus: number): number
	if prev <= 0 then
		return 0
	end
	return math.min(R.CARRY_MAX, prev ^ R.CARRY_EXP * (base + bonus))
end

function PlagueSim._sea_path(self: any, a: any, b: any): { number }?
	local key = a.k * 1024 + b.k
	local p = self.path_cache[key]
	if p ~= nil then
		return p
	end
	local rev = self.path_cache[b.k * 1024 + a.k]
	if rev ~= nil then
		local out = table.create(#rev)
		for k = #rev, 1, -1 do
			out[#out + 1] = rev[k]
		end
		self.path_cache[key] = out
		return out
	end
	if self.path_budget <= 0 then
		return nil
	end
	self.path_budget -= 1
	p = self.nav:find_path(a.water, b.water)
	self.path_cache[key] = p
	return p
end

--- The player's ships (the "infect" click across a sea): they land on arrival.
function PlagueSim._ships(self: any)
	local tick = self.tick
	local ships = self.ships
	if #ships == 0 then
		return
	end
	local keep = {}
	for _, s in ships do
		if s.arrive <= tick then
			self:_emit({ Ev.UNIT_DEL, s.uid, Defs.DEL_ARRIVED })
			self:_use(s.k or 1)
			if self:_arrive(s.target, s.tile, s.troops, s.src) then
				self:_tell(Defs.MSG_GOOD, ("Your infected ship lands in %s"):format(self.cs.list[s.target].name))
			end
		else
			keep[#keep + 1] = s
		end
	end
	self.ships = keep
end

--- What a click on country `c` would do now: kind ("land" / "sea" / nil), source, DNA cost, reason.
function PlagueSim.route(self: any, c: number): (string?, number, number, string?)
	local I = self.Ic
	local closed = self.closed
	local multi, holder, cur = self.multi, self.holder, self.cur
	local hd = if multi and c >= 1 and c <= self.C then holder[c] else 0
	if hd ~= 0 and hd ~= cur and self.shield[c] > self.tick then
		local days = math.ceil((self.shield[c] - self.tick) / R.DAY_TICKS)
		return nil, 0, 0, ("Just taken: it can't be attacked for %d days"):format(days)
	end
	local kind, src, cost, reason = Reach.route(self.cs, self.map, c, function(x)
		-- (a shared world: only this plague's countries carry it)
		if multi and holder[x] ~= cur then
			return 0
		end
		return I[x] or 0
	end, function(x)
		return closed[x] or 0
	end, self:_route_opts())
	if kind ~= nil and hd ~= 0 and hd ~= cur then
		cost += R.ATTACK_DNA -- (an attack on another plague's country)
	end
	return kind, src, cost, reason
end

--- What the plague can do this tick when a country is clicked (Reach.route's options).
function PlagueSim._route_opts(self: any): any
	local n = 0
	local multi, holder, cur = self.multi, self.holder, self.cur
	for c = 1, self.C do
		if self.Ic[c] >= 1 and (not multi or holder[c] == cur) then
			n += 1
		end
	end
	local water = (self.fx.water or 0) + self.sea_bonus
	return {
		water = water,
		stow = self.fx.stow or 0,
		ships = water > 0,
		min_hosts = R.TRAVEL_MIN,
		extra = math.floor(n / R.INFECT_COST_STEP),
	}
end

--- Once a day: the plague may turn up by itself in a far country (fx.air: travellers) or on a coast
--- across a sea (fx.water). No planes or boats are drawn; the country just starts reporting cases.
function PlagueSim._jumps(self: any)
	if self.tick % R.DAY_TICKS ~= 3 then
		return
	end
	local fx = self.fx
	local air, water = fx.air or 0, fx.water or 0
	if air <= 0 and water <= 0 then
		return
	end
	local C = self.C
	local I, H = self.Ic, self.Hc
	local multi, holder, cur = self.multi, self.holder, self.cur
	local n_inf = 0
	for c = 1, C do
		if I[c] >= 1 and (not multi or holder[c] == cur) then
			n_inf += 1
		end
	end
	if n_inf == 0 then
		return
	end
	local reach = math.min(1, n_inf / R.JUMP_FULL)
	-- (a shared world: only into free countries)
	local function free(c: number): boolean
		return not multi or holder[c] == 0
	end
	local rng = self.rng
	local list = self.cs.list
	if air > 0 and rng:randf() < R.AIR_JUMP_K * air * reach then
		-- a far country, weighted by people, with its airports open
		local total = 0
		for c = 1, C do
			if I[c] < 1 and H[c] >= 1 and bit32.band(self.closed[c], C_AIR) == 0 and free(c) then
				total += math.sqrt(list[c].pop)
			end
		end
		if total > 0 then
			local pick = rng:randf() * total
			for c = 1, C do
				if I[c] < 1 and H[c] >= 1 and bit32.band(self.closed[c], C_AIR) == 0 and free(c) then
					pick -= math.sqrt(list[c].pop)
					if pick <= 0 then
						self:_seed(c, list[c].label, R.JUMP_HOSTS)
						break
					end
				end
			end
		end
	end
	if water > 0 and rng:randf() < R.SEA_JUMP_K * water * reach then
		-- a coast that shares a sea with an infected one (a few tries)
		for _ = 1, 6 do
			local c = rng:randi_range(1, C)
			if I[c] < 1 and H[c] >= 1 and free(c) then
				local kind = self:route(c)
				if kind == "sea" then
					local ports = list[c].ports
					self:_seed(c, if #ports > 0 then ports[1] else list[c].label, R.JUMP_HOSTS)
					break
				end
			end
		end
	end
end

--- An infected traveller walks from inside country `src` to its border with `c` (drawn by the map's
--- CarrierLayer, through the flight events Ev.P_FLIGHT / P_FLIGHT_END); it plants the plague on arrival.
function PlagueSim._walk(self: any, src: number, c: number)
	local W = self.W
	local to = self.border_tile[c * 256 + src] or self.cs.list[c].label
	local home = self.cs.list[src].label
	local tx, ty = to % W, to // W
	local hx, hy = home % W, home // W
	local dx, dy = hx - tx, hy - ty
	local len = math.sqrt(dx * dx + dy * dy)
	local back = math.min(len, R.WALK_FROM)
	local from = to
	if len > 0 then
		local fx = math.floor(tx + dx / len * back + 0.5)
		local fy = math.floor(ty + dy / len * back + 0.5)
		from = math.clamp(fy, 0, self.map.H - 1) * W + math.clamp(fx, 0, W - 1)
	end
	local ticks = math.clamp(math.ceil(back / R.WALK_TILES_PER_TICK), R.WALK_MIN_TICKS, R.WALK_MAX_TICKS)
	self.next_uid += 1
	local uid = self.next_uid
	table.insert(self.flights, {
		uid = uid,
		target = c,
		src = src,
		from_tile = from,
		to_tile = to,
		launch = self.tick,
		arrive = self.tick + ticks,
		k = self.cur,
	})
	self:_emit({ Ev.P_FLIGHT, uid, from, to, self.tick, ticks, 1, src, self.pid })
end

--- An attack's troops out of country `src` (R.attack_troops of its infected): they leave it (recovered
--- there, sick again wherever they win).
function PlagueSim._draft(self: any, src: number): number
	if src < 1 or src > self.C then
		return 0
	end
	local n = R.attack_troops(self.Ic[src])
	self.Ic[src] -= n
	self.Hc[src] += n
	return n
end

--- A traveller / ship of the running plague reached country c: it plants the plague there (a free
--- country, or one of its own); a ship carrying `troops` to another plague's starts an attack. True when
--- the plague got in (or the attack began).
function PlagueSim._arrive(self: any, c: number, tile: number, troops: number?, src: number?): boolean
	local hd = if self.multi then self.holder[c] else 0
	if hd == 0 or hd == self.cur then
		return self:_seed(c, tile, math.max(R.INFECT_HOSTS, troops or 0))
	end
	if troops == nil or troops < 1 then
		return false
	end
	return self:_attack_start(c, src or 0, troops, tile)
end

--- The running plague attacks country c (another plague's) with `troops`, at `tile` (the front): a new
--- RoWorld attack (Ev.ATTACK, so its attacks panel and front labels show it), or more troops on the
--- one already there. A free country (or one of ours by now): they just move in.
function PlagueSim._attack_start(self: any, c: number, src: number, troops: number, tile: number): boolean
	if troops < 1 then
		table.insert(self._ev, { Ev.MSG, self.pid, Defs.MSG_INFO, "Not enough infected there to attack with" })
		return false
	end
	local hd = self.holder[c]
	if hd == 0 or hd == self.cur then
		return self:_seed(c, tile, troops)
	end
	if self.shield[c] > self.tick then
		local h = self.Hc[src] or 0
		if src >= 1 then
			-- (shielded: the troops go home)
			local back = math.min(troops, h)
			self.Hc[src] = h - back
			self.Ic[src] += back
		end
		return false
	end
	for _, a in self.attacks do
		if a.k == self.cur and a.c == c then
			a.troops += troops
			self:_emit_attack(a)
			return true
		end
	end
	self.next_uid += 1
	local a = { aid = self.next_uid, k = self.cur, q = hd, c = c, src = src, troops = troops, tile = tile, start = tile, prog = 0, painted = 0 }
	table.insert(self.attacks, a)
	self:_emit_attack(a)
	local name = self.cs.list[c].name
	table.insert(self._ev, { Ev.MSG, self.C + hd, Defs.MSG_BAD, ("%s is attacking %s"):format(self.plague_name, name) })
	self._pl_dirty = true
	return true
end

function PlagueSim._emit_attack(self: any, a: any)
	table.insert(self._ev, { Ev.ATTACK, a.aid, self.C + a.k, self.C + a.q, floor(a.troops), a.tile, false, a.c })
end

--- The running plague calls attack `aid` back: its troops go home (sick again in the country they left).
function PlagueSim._retreat(self: any, aid: number)
	for i, a in self.attacks do
		if a.aid == aid and a.k == self.cur then
			table.remove(self.attacks, i)
			self:_front_paint(a, 0, true)
			local src = a.src
			if src >= 1 and self.holder[src] == self.cur then
				local back = math.min(a.troops, self.Hc[src])
				self.Hc[src] -= back
				self.Ic[src] += back
			end
			self:_emit({ Ev.ATTACK_END, aid })
			return
		end
	end
end

--- Country c's tiles in order outward from `start` (a front crossing it): a buffer of tile ids and
--- their count (the tiles reached across its own land).
function PlagueSim._front_order(self: any, c: number, start: number): (buffer, number)
	local grid, W, N = self.cs.grid, self.W, self.N
	local n = self.cs.list[c].tiles
	local order = buffer.create(math.max(1, n) * 4)
	if start < 0 or start >= N or readu8(grid, start) ~= c then
		start = self.cs.list[c].label
	end
	local seen = {}
	seen[start] = true
	buffer.writei32(order, 0, start)
	local head, tail = 0, 1
	while head < tail and tail < n do
		local t = buffer.readi32(order, head * 4)
		head += 1
		local x = t % W
		local function try(u: number)
			if tail < n and not seen[u] and readu8(grid, u) == c then
				seen[u] = true
				buffer.writei32(order, tail * 4, u)
				tail += 1
			end
		end
		if x > 0 then
			try(t - 1)
		end
		if x < W - 1 then
			try(t + 1)
		end
		if t >= W then
			try(t - W)
		end
		if t + W < N then
			try(t + W)
		end
		if head % 4096 == 0 then
			Coop.check()
		end
	end
	return order, tail
end

--- Repaints attack a's front to `want` tiles: newly crossed tiles in the attacker's colour, given-back
--- ones in the defender's again (at most R.INVADE_PAINT a call unless `all`).
function PlagueSim._front_paint(self: any, a: any, want: number, all: boolean?)
	local order = a.order
	if order == nil then
		return
	end
	local ts = self.tstate
	local budget = if all then math.huge else R.INVADE_PAINT
	local mine = (a.k - 1) * 8
	local theirs = self:_pbits(a.c)
	while a.painted < want and budget > 0 do
		local t = buffer.readi32(order, a.painted * 4)
		a.painted += 1
		budget -= 1
		self:_set_flag(t, F_INF + (if readu8(ts, t) == T_DEAD then F_DEAD else 0) + mine)
	end
	while a.painted > want and budget > 0 do
		local t = buffer.readi32(order, (a.painted - 1) * 4)
		a.painted -= 1
		budget -= 1
		local st = readu8(ts, t)
		self:_set_flag(t, if st == T_DEAD then F_INF + F_DEAD + theirs elseif st == T_INF then F_INF + theirs else 0)
	end
	if a.painted > 0 then
		-- (the troop count rides the front)
		a.tile = buffer.readi32(order, (a.painted - 1) * 4)
	end
end

--- Every attack fights a tick (R.FIGHT_RATE) and its front moves (R.INVADE_*): it takes the country
--- once the front has crossed it, or is beaten back.
function PlagueSim._fight(self: any)
	if #self.attacks == 0 then
		if next(self.contested) ~= nil then
			table.clear(self.contested)
		end
		return
	end
	local dt = 1 / R.DAY_TICKS
	local keep = {}
	local update = self.tick % 5 == 0
	for _, a in self.attacks do
		local c = a.c
		local hd = self.holder[c]
		self:_use(a.k)
		if self.out then
			self:_emit({ Ev.ATTACK_END, a.aid })
			continue
		end
		if hd == 0 or hd == a.k then
			-- (its defenders died out, or it is ours by now: the troops move in)
			self:_seed(c, a.tile, a.troops)
			self:_emit({ Ev.ATTACK_END, a.aid })
			continue
		end
		a.q = hd
		if a.order == nil then
			a.order, a.n = self:_front_order(c, a.start)
		end
		local sa = R.ATTACK_BASE + (self.inf_m or 0)
		local sd = (R.ATTACK_BASE + (self:_pget(hd, "inf_m") or 0)) * R.DEFEND_K
		local A, D = a.troops, self.Ic[c]
		local lost_d = math.min(D, R.FIGHT_RATE * sa * A * dt)
		local lost_a = math.min(A, R.FIGHT_RATE * sd * D * dt)
		-- (beaten-back defenders recover: healthy again)
		self.Ic[c] = D - lost_d
		self.Hc[c] += lost_d
		a.troops = A - lost_a
		-- the front: forward while the attackers are the stronger, back while they are the weaker
		local pa, pd = a.troops * sa, self.Ic[c] * sd
		local edge = (pa - pd) / (pa + pd + 1)
		local days = R.INVADE_DAYS * math.sqrt(math.max(a.n, R.INVADE_REF_TILES * 0.1) / R.INVADE_REF_TILES)
		a.prog = math.clamp(a.prog + edge * dt / days, 0, 1)
		self:_front_paint(a, floor(a.prog * a.n))
		local name = self.cs.list[c].name
		if a.prog >= 1 and a.troops >= 1 then
			-- taken: the last defenders recover, the attackers move in, and it is safe a while
			local q_pid, q_name = self.C + hd, self:_pget(hd, "plague_name") or "another plague"
			self.Hc[c] += self.Ic[c]
			self.Ic[c] = 0
			local n = math.min(math.max(a.troops, R.INFECT_HOSTS), self.Hc[c])
			self.Hc[c] -= n
			self.Ic[c] = n
			self.holder[c] = a.k
			self:_front_paint(a, a.n, true)
			self.shield[c] = self.tick + R.CAPTURE_SHIELD_DAYS * R.DAY_TICKS
			self.beta_c[c] = self:_beta_of(c)
			self:_repaint(c)
			self:_emit({ Ev.ATTACK_END, a.aid })
			self:_emit({ Ev.P_CAPTURE, c, self.pid, q_pid })
			self:_news(Defs.MSG_ALERT, ("%s takes %s from %s"):format(self.plague_name, name, q_name))
			self._pl_dirty = true
		elseif a.troops < 1 then
			self:_front_paint(a, 0, true)
			self:_emit({ Ev.ATTACK_END, a.aid })
			table.insert(self._ev, { Ev.MSG, self.pid, Defs.MSG_BAD, ("Your attack on %s was beaten back"):format(name) })
			table.insert(self._ev, { Ev.MSG, self.C + hd, Defs.MSG_GOOD, ("You held %s"):format(name) })
		else
			table.insert(keep, a)
			if update then
				self:_emit_attack(a)
			end
		end
	end
	self.attacks = keep
	table.clear(self.contested)
	for _, a in keep do
		self.contested[a.c] = true
	end
end

--- A country changed hands: its red repainted in its new plague's colour.
function PlagueSim._repaint(self: any, c: number)
	local ts = self.tstate
	local bits = self:_pbits(c)
	for _, t in self.inf_list[c] do
		local st = readu8(ts, t)
		if st == T_INF then
			self:_set_flag(t, F_INF + bits)
		elseif st == T_DEAD then
			self:_set_flag(t, F_INF + F_DEAD + bits)
		end
	end
end

--- Travellers that reached the border plant the plague there.
function PlagueSim._walkers(self: any)
	local fl = self.flights
	if #fl == 0 then
		return
	end
	local tick = self.tick
	local keep = {}
	for _, f in fl do
		if f.arrive <= tick then
			self:_use(f.k or 1)
			local ok = self:_arrive(f.target, f.to_tile, nil, f.src)
			self:_emit({ Ev.P_FLIGHT_END, f.uid, if ok then 1 else 0 })
		else
			keep[#keep + 1] = f
		end
	end
	self.flights = keep
end

--- The "infect" click: plant the plague in country `c` across a border, or send a ship to it.
function PlagueSim._infect_click(self: any, c: number): boolean
	if self.phase ~= Defs.PHASE_PLAYING then
		return false
	end
	-- (a shared world: only this plague's own)
	local cur = self.cur
	for _, s in self.ships do
		if s.target == c and (s.k or 1) == cur then
			return false -- (a ship is already on its way there)
		end
	end
	for _, f in self.flights do
		if f.target == c and (f.k or 1) == cur then
			return false -- (a traveller is already on the way)
		end
	end
	local kind, src, cost, reason = self:route(c)
	if kind == nil then
		if reason ~= nil then
			table.insert(self._ev, { Ev.MSG, self.pid, Defs.MSG_INFO, reason })
		end
		return false
	end
	if self.dna < cost then
		table.insert(self._ev, { Ev.MSG, self.pid, Defs.MSG_INFO, ("You need %d DNA"):format(cost) })
		return false
	end
	if kind == "land" then
		self.dna -= cost
		self._pl_dirty = true
		local hd = if self.multi then self.holder[c] else 0
		if hd ~= 0 and hd ~= self.cur then
			-- (a shared world: across a border an attack starts at once, RoWorld's way)
			local troops = self:_draft(src)
			return self:_attack_start(c, src, troops, self.border_tile[c * 256 + src] or self.cs.list[c].label)
		end
		self:_walk(src, c)
		return true
	end
	-- sea: a ship sails from the source's coast to the target's
	local a, b, body = Reach.sea_ends(self.cs, self.map, src, c)
	if a < 0 or b < 0 then
		return false
	end
	local nav = self.nav
	local wa = nav:water_next_to(a, body)
	local wb = nav:water_next_to(b, body)
	if wa < 0 or wb < 0 then
		return false
	end
	local path = nav:find_path(wa, wb)
	if #path < 2 then
		table.insert(self._ev, { Ev.MSG, self.pid, Defs.MSG_INFO, "No sea route there" })
		return false
	end
	self.dna -= cost
	self._pl_dirty = true
	self.next_uid += 1
	local uid = self.next_uid
	local tpt = floor(100 / R.SHIP_TILES_PER_TICK)
	local arrive = self.tick + math.ceil(#path * tpt / 100)
	-- (a shared world: a ship to another plague's country carries the attack)
	local hd = if self.multi then self.holder[c] else 0
	local troops = if hd ~= 0 and hd ~= self.cur then self:_draft(src) else nil
	table.insert(
		self.ships,
		{ uid = uid, target = c, tile = b, path = path, start = self.tick, arrive = arrive, k = self.cur, troops = troops, src = src }
	)
	self:_emit({ Ev.UNIT_ADD, uid, Defs.U_TRANSPORT, self.pid, path, self.tick, tpt, 1 })
	return true
end

--- Trading partners for every port (see R.SHIP_PARTNERS): a deterministic weighted draw without
--- replacement, then made symmetric. Bounds the sea routes to look up and keeps islands supplied.
function PlagueSim._link_ports(self: any)
	local W = self.W
	local pop = self.pop
	local links = {}
	for _, a in self.ports do
		links[a.k] = {}
		a.partners = {}
	end
	for _, a in self.ports do
		local lst = self.ports_by_body[a.body] or {}
		local cands = {}
		local ax, ay = a.tile % W, a.tile // W
		for _, b in lst do
			if b.c ~= a.c then
				local d = sqrt((ax - b.tile % W) ^ 2 + (ay - b.tile // W) ^ 2)
				table.insert(cands, { b = b, w = pop[b.c] ^ R.PARTNER_POP_EXP / (1 + d / R.PARTNER_REACH) })
			end
		end
		for _ = 1, R.SHIP_PARTNERS do
			local total = 0
			for _, e in cands do
				total += e.w
			end
			if total <= 0 then
				break
			end
			local r = self.rng:randf() * total
			for k, e in cands do
				r -= e.w
				if r <= 0 then
					links[a.k][e.b.k] = e.b
					links[e.b.k][a.k] = a
					table.remove(cands, k)
					break
				end
			end
		end
	end
	for _, a in self.ports do
		local ks = {}
		for k in links[a.k] do
			table.insert(ks, k)
		end
		table.sort(ks)
		for _, k in ks do
			table.insert(a.partners, links[a.k][k])
		end
	end
end

function PlagueSim._refugees(self: any)
	if self.tick % R.DAY_TICKS ~= 5 or self.Dw <= 0 then
		return
	end
	local dead = self.Dw / self.world_pop
	local k = R.REFUGEE_K * dead * (1 + R.REFUGEE_STOW * self.fx.stow)
	local H, I, pop = self.Hc, self.Ic, self.pop
	local best = {} -- [country] = {port, highest partner infected share}
	for _, a in self.ports do
		local c = a.c
		if I[c] < 1 and H[c] >= 1 then
			local m = 0
			for _, b in a.partners do
				m = math.max(m, I[b.c] / pop[b.c])
			end
			local cur = best[c]
			if cur == nil or m > cur[2] then
				best[c] = { a, m }
			end
		end
	end
	for c = 1, self.C do
		local e = best[c]
		if e ~= nil and e[2] > 0 and self.rng:randf() < k * e[2] then
			if self:_seed(c, e[1].tile, R.SEED_HOSTS) and self.cs.list[c].pop >= 1e5 then
				self:_news(Defs.MSG_BAD, ("Refugee boats bring the disease to %s"):format(self.cs.list[c].name))
			end
		end
	end
end

--- The end (R.END_SEED_P): once a day, the last untouched places catch it from the dying world.
function PlagueSim._end_seed(self: any)
	if self.tick % R.DAY_TICKS ~= 7 or self.leth <= 0 or self.Dw < R.END_WORLD_DEAD * self.world_pop then
		return
	end
	local H, I = self.Hc, self.Ic
	for c = 1, self.C do
		if I[c] < 1 and H[c] >= 1 and self.rng:randf() < R.END_SEED_P then
			if self:_seed(c, -1, R.SEED_HOSTS) and self.cs.list[c].pop >= 1e5 then
				self:_news(Defs.MSG_BAD, ("Survivors carry the disease to %s"):format(self.cs.list[c].name))
			end
		end
	end
end

function PlagueSim._pick_port(self: any, a: any): any
	local lst = a.partners
	if lst == nil or #lst == 0 then
		return nil
	end
	local closed = self.closed
	local pop = self.pop
	local function weight(b: any): number
		if self.Hc[b.c] < 1 and self.Ic[b.c] < 1 then
			return 0
		end
		local w = pop[b.c] ^ R.PARTNER_POP_EXP
		if bit32.band(closed[b.c], C_PORT) ~= 0 then
			w *= R.CLOSED_PORT_TRAFFIC
		end
		return w
	end
	local total = 0
	for _, b in lst do
		total += weight(b)
	end
	if total <= 0 then
		return nil
	end
	local r = self.rng:randf() * total
	for _, b in lst do
		local w = weight(b)
		r -= w
		if w > 0 and r <= 0 then
			return b
		end
	end
	return nil
end

function PlagueSim._flights(self: any)
	local tick = self.tick
	local slot = tick % R.DAY_TICKS
	local rng = self.rng
	local closed = self.closed
	local flights = self.flights
	if #flights > 0 then
		local keep = {}
		for _, f in flights do
			if f.arrive <= tick then
				local to = f.to
				local seeded = false
				if f.infected and bit32.band(closed[to.c], C_AIR) == 0 then
					seeded = self:_seed(to.c, to.tile, R.SEED_HOSTS)
				end
				self:_emit({ Ev.P_FLIGHT_END, f.uid, if seeded then 1 else 0 })
			else
				keep[#keep + 1] = f
			end
		end
		self.flights = keep
		flights = keep
	end
	if #flights >= R.MAX_FLIGHTS then
		return
	end
	local p_day = 1 / R.FLIGHT_DAYS
	local W = self.W
	for _, a in self.airports do
		if a.k % R.DAY_TICKS ~= slot or bit32.band(closed[a.c], C_AIR + C_COLLAPSE) ~= 0 then
			continue
		end
		if rng:randf() >= p_day then
			continue
		end
		local b = self:_pick_airport(a)
		if b == nil then
			continue
		end
		local ax, ay = a.tile % W, a.tile // W
		local bx, by = b.tile % W, b.tile // W
		local dist = sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
		local ft = math.clamp(floor(dist / R.FLIGHT_SPEED), R.FLIGHT_MIN_TICKS, R.FLIGHT_MAX_TICKS)
		local prev = self.Ic[a.c] / self.pop[a.c]
		local infected = rng:randf() < carry(prev, R.FLIGHT_CARRY, self.fx.air)
		self.next_uid += 1
		local uid = self.next_uid
		table.insert(self.flights, { uid = uid, from = a, to = b, infected = infected, launch = tick, arrive = tick + ft })
		self:_emit({ Ev.P_FLIGHT, uid, a.tile, b.tile, tick, ft, if infected then 1 else 0, a.c })
		if #self.flights >= R.MAX_FLIGHTS then
			break
		end
	end
end

function PlagueSim._pick_airport(self: any, a: any): any
	local total = 0
	local closed = self.closed
	local pop = self.pop
	local W = self.W
	local ax, ay = a.tile % W, a.tile // W
	local ws = {}
	for k, b in self.airports do
		local w = 0
		if b.c ~= a.c and bit32.band(closed[b.c], C_AIR) == 0 then
			local d = sqrt((ax - b.tile % W) ^ 2 + (ay - b.tile // W) ^ 2)
			w = sqrt(pop[b.c]) / (1 + d / R.FLIGHT_REACH)
		end
		ws[k] = w
		total += w
	end
	if total <= 0 then
		return nil
	end
	local r = self.rng:randf() * total
	for k, b in self.airports do
		r -= ws[k]
		if ws[k] > 0 and r <= 0 then
			return b
		end
	end
	return nil
end

function PlagueSim._awareness(self: any, dt: number)
	local seen = (self.Iw + self.Dw) / self.world_pop
	if seen > 0 then
		local sev = self.sev + R.SEV_FLOOR * self.pathogen.sev
		if self.multi then
			-- (a shared world: the most noticeable plague sets the pace)
			for k = 1, self.K do
				local p = self:_pget(k, "pathogen")
				sev = math.max(sev, (self:_pget(k, "sev") or 0) + R.SEV_FLOOR * p.sev)
			end
		end
		self.aware += R.AWARE_K[self.di] * sev * sqrt(seen) * dt
	end
	if not self.research and self.aware >= 1 then
		self.research = true
		self.next_cure_bubble_tick = self.tick + 6 * R.DAY_TICKS
		self:_news(Defs.MSG_ALERT, "The world noticed your plague. The cure race has started!")
		self._pl_dirty = true
	end
end

--- What the batched news says (PlagueSim._flush_news), in the order it is said: one country's line,
--- several countries' line (%s: "A and B", "A, B and C", "A, B and 3 more"), its category.
local NEWS_KINDS = {
	{ key = "first", one = "First cases reported in %s", many = "First cases reported in %s", cat = Defs.MSG_ALERT },
	{ key = "air", bit = C_AIR, one = "%s closes its airports", many = "%s close their airports", cat = Defs.MSG_BAD },
	{
		key = "port",
		bit = C_PORT,
		one = "%s closes its ports (ships cost more)",
		many = "%s close their ports (ships cost more)",
		cat = Defs.MSG_BAD,
	},
	{
		key = "border",
		bit = C_BORDER,
		one = "%s closes its borders (costs more to reach)",
		many = "%s close their borders (cost more to reach)",
		cat = Defs.MSG_BAD,
	},
	{
		key = "quarantine",
		bit = C_QUARANTINE,
		one = "%s goes into quarantine (spreads slower)",
		many = "%s go into quarantine (spread slower)",
		cat = Defs.MSG_BAD,
	},
	{
		key = "collapse",
		bit = C_COLLAPSE,
		one = "%s has collapsed (no more cure work there)",
		many = "%s have collapsed (no more cure work there)",
		cat = Defs.MSG_GOOD,
	},
}

--- "A", "A and B", "A, B and C", "A, B and 3 more".
local function name_list(names: { string }): string
	local n = #names
	if n == 1 then
		return names[1]
	elseif n == 2 then
		return names[1] .. " and " .. names[2]
	elseif n == 3 then
		return names[1] .. ", " .. names[2] .. " and " .. names[3]
	end
	return ("%s, %s and %d more"):format(names[1], names[2], n - 2)
end

--- Gathers a line of news about country `name` (said by _flush_news).
function PlagueSim._queue_news(self: any, key: string, name: string)
	local q = self.news_q[key]
	if q == nil then
		q = {}
		self.news_q[key] = q
	end
	if not table.find(q, name) then
		table.insert(q, name)
	end
end

--- Every NEWS_BATCH_DAYS: what was gathered, one line a kind.
function PlagueSim._flush_news(self: any)
	if self.tick < self.next_news_tick then
		return
	end
	self.next_news_tick = self.tick + R.NEWS_BATCH_DAYS * R.DAY_TICKS
	for _, n in NEWS_KINDS do
		local q = self.news_q[n.key]
		if q ~= nil and #q > 0 then
			self:_news(n.cat, (if #q == 1 then n.one else n.many):format(name_list(q)))
		end
	end
	table.clear(self.news_q)
end

function PlagueSim._gov(self: any)
	if not self.research then
		return
	end
	local C = self.C
	local tick = self.tick
	local rng = self.rng
	local list = self.cs.list
	local I, D, pop = self.Ic, self.Dc, self.pop
	local sevk = 1 + self.sev / 10
	local diff = R.GOV_DIFF[self.di]
	local world_alarm = (self.Iw + self.Dw) / self.world_pop * sevk
	local alarm = self.alarm
	for c = 1, C do
		if (tick + c) % R.GOV_THINK ~= 0 then
			continue
		end
		local a = (I[c] + D[c]) / pop[c] * sevk * self.nerve[c] * diff
		alarm[c] = a
		local cc = list[c]
		local cl = self.closed[c]
		local nc = cl
		local island = #cc.neighbors == 0
		local worried = island and world_alarm * diff >= R.ISLAND_WORLD_ALARM
		if D[c] / pop[c] >= R.COLLAPSE_DEAD then
			nc = bit32.bor(nc, C_COLLAPSE)
		end
		local nmax = 0
		for _, nb in cc.neighbors do
			nmax = math.max(nmax, alarm[nb[1]])
		end
		local lax = self.lax[c]
		if bit32.band(nc, C_AIR) == 0 and bit32.band(lax, C_AIR) == 0 and #cc.airports > 0 then
			local thr = if cc.wealth >= 4 then R.CLOSE_AIR_RICH else R.CLOSE_AIR
			if a >= thr and rng:randf() < R.GOV_ACT_P or worried and rng:randf() < R.ISLAND_ACT_P then
				nc = bit32.bor(nc, C_AIR)
			end
		end
		if bit32.band(nc, C_PORT) == 0 and bit32.band(lax, C_PORT) == 0 and #cc.ports > 0 then
			if
				(a >= R.CLOSE_PORT or nmax >= 2 * R.CLOSE_BORDER_NEIGHBOUR) and rng:randf() < R.GOV_ACT_P
				or worried and rng:randf() < R.ISLAND_ACT_P
			then
				nc = bit32.bor(nc, C_PORT)
			end
		end
		if bit32.band(nc, C_BORDER) == 0 and not island then
			if nmax >= R.CLOSE_BORDER_NEIGHBOUR and rng:randf() < R.GOV_ACT_P then
				nc = bit32.bor(nc, C_BORDER)
			end
		end
		if bit32.band(nc, C_QUARANTINE) == 0 and a >= R.QUARANTINE and rng:randf() < R.GOV_ACT_P then
			nc = bit32.bor(nc, C_QUARANTINE)
		end
		if nc ~= cl then
			self.closed[c] = nc
			self:_emit({ Ev.P_CLOSE, c, nc })
			local added = bit32.band(nc, bit32.bnot(cl))
			if bit32.band(added, C_QUARANTINE) ~= 0 then
				self.beta_c[c] = self:_beta_for(c)
			end
			if cc.pop >= 30e6 or island and cc.pop >= 1e6 then
				for _, n in NEWS_KINDS do
					if n.bit ~= nil and bit32.band(added, n.bit) ~= 0 then
						self:_queue_news(n.key, cc.name)
					end
				end
			end
			self._pl_dirty = true
		end
	end
end

function PlagueSim._cure(self: any, dt: number)
	if not self.research then
		return
	end
	local C = self.C
	local list = self.cs.list
	local H, I, pop = self.Hc, self.Ic, self.pop
	local num, den = 0, 0
	for c = 1, C do
		local w = list[c].wealth ^ 1.5
		den += w
		if bit32.band(self.closed[c], C_COLLAPSE) == 0 then
			local f = self.funding[c]
			if f < 1 then
				f = math.min(1, f + dt * (R.FUND_BASE * (0.6 + 0.2 * list[c].wealth) + R.FUND_ALARM * math.min(self.alarm[c], 1)))
				self.funding[c] = f
			end
			local lab = if (self.lab_cov[c] or 0) > 0 then 1 + R.LAB_RESEARCH else 1
			num += w * (H[c] + R.SICK_RESEARCHER * I[c]) / pop[c] * f * lab
		end
	end
	local panic = 1 + R.PANIC * math.min(1, R.PANIC_DEAD * self.Dw / self.world_pop)
	local resist = self.resist + self.perk_resist
	if self.multi then
		-- (a shared world: one cure for every plague, slowed by their mean resistance)
		local sum, n = 0, 0
		for k = 1, self.K do
			if not self:_pget(k, "out") then
				sum += (self:_pget(k, "resist") or 0) + (self:_pget(k, "perk_resist") or 0)
				n += 1
			end
		end
		resist = if n > 0 then sum / n else 0
	end
	local rate = if den > 0 then num / den / R.CURE_DAYS[self.di] / (1 + resist) * panic else 0
	self.cure_rate = rate
	self.cure = math.min(1, self.cure + rate * dt)
	if self.cure >= 1 then
		self:_news(Defs.MSG_GOOD, "The cure is ready")
		self:_over(Defs.OVER_CURED)
	end
end

function PlagueSim._dna(self: any, dt: number)
	local wp = self.world_pop
	-- (a shared world: from this plague's own sick and dead)
	local Iw = if self.multi then self.Ik or 0 else self.Iw
	local Dw = if self.multi then self.kills or 0 else self.Dw
	if Iw + Dw <= 0 then
		return
	end
	self.dna_acc += (R.DNA_BASE + R.DNA_INFECTED * sqrt(Iw / wp) + R.DNA_DEAD * sqrt(Dw / wp)) * dt
	if self.dna_acc >= 1 then
		local whole = floor(self.dna_acc)
		self.dna_acc -= whole
		self.dna += whole
		self.dna_earned += whole
		self._pl_dirty = true
	end
end

function PlagueSim._add_bubble(self: any, kind: number, c: number, tile: number, value: number)
	-- (over its kind's cap: added to the newest live bubble of that kind, which pays both and lives on;
	-- the same id sent again carries its new value)
	local cap = if kind == PlagueSim.B_DNA
		then R.MAX_DNA_BUBBLES
		elseif kind == PlagueSim.B_CURE then R.MAX_CURE_BUBBLES
		else math.huge
	-- (a shared world: a DNA bubble or a hotspot belongs to the plague it came up for)
	local owner = if self.multi and kind ~= PlagueSim.B_CURE then self.pid else 0
	local live, newest = 0, nil
	for _, o in self.bubbles do
		if o.kind == kind and (o.owner or 0) == owner then
			live += 1
			newest = o
		end
	end
	if newest ~= nil and live >= cap then
		newest.value += value
		newest.n = (newest.n or 1) + 1
		newest.expire = math.max(newest.expire, self.tick + R.BUBBLE_LIFE)
		self:_emit({ Ev.P_BUBBLE, newest.id, kind, newest.c, newest.tile, newest.value, newest.expire, owner })
		return
	end
	self.next_bubble_id += 1
	local b = {
		id = self.next_bubble_id,
		kind = kind,
		c = c,
		tile = tile,
		value = value,
		expire = self.tick + R.BUBBLE_LIFE,
		n = 1,
		owner = owner,
	}
	table.insert(self.bubbles, b)
	self:_emit({ Ev.P_BUBBLE, b.id, kind, c, tile, value, b.expire, owner })
end

function PlagueSim._bubbles(self: any)
	local tick = self.tick
	local bs = self.bubbles
	if #bs > 0 then
		local keep = {}
		for _, b in bs do
			if b.expire <= tick then
				self:_emit({ Ev.P_BUBBLE_END, b.id, 0 })
			else
				keep[#keep + 1] = b
			end
		end
		self.bubbles = keep
	end
	local rng = self.rng
	-- (the order is DNA bubbles, the cure's, then hotspots: the rng draws stay those of solo)
	for k = 1, self.K do
		if not self:_pget(k, "out") then
			self:_use(k)
			self:_plague_bubbles(tick, rng, false)
		end
	end
	if self.research and tick >= self.next_cure_bubble_tick then
		self.next_cure_bubble_tick = tick + rng:randi_range(R.CURE_BUBBLE_DAYS[1], R.CURE_BUBBLE_DAYS[2]) * R.DAY_TICKS
		local pool = {}
		for c = 1, self.C do
			if self.funding[c] >= 0.2 and bit32.band(self.closed[c], C_COLLAPSE) == 0 then
				table.insert(pool, c)
			end
		end
		if #pool > 0 then
			local c = pool[rng:randi_range(1, #pool)]
			self:_add_bubble(PlagueSim.B_CURE, c, self.cs.list[c].label, R.CURE_BUBBLE_DNA)
		end
	end
	for k = 1, self.K do
		if not self:_pget(k, "out") then
			self:_use(k)
			self:_plague_bubbles(tick, rng, true)
		end
	end
end

--- The running plague's DNA bubbles (hot = false) or its hotspot (hot = true); in a shared world each
--- plague has its own.
function PlagueSim._plague_bubbles(self: any, tick: number, rng: any, hot: boolean)
	local multi, holder, cur = self.multi, self.holder, self.cur
	local function mine(c: number): boolean
		return not multi or holder[c] == cur
	end
	if not hot and tick >= self.next_bubble_tick then
		self.next_bubble_tick = tick
			+ math.floor(rng:randi_range(R.BUBBLE_DAYS[1], R.BUBBLE_DAYS[2]) * R.DAY_TICKS / self.bubble_rate)
		local pool = {}
		for c = 1, self.C do
			if self.Ic[c] >= 1 and mine(c) then
				table.insert(pool, c)
			end
		end
		if #pool > 0 then
			local c = pool[rng:randi_range(1, #pool)]
			local il = self.inf_list[c]
			local t = if #il > 0 then il[rng:randi_range(1, #il)] else self.cs.list[c].label
			self:_add_bubble(PlagueSim.B_DNA, c, t, rng:randi_range(R.BUBBLE_VALUE[1], R.BUBBLE_VALUE[2]))
		end
	end
	-- a hotspot over an uninfected neighbour of the plague
	if not hot then
		return
	end
	if self.next_hot_tick == 0 then
		self.next_hot_tick = tick + R.HOTSPOT_DAYS[1] * R.DAY_TICKS
	elseif tick >= self.next_hot_tick then
		self.next_hot_tick = tick + rng:randi_range(R.HOTSPOT_DAYS[1], R.HOTSPOT_DAYS[2]) * R.DAY_TICKS
		local pool, seen = {}, {}
		local list = self.cs.list
		for c = 1, self.C do
			if self.Ic[c] >= 1 and mine(c) then
				for _, nb in list[c].neighbors do
					local n = nb[1]
					if not seen[n] and self.Ic[n] < 1 and self.Hc[n] >= 1 and (not multi or holder[n] == 0) then
						seen[n] = true
						table.insert(pool, n)
					end
				end
			end
		end
		for _, b in self.bubbles do
			if b.kind == PlagueSim.B_HOT and (not multi or b.owner == self.pid) then
				pool = {} -- (one at a time)
			end
		end
		if #pool > 0 then
			local c = pool[rng:randi_range(1, #pool)]
			self:_add_bubble(PlagueSim.B_HOT, c, list[c].label, R.HOTSPOT_DNA)
		end
	end
end

function PlagueSim._mutation(self: any)
	local p = self.pathogen
	local Iw = if self.multi then self.Ik or 0 else self.Iw
	if self.tick % R.DAY_TICKS ~= 0 or self.fx.lock > 0 or p.mutate <= 0 or Iw < 1 then
		return
	end
	local spread = math.min(1, sqrt(Iw / self.world_pop) * 4)
	if self.rng:randf() >= p.mutate * spread then
		return
	end
	local pool = {}
	for _, t in Traits.list do
		if t.tree == "symptoms" and t.cost <= 9 and (t.fx.leth or 0) <= 0.002 and Traits.reachable(t.id, self.owned) then
			table.insert(pool, t.id)
		end
	end
	if #pool == 0 then
		return
	end
	local id = pool[self.rng:randi_range(1, #pool)]
	self.owned[id] = true
	self:_recompute()
	self:_emit({ Ev.P_TRAIT, id, 1, 1, self.pid })
	self:_tell(Defs.MSG_INFO, ("%s mutated: %s"):format(self.plague_name, Traits.by_id[id].name))
end

function PlagueSim._check_over(self: any)
	if self.multi then
		self:_check_over_multi()
		return
	end
	if self.Hw + self.Iw < 1 then
		self:_news(Defs.MSG_ALERT, ("%s has wiped out humanity"):format(self.plague_name))
		self:_over(Defs.OVER_EXTINCT)
		return
	end
	if self.Iw < 1 then
		if #self.ships > 0 or #self.flights > 0 then
			return -- (a ship still carries it)
		end
		self:_news(Defs.MSG_GOOD, ("%s has died out"):format(self.plague_name))
		self:_over(Defs.OVER_BURNOUT)
	end
end

--- A shared world: a plague with nobody sick and nothing on its way is out; the last one left wins;
--- humanity gone, the deadliest wins.
function PlagueSim._check_over_multi(self: any)
	local on_way = {}
	for _, s in self.ships do
		on_way[s.k or 1] = true
	end
	for _, f in self.flights do
		on_way[f.k or 1] = true
	end
	for _, a in self.attacks do
		on_way[a.k] = true
	end
	local alive = {}
	for k = 1, self.K do
		if not self:_pget(k, "out") then
			if (self:_pget(k, "Ik") or 0) < 1 and not on_way[k] then
				self:_pset(k, "out", true)
				self:_news(Defs.MSG_ALERT, ("%s has died out"):format(self:_pget(k, "plague_name")))
				self._pl_dirty = true
			else
				table.insert(alive, k)
			end
		end
	end
	if self.Hw + self.Iw < 1 then
		local best, best_kills = 0, -1
		for k = 1, self.K do
			local kills = self:_pget(k, "kills") or 0
			if kills > best_kills then
				best, best_kills = k, kills
			end
		end
		self:_news(Defs.MSG_ALERT, ("Humanity is gone. %s killed the most"):format(self:_pget(best, "plague_name")))
		self:_over(Defs.OVER_EXTINCT, self.C + best)
	elseif #alive == 0 then
		self:_news(Defs.MSG_GOOD, "Every plague has died out")
		self:_over(Defs.OVER_BURNOUT, 0)
	elseif #alive == 1 then
		self:_news(Defs.MSG_ALERT, ("%s is the last plague standing"):format(self:_pget(alive[1], "plague_name")))
		self:_over(Defs.OVER_LAST, self.C + alive[1])
	end
end

function PlagueSim._over(self: any, reason: number, winner: number?)
	if self.phase == Defs.PHASE_OVER then
		return
	end
	self.phase = Defs.PHASE_OVER
	self.over_reason = reason
	-- (a duel: the cure's player wins when the plague is cured or burns out; a shared world: `winner`)
	self.winner = if winner ~= nil
		then winner
		elseif reason == Defs.OVER_EXTINCT then self.pid
		elseif self.cure_pid ~= 0 then self.cure_pid
		else 0
	self:_emit({ Ev.GAME_OVER, self.winner, reason, 0 })
	self:_emit({ Ev.PHASE, Defs.PHASE_OVER, 0 })
	self._pl_dirty = true
end

-- =============================================================================================
-- Rows (snapshot / delta)
-- =============================================================================================

--- The plague's numbers. full: every country's row too ({c, healthy, infected, dead, closed, funding %}).
function PlagueSim._pl_rows(self: any, full: boolean): { [string]: any }
	local inf, sev, leth = self:meters()
	local pl = {
		dna = self.dna,
		cure = self.cure,
		cure_rate = self.cure_rate,
		aware = self.aware,
		research = self.research,
		H = self.Hw,
		I = self.Iw,
		D = self.Dw,
		peak = self.peak_I,
		inf = inf,
		sev = sev,
		leth = leth,
		ability_ready = self.ability_ready,
		start_c = self.start_c,
		price_mult = self.price_mult,
		sea_bonus = self.sea_bonus,
		-- multiplayer (Data/PlagueModes): the mode, and a duel's cure side
		mode = self.mode,
		cure_pid = self.cure_pid,
		cure_name = self.cure_name,
		funds = self.cure_funds,
	}
	if self.multi then
		-- a shared world: every plague's numbers (GameState shows its local player's as `plague`)
		local held = {}
		for c = 1, self.C do
			local h = self.holder[c]
			if h > 0 then
				held[h] = (held[h] or 0) + 1
			end
		end
		local list = {}
		for k = 1, self.K do
			self:_use(k)
			local mi, ms, ml = self:meters()
			local row = {
				pid = self.pid,
				name = self.plague_name,
				pathogen = self.pathogen.id,
				dna = self.dna,
				inf = mi,
				sev = ms,
				leth = ml,
				ability_ready = self.ability_ready,
				start_c = self.start_c,
				price_mult = self.price_mult,
				sea_bonus = self.sea_bonus,
				kills = floor(self.kills or 0),
				I = floor(self.Ik or 0),
				D = floor(self.Dk or 0),
				held = held[k] or 0,
				out = self.out == true,
				human = self.human_name,
			}
			if full then
				local owned = {}
				for id, on in self.owned do
					if on then
						table.insert(owned, id)
					end
				end
				table.sort(owned)
				row.owned = owned
			end
			list[k] = row
		end
		pl.plagues = list
	end
	if full then
		local rows = {}
		for c = 1, self.C do
			if self.first_tick[c] >= 0 or self.closed[c] ~= 0 or self.funding[c] > 0 then
				local h = self.holder[c]
				table.insert(rows, {
					c,
					self.Hc[c],
					self.Ic[c],
					self.Dc[c],
					self.closed[c],
					floor(self.funding[c] * 100),
					if self.multi and h > 0 then self.C + h else 0,
				})
			end
		end
		pl.c = rows
	end
	return pl
end

--- Owner stats rows, the channel RoWorld used for troops: {id, tiles, troops, gold, cap, income} per
--- owner. Here troops = the country's infected and gold = its dead, so RoWorld's name labels show the
--- infected count under every country's name.
function PlagueSim._stats_rows(self: any): { number }
	local out = table.create(self.C * 6)
	local list = self.cs.list
	local floor_ = floor
	for c = 1, self.C do
		local n = #out
		out[n + 1] = c
		out[n + 2] = list[c].tiles
		out[n + 3] = floor_(self.Ic[c])
		out[n + 4] = floor_(self.Dc[c])
		out[n + 5] = floor_(self.pop[c])
		out[n + 6] = 0
	end
	return out
end

function PlagueSim.snapshot(self: any): { [string]: any }
	local owners = {}
	local list = self.cs.list
	for c = 1, self.C do
		local cc = list[c]
		table.insert(owners, {
			c,
			cc.name,
			cc.rgba,
			Defs.KIND_NATION,
			0,
			true,
			cc.tiles,
			floor(self.Ic[c]),
			floor(self.Dc[c]),
			floor(self.pop[c]),
			0,
			0,
			cc.label,
		})
	end
	-- the plagues (a shared world: one owner each)
	for k = 1, self.K do
		self:_use(k)
		table.insert(owners, {
			self.pid,
			self.plague_name,
			PATHOGEN_RGBA[self.pathogen.id] or Defs.html_rgba("#e04848"),
			Defs.KIND_HUMAN,
			0,
			true,
			0,
			0,
			0,
			0,
			0,
			0,
			self.start_tile or -1,
		})
	end
	self:_use(1)
	if self.cure_pid ~= 0 then
		-- a duel: the cure's player is an owner of its own (no land), so its client has a local owner
		table.insert(owners, {
			self.cure_pid,
			if self.cure_name ~= "" then self.cure_name else "The Cure",
			Defs.html_rgba("#3cb4ff"),
			Defs.KIND_HUMAN,
			0,
			true,
			0,
			0,
			0,
			0,
			0,
			0,
			-1,
		})
	end
	local units = {}
	local tpt = floor(100 / R.SHIP_TILES_PER_TICK)
	for _, s in self.ships do
		table.insert(units, { s.uid, Defs.U_TRANSPORT, self.C + (s.k or 1), s.path, s.start, tpt, 1 })
	end
	local flights = {}
	for _, f in self.flights do
		table.insert(flights, { f.uid, f.from_tile, f.to_tile, f.launch, f.arrive - f.launch, 1, f.src, self.C + (f.k or 1) })
	end
	local bubbles = {}
	for _, b in self.bubbles do
		table.insert(bubbles, { b.id, b.kind, b.c, b.tile, b.value, b.expire, b.owner or 0 })
	end
	local owned = {}
	for id, on in self.owned do
		if on then
			table.insert(owned, id)
		end
	end
	table.sort(owned)
	local pl = self:_pl_rows(true)
	pl.owned = owned
	pl.bubbles = bubbles
	pl.flights = flights
	pl.pathogen = self.pathogen.id
	pl.name = self.plague_name
	pl.pid = self.pid
	pl.difficulty = self.difficulty
	local n = self.N
	local fl = buffer.create(n)
	buffer.copy(fl, 0, self.flags, 0, n)
	local own = buffer.create(n * 4)
	buffer.copy(own, 0, self.owner, 0, n * 4)
	return {
		map_id = self.map.id,
		map_w = self.W,
		map_h = self.H,
		t = self.tick,
		phase = self.phase,
		phase_left = self:spawn_ticks_left(),
		time_limit_ticks = 0,
		playing_since = self.playing_since,
		winner = self.winner,
		over_reason = self.over_reason,
		owner = own,
		flags = fl,
		owners = owners,
		structs = self.structs,
		units = units,
		attacks = (function()
			local rows = {}
			for _, a in self.attacks do
				table.insert(rows, { a.aid, self.C + a.k, self.C + a.q, floor(a.troops), a.tile, false, a.c })
			end
			return rows
		end)(),
		plague = pl,
	}
end

return PlagueSim
