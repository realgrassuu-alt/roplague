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
local Defs = require("../Defs")
local Ev = require("../Ev")
local Rng = require("../Rng")
local SimNav = require("../SimNav")
local Coop = require("../../Net/Coop")
local Traits = require("../../Data/Traits")
local Countries = require("./Countries")
local R = require("./PlagueRules")
local PlagueBot = require("./PlagueBot")

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

	self:_link_ports()

	-- the disease ------------------------------------------------------------------------------
	self.pathogen = Traits.pathogen_by_id[tostring(cfg.pathogen or "")] or Traits.PATHOGENS[1]
	self.plague_name = if type(cfg.name) == "string" and cfg.name ~= "" then cfg.name else self.pathogen.name
	self.dna = R.DNA_START
	self.dna_earned = R.DNA_START
	self.dna_acc = 0
	self.owned = {} :: { [string]: boolean }
	self.ability_ready = 0
	self.start_c = 0
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
	self.bubbles = {} -- ordered list of {id, kind, c, tile, value, expire}
	self.next_bubble_id = 0
	self.next_bubble_tick = 0
	self.next_cure_bubble_tick = 0

	-- per-tick output ------------------------------------------------------------------------
	self._intents = {}
	self._ev = {}
	self._flags = {}
	self._pl_dirty = true
	self.news_count = {}

	self.bot = if cfg.auto then PlagueBot.new(self, cfg.strategy, cfg.zero_after) else nil
	self:_recompute()
	return self
end

--- The local player (solo): returns the disease's owner id.
function PlagueSim.add_human(self: any, _key: string, display_name: string): number
	self.human = true
	self.human_name = display_name
	return self.pid
end

function PlagueSim.submit(self: any, owner_id: number, intent: { [string]: any })
	if owner_id == self.pid then
		table.insert(self._intents, intent)
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

--- Solo convenience: pick patient zero immediately. True when accepted.
function PlagueSim.human_start(self: any, _owner_id: number, tile: number): boolean
	return self:_start(tile)
end

function PlagueSim.spawn_ticks_left(self: any): number
	return if self.phase == Defs.PHASE_SPAWN then -1 else 0
end

function PlagueSim.owner_count(self: any): number
	return self.pid
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
	for c = 1, self.C do
		self.beta_c[c] = self:_beta_of(c)
	end
	self._pl_dirty = true
end

function PlagueSim._beta_of(self: any, c: number): number
	local cc = self.cs.list[c]
	local fx = self.fx
	local p = self.pathogen
	local b = R.BASE_BETA + fx.beta
	if cc.climate == "hot" then
		b += fx.hot
	end
	if cc.density == "urban" then
		b += fx.urban
	elseif cc.density == "rural" then
		b += fx.rural
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
	table.insert(self._ev, { Ev.P_DNA, amount, tile, reason })
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
	self:_set_flag(t, F_INF)
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
function PlagueSim._next_tile(self: any, c: number): number
	local front = self.front[c]
	local ts = self.tstate
	local rng = self.rng
	while #front > 0 do
		local j = rng:randi_range(1, #front)
		local t = front[j]
		front[j] = front[#front]
		front[#front] = nil
		if readu8(ts, t) == T_QUEUED then
			return t
		end
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
				self:_set_flag(t, F_INF + F_DEAD)
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
	local n = math.min(hosts, h)
	self.Hc[c] = h - n
	self.Ic[c] += n
	local cc = self.cs.list[c]
	if t < 0 or readu8(self.cs.grid, t) ~= c then
		t = cc.label
	end
	if self.first_tick[c] < 0 then
		self.first_tick[c] = self.tick
		self:_emit({ Ev.P_INFECTED, c, t })
		if not quiet then
			self:_gain(R.DNA_NEW_COUNTRY, t, PlagueSim.DNA_COUNTRY)
			self:_add_bubble(PlagueSim.B_DNA, c, t, R.NEW_COUNTRY_BUBBLE)
			if cc.pop >= 5e6 then
				self:_news(Defs.MSG_ALERT, ("First cases reported in %s"):format(cc.name))
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
	self.start_c = c
	self.phase = Defs.PHASE_PLAYING
	self.playing_since = self.tick
	self:_emit({ Ev.PHASE, Defs.PHASE_PLAYING, 0 })
	self:_seed(c, tile, 1, true)
	self.next_bubble_tick = self.tick + 4 * R.DAY_TICKS
	self:_news(Defs.MSG_INFO, ("Patient zero: an unknown illness in %s"):format(self.cs.list[c].name))
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
		if ty == "zero" then
			self:_start(tonumber(it.tile) or -1)
		elseif ty == "evolve" then
			self:_evolve(tostring(it.id))
		elseif ty == "devolve" then
			self:_devolve(tostring(it.id))
		elseif ty == "pop" then
			self:_pop(tonumber(it.id) or -1)
		elseif ty == "ability" then
			self:_ability(tostring(it.key))
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
	local price = Traits.price(id, self.owned)
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
	self:_emit({ Ev.P_TRAIT, id, 1, 0 })
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
	self:_emit({ Ev.P_TRAIT, id, 0, 2 })
	return true
end

function PlagueSim._pop(self: any, id: number): boolean
	for k, b in self.bubbles do
		if b.id == id then
			table.remove(self.bubbles, k)
			self:_emit({ Ev.P_BUBBLE_END, id, 1 })
			if b.kind == PlagueSim.B_CURE then
				self.cure = math.max(0, self.cure - R.CURE_BUBBLE_CUT)
				self:_gain(R.CURE_BUBBLE_DNA, b.tile, PlagueSim.DNA_CURE_BUBBLE)
			else
				self:_gain(b.value, b.tile, PlagueSim.DNA_BUBBLE)
			end
			return true
		end
	end
	return false
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
			if self.Ic[c] < 1 and self.Hc[c] >= 1 then
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
	if self.phase == Defs.PHASE_PLAYING then
		local dt = 1 / R.DAY_TICKS
		self:_population(dt)
		self:_land()
		Coop.check()
		self:_ships()
		self:_flights()
		self:_refugees()
		self:_awareness(dt)
		self:_gov()
		self:_cure(dt)
		self:_dna(dt)
		self:_bubbles()
		self:_mutation()
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
	local leth = self.leth
	local Hw, Iw, Dw = 0, 0, 0
	for c = 1, C do
		local i = I[c]
		local h = H[c]
		local d = D[c]
		if i > 0 then
			local alive = h + i
			local ni = beta[c] * i * h / alive * dt
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
			h -= ni
			i += ni - nd
			d += nd
			if h < 1 then
				i += h
				h = 0
			end
			if i < 0.5 then
				i = 0
			end
			H[c], I[c], D[c] = h, i, d
			if d >= 1 and not self.first_death[c] then
				self.first_death[c] = true
				self:_gain(R.DNA_FIRST_DEATH, self.cs.list[c].label, PlagueSim.DNA_DEATH)
			end
		end
		Hw += h
		Iw += i
		Dw += d
	end
	self.Hw, self.Iw, self.Dw = Hw, Iw, Dw
end

--- Land borders: each infected country, once a day (staggered), may seed each healthy neighbour.
function PlagueSim._land(self: any)
	local C = self.C
	local slot = self.tick % R.DAY_TICKS
	local list = self.cs.list
	local rng = self.rng
	local H, I, pop = self.Hc, self.Ic, self.pop
	local lm = self.land_mult
	for c = 1, C do
		if c % R.DAY_TICKS ~= slot or I[c] <= 0 then
			continue
		end
		local tot = self.border_total[c]
		if tot <= 0 then
			continue
		end
		local base = R.LAND_K * lm * (I[c] / pop[c]) ^ R.LAND_EXP
		for _, nb in list[c].neighbors do
			local n = nb[1]
			if I[n] >= 1 or H[n] < 1 then
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

function PlagueSim._ships(self: any)
	local tick = self.tick
	local slot = tick % R.DAY_TICKS
	local rng = self.rng
	local closed = self.closed
	-- arrivals
	local ships = self.ships
	if #ships > 0 then
		local keep = {}
		for _, s in ships do
			if s.arrive <= tick then
				local to = s.to
				local open = bit32.band(closed[to.c], C_PORT) == 0
				self:_emit({ Ev.UNIT_DEL, s.uid, if open then Defs.DEL_ARRIVED else Defs.DEL_INTERCEPTED })
				if s.infected and (open or rng:randf() < R.CLOSED_LEAK + self.fx.stow) then
					self:_seed(to.c, to.tile, R.SEED_HOSTS)
				end
			else
				keep[#keep + 1] = s
			end
		end
		self.ships = keep
		ships = keep
	end
	-- departures: each open port rolls once a day
	if #ships >= R.MAX_SHIPS then
		return
	end
	local p_day = 1 / R.SHIP_DAYS
	for _, a in self.ports do
		if a.k % R.DAY_TICKS ~= slot or bit32.band(closed[a.c], C_PORT + C_COLLAPSE) ~= 0 then
			continue
		end
		if rng:randf() >= p_day then
			continue
		end
		local b = self:_pick_port(a)
		if b == nil then
			continue
		end
		local path = self:_sea_path(a, b)
		if path == nil or #path < 2 then
			continue
		end
		local prev = self.Ic[a.c] / self.pop[a.c]
		local infected = rng:randf() < carry(prev, R.SHIP_CARRY, self.fx.water)
		self.next_uid += 1
		local uid = self.next_uid
		local tpt = floor(100 / R.SHIP_TILES_PER_TICK)
		local s = { uid = uid, from = a, to = b, infected = infected, arrive = tick + math.ceil(#path * tpt / 100) }
		table.insert(self.ships, s)
		self:_emit({ Ev.UNIT_ADD, uid, if infected then Defs.U_TRANSPORT else Defs.U_TRADE, a.c, path, tick, tpt, if infected then 1 else 0 })
		if #self.ships >= R.MAX_SHIPS then
			break
		end
	end
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
		self.aware += R.AWARE_K[self.di] * sev * sqrt(seen) * dt
	end
	if not self.research and self.aware >= 1 then
		self.research = true
		self.next_cure_bubble_tick = self.tick + 6 * R.DAY_TICKS
		self:_news(Defs.MSG_ALERT, ("The world has noticed %s. Researchers begin work on a cure"):format(self.plague_name))
		self._pl_dirty = true
	end
end

local CLOSE_NEWS = {
	[C_AIR] = "%s closes its airports",
	[C_PORT] = "%s closes its ports",
	[C_BORDER] = "%s closes its borders",
	[C_QUARANTINE] = "%s orders a nationwide quarantine",
	[C_COLLAPSE] = "Government collapse in %s",
}

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
				self.beta_c[c] = self:_beta_of(c)
			end
			if cc.pop >= 30e6 or island and cc.pop >= 1e6 then
				for bit, text in CLOSE_NEWS do
					if bit32.band(added, bit) ~= 0 then
						self:_news(if bit == C_COLLAPSE then Defs.MSG_GOOD else Defs.MSG_BAD, text:format(cc.name))
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
			num += w * (H[c] + R.SICK_RESEARCHER * I[c]) / pop[c] * f
		end
	end
	local panic = 1 + R.PANIC * math.min(1, R.PANIC_DEAD * self.Dw / self.world_pop)
	local rate = if den > 0 then num / den / R.CURE_DAYS[self.di] / (1 + self.resist) * panic else 0
	self.cure_rate = rate
	self.cure = math.min(1, self.cure + rate * dt)
	if self.cure >= 1 then
		self:_news(Defs.MSG_GOOD, "The cure is complete. It is being given out around the world")
		self:_over(Defs.OVER_CURED)
	end
end

function PlagueSim._dna(self: any, dt: number)
	local wp = self.world_pop
	if self.Iw + self.Dw <= 0 then
		return
	end
	self.dna_acc += (R.DNA_BASE + R.DNA_INFECTED * sqrt(self.Iw / wp) + R.DNA_DEAD * sqrt(self.Dw / wp)) * dt
	if self.dna_acc >= 1 then
		local whole = floor(self.dna_acc)
		self.dna_acc -= whole
		self.dna += whole
		self.dna_earned += whole
		self._pl_dirty = true
	end
end

function PlagueSim._add_bubble(self: any, kind: number, c: number, tile: number, value: number)
	self.next_bubble_id += 1
	local b = { id = self.next_bubble_id, kind = kind, c = c, tile = tile, value = value, expire = self.tick + R.BUBBLE_LIFE }
	table.insert(self.bubbles, b)
	self:_emit({ Ev.P_BUBBLE, b.id, kind, c, tile, value, b.expire })
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
	if tick >= self.next_bubble_tick then
		self.next_bubble_tick = tick + rng:randi_range(R.BUBBLE_DAYS[1], R.BUBBLE_DAYS[2]) * R.DAY_TICKS
		local pool = {}
		for c = 1, self.C do
			if self.Ic[c] >= 1 then
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
end

function PlagueSim._mutation(self: any)
	local p = self.pathogen
	if self.tick % R.DAY_TICKS ~= 0 or self.fx.lock > 0 or p.mutate <= 0 or self.Iw < 1 then
		return
	end
	local spread = math.min(1, sqrt(self.Iw / self.world_pop) * 4)
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
	self:_emit({ Ev.P_TRAIT, id, 1, 1 })
	self:_news(Defs.MSG_INFO, ("%s mutated: %s"):format(self.plague_name, Traits.by_id[id].name))
end

function PlagueSim._check_over(self: any)
	if self.Hw + self.Iw < 1 then
		self:_news(Defs.MSG_ALERT, ("%s has wiped out humanity"):format(self.plague_name))
		self:_over(Defs.OVER_EXTINCT)
		return
	end
	if self.Iw < 1 then
		for _, s in self.ships do
			if s.infected then
				return
			end
		end
		for _, f in self.flights do
			if f.infected then
				return
			end
		end
		self:_news(Defs.MSG_GOOD, ("%s has died out"):format(self.plague_name))
		self:_over(Defs.OVER_BURNOUT)
	end
end

function PlagueSim._over(self: any, reason: number)
	if self.phase == Defs.PHASE_OVER then
		return
	end
	self.phase = Defs.PHASE_OVER
	self.over_reason = reason
	self.winner = if reason == Defs.OVER_EXTINCT then self.pid else 0
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
		inf = inf,
		sev = sev,
		leth = leth,
		ability_ready = self.ability_ready,
		start_c = self.start_c,
	}
	if full then
		local rows = {}
		for c = 1, self.C do
			if self.first_tick[c] >= 0 or self.closed[c] ~= 0 or self.funding[c] > 0 then
				table.insert(rows, { c, self.Hc[c], self.Ic[c], self.Dc[c], self.closed[c], floor(self.funding[c] * 100) })
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
		-1,
	})
	local units = {}
	local tpt = floor(100 / R.SHIP_TILES_PER_TICK)
	for _, s in self.ships do
		local path = self.path_cache[s.from.k * 1024 + s.to.k] or {}
		local start = s.arrive - math.ceil(#path * tpt / 100)
		table.insert(units, { s.uid, if s.infected then Defs.U_TRANSPORT else Defs.U_TRADE, s.from.c, path, start, tpt, if s.infected then 1 else 0 })
	end
	local flights = {}
	for _, f in self.flights do
		table.insert(flights, { f.uid, f.from.tile, f.to.tile, f.launch, f.arrive - f.launch, if f.infected then 1 else 0, f.from.c })
	end
	local bubbles = {}
	for _, b in self.bubbles do
		table.insert(bubbles, { b.id, b.kind, b.c, b.tile, b.value, b.expire })
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
		plague = pl,
	}
end

return PlagueSim
