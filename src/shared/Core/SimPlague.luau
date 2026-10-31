--!native
-- RoPlague on RoWorld's Sim (a mixin, installed like SimNukes / SimArsenal): evolutions (Data/Traits)
-- bought with gold (the HUD calls it DNA), their effects on the owner's troop growth and capacity,
-- attack costs and speed, boats and income (read by Sim._economy_tick, SimAttacks._process_attack and
-- SimNaval.launch_boat through fx_of), sickness across the owner's borders, and the solo cure race.
--
-- Events: Ev.EVOLVE {owner, trait id}; Ev.CURE {progress x 10000, research on (1 / 0), per-second rate
-- x 1e7} once a second while a cure runs. Intent: {type = "evolve", kind = trait id}.
local Defs = require("./Defs")
local Ev = require("./Ev")
local Traits = require("../Data/WarTraits")

local readi32 = buffer.readi32

local SimPlague = {}

SimPlague.DEFAULT_FX = Traits.effects({})
local DEFAULT = SimPlague.DEFAULT_FX

--- Seconds of research a full cure needs at full speed (casual, normal, brutal).
SimPlague.CURE_SECONDS = { 1500, 1080, 760 }
--- The world notices the plague once it holds this share of the land, or after this many ticks of play.
SimPlague.CURE_START_SHARE = 0.12
SimPlague.CURE_START_TICKS = 3000
--- Sickness: how long a nation counts as sick after the last check that found it on a border.
SimPlague.SICK_TICKS = 15

function SimPlague.install(C: any)
	function C:_init_plague(config: any)
		self.o_evo = {} :: { [number]: { [string]: boolean } }
		self.o_fx = {} :: { [number]: any }
		self.o_sick_until = {} :: { [number]: number }
		self.o_sick_mult = {} :: { [number]: number }
		self.cure = 0.0
		self.cure_on = false
		self.cure_rate = 0.0
		-- (solo only: a multiplayer match has its time limit; the title backdrop has no human)
		self.cure_enabled = (tonumber(config and config.max_humans) or 0) == 1 and config.cure ~= false
	end

	--- The owner's evolution effects (DEFAULT for an owner that never evolved).
	function C:fx_of(id: number): any
		local t = self.o_fx
		return if t ~= nil then (t[id] or DEFAULT) else DEFAULT
	end

	--- Troop growth multiplier while the owner is sick (Insanity on a border).
	function C:sick_mult(id: number): number
		if self.o_sick_until == nil then
			return 1.0
		end
		local u = self.o_sick_until[id]
		if u ~= nil and u > self.tick then
			return self.o_sick_mult[id] or 1.0
		end
		return 1.0
	end

	function C:_recompute_fx(id: number)
		self.o_fx[id] = Traits.effects(self.o_evo[id] or {})
	end

	--- Buys trait `trait` for owner `id` with gold. True when it was bought.
	function C:evolve(id: number, trait: string): boolean
		if self.o_alive[id] == 0 then
			return false
		end
		local owned = self.o_evo[id] or {}
		if not Traits.reachable(trait, owned) then
			return false
		end
		local price = Traits.price(trait, owned)
		if self.o_gold[id] < price then
			self:msg(id, Defs.MSG_INFO, "Not enough DNA to evolve that")
			return false
		end
		self.o_gold[id] -= price
		self:grant_evolution(id, trait)
		return true
	end

	--- Gives trait `trait` to owner `id` for free (a strain's starting evolution).
	function C:grant_evolution(id: number, trait: string)
		if Traits.by_id[trait] == nil then
			return
		end
		local owned = self.o_evo[id]
		if owned == nil then
			owned = {}
			self.o_evo[id] = owned
		end
		if owned[trait] then
			return
		end
		owned[trait] = true
		self:_recompute_fx(id)
		self:ev({ Ev.EVOLVE, id, trait })
	end

	--- Snapshot rows: {owner, {trait ids}}.
	function C:evo_rows(): { any }
		local out = {}
		local ids = {}
		for id in self.o_evo do
			table.insert(ids, id)
		end
		table.sort(ids)
		for _, id in ids do
			local list = {}
			for t, on in self.o_evo[id] do
				if on then
					table.insert(list, t)
				end
			end
			table.sort(list)
			table.insert(out, { id, list })
		end
		return out
	end

	--- Owners whose land touches `id`'s (walks its border list), ascending.
	function C:_neighbour_owners(id: number): { number }
		local seen = {}
		local list = {}
		local owner = self.owner
		local bnext = self.bnext
		local W = self.W
		local NW = self.N - W
		local t = self.bhead[id]
		local function see(o: number)
			if o > 0 and o ~= id and not seen[o] then
				seen[o] = true
				table.insert(list, o)
			end
		end
		while t ~= -1 do
			local x = t % W
			if x > 0 then
				see(readi32(owner, (t - 1) * 4))
			end
			if x < W - 1 then
				see(readi32(owner, (t + 1) * 4))
			end
			if t >= W then
				see(readi32(owner, (t - W) * 4))
			end
			if t < NW then
				see(readi32(owner, (t + W) * 4))
			end
			t = readi32(bnext, t * 4)
		end
		table.sort(list)
		return list
	end

	--- Once a second while playing: sickness across borders, then the cure.
	function C:plague_tick()
		if self.tick % 10 ~= 0 then
			return
		end
		local ids = {}
		for id in self.o_fx do
			table.insert(ids, id)
		end
		table.sort(ids)
		for _, id in ids do
			local fx = self.o_fx[id]
			if self.o_alive[id] == 1 and (fx.leth > 0 or fx.panic > 0) then
				for _, o in self:_neighbour_owners(id) do
					if self.o_alive[o] == 1 and not self:allied(id, o) then
						if fx.leth > 0 then
							local d = math.floor(self.o_troops[o] * fx.leth)
							if d > 0 then
								self.o_troops[o] -= d
							end
						end
						if fx.panic > 0 then
							local cur = if (self.o_sick_until[o] or 0) > self.tick then (self.o_sick_mult[o] or 1.0) else 1.0
							self.o_sick_mult[o] = math.min(cur, 1.0 - fx.panic)
							self.o_sick_until[o] = self.tick + SimPlague.SICK_TICKS
						end
					end
				end
			end
		end
		self:_cure_tick()
	end

	--- The solo cure: the world notices the human plague, researches, and wins if it finishes first.
	function C:_cure_tick()
		if not self.cure_enabled or self.phase ~= Defs.PHASE_PLAYING then
			return
		end
		local human = 0
		for id = 1, self.owner_total do
			if self.o_kind[id] == Defs.KIND_HUMAN and self.o_bot[id] ~= 1 and self.o_alive[id] == 1 and self.o_spawned[id] == 1 then
				human = id
				break
			end
		end
		if human == 0 then
			return
		end
		local land = math.max(self.map.contestable_count, 1)
		local share = self.o_tiles[human] / land
		if not self.cure_on then
			local played = if self.playing_since >= 0 then self.tick - self.playing_since else 0
			if share >= SimPlague.CURE_START_SHARE or played >= SimPlague.CURE_START_TICKS then
				self.cure_on = true
				self:msg(-1, Defs.MSG_ALERT, ("The world has noticed %s! Scientists start working on a cure"):format(self.o_name[human]))
			end
		end
		if self.cure_on then
			local di = math.clamp(self.difficulty + 1, 1, 3)
			local fx = self:fx_of(human)
			-- the less of the world is left healthy, the slower the research
			local rate = (1.0 / SimPlague.CURE_SECONDS[di]) / (1.0 + fx.resist) * math.sqrt(math.max(0.0, 1.0 - share))
			self.cure_rate = rate
			local before = self.cure
			self.cure = math.min(1.0, self.cure + rate)
			for _, mark in { 0.5, 0.75, 0.9 } do
				if before < mark and self.cure >= mark then
					self:msg(-1, Defs.MSG_ALERT, ("The cure is %d%% done"):format(math.floor(mark * 100)))
				end
			end
			if self.cure >= 1.0 then
				self:ev({ Ev.CURE, 10000, 1, math.floor(rate * 1e7) })
				self:msg(-1, Defs.MSG_ALERT, ("The cure is ready. %s has been wiped out"):format(self.o_name[human]))
				self:_game_over(0, Defs.OVER_CURED)
				return
			end
		end
		self:ev({ Ev.CURE, math.floor(self.cure * 10000), if self.cure_on then 1 else 0, math.floor(self.cure_rate * 1e7) })
	end
end

return SimPlague
