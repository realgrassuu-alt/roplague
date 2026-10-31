--!strict
-- RoPlague: a scripted player for the disease. It runs the title backdrop (a plague spreading behind
-- the menu) and the balance harness (tools/balance/run.luau). It acts only through intents, like a
-- person: it picks patient zero, pops bubbles, and buys traits from a plan.
--
-- Strategies:
--   balanced  spread first (transmission, resistances, a mild symptom), lethal once most of the world
--             is infected or the cure gets close, gene shields while research runs
--   rush      lethal symptoms from the start
--   stealth   spread only, never lethal (should not win: the disease never kills anyone)
--   random    any affordable trait, any time
local Defs = require("../Defs")
local Traits = require("../../Data/Traits")

local PlagueBot = {}
PlagueBot.__index = PlagueBot

local SPREAD = {
	"cough", "air1", "water1", "rodent1", "farm1", "cold1", "heat1", "air2", "water2", "stowaway", "drug1",
	"insect1", "rash", "hardy", "cold2", "heat2", "drug2", "rodent2", "farm2", "insect2",
}
local LETHAL = {
	"nausea", "vomit", "anaemia", "bleeding", "sneeze", "insomnia", "fever", "pneumonia",
	"immune", "organs", "paranoia", "seizures", "paralysis", "coma",
}
local SHIELDS = { "shield1", "shield2", "shield3" }

function PlagueBot.new(sim: any, strategy: string?, zero_after: number?): any
	local self = setmetatable({}, PlagueBot)
	self.sim = sim
	self.strategy = strategy or "balanced"
	self.zero_after = zero_after or 0
	--- chance per check that a visible bubble gets popped (a person misses some)
	self.pop_p = 0.5
	return self
end

function PlagueBot.tick(self: any)
	local s = self.sim
	if s.phase == Defs.PHASE_SPAWN then
		if s.tick >= self.zero_after then
			self:_pick_zero()
		end
		return
	end
	if s.phase ~= Defs.PHASE_PLAYING then
		return
	end
	if s.tick % 7 == 0 then
		for _, b in s.bubbles do
			if s.tick - (b.expire - 140) >= 15 and s.rng:randf() < self.pop_p then
				s:submit(s.pid, { type = "pop", id = b.id })
			end
		end
	end
	if s.tick % 10 == 0 then
		self:_buy()
	end
	if s.tick % 15 == 5 then
		self:_click()
	end
	if s.pathogen.ability == "spores" and s.tick % 50 == 0 and s.dna >= 30 and s.tick >= s.ability_ready then
		s:submit(s.pid, { type = "ability", key = "spores" })
	end
end

--- Clicks a country to infect it, like a person: the most populous one it can reach, now and then
--- (keeping DNA for evolutions once the next one is close).
function PlagueBot._click(self: any)
	local s = self.sim
	if s.dna < 1 or s.rng:randf() > 0.6 then
		return
	end
	local best, best_pop = 0, -1
	for c = 1, s.C do
		if s.Ic[c] < 1 and s.Hc[c] >= 1 and s.first_tick[c] < 0 then
			local kind, _, cost = s:route(c)
			if kind ~= nil and cost <= s.dna and s.pop[c] > best_pop then
				best, best_pop = c, s.pop[c]
			end
		end
	end
	if best > 0 then
		s:submit(s.pid, { type = "infect", target = best })
	end
end

function PlagueBot._pick_zero(self: any)
	local s = self.sim
	local list = s.cs.list
	-- a populous country, weighted towards the big ones
	local pool = {}
	local total = 0
	for c = 1, s.C do
		if list[c].pop >= 5e6 and list[c].tiles >= 40 then
			local w = math.sqrt(list[c].pop)
			table.insert(pool, { c, w })
			total += w
		end
	end
	local r = s.rng:randf() * total
	for _, e in pool do
		r -= e[2]
		if r <= 0 then
			s:submit(s.pid, { type = "zero", tile = list[e[1]].label })
			return
		end
	end
end

function PlagueBot._plan(self: any): { string }
	local s = self.sim
	local strat = self.strategy
	if strat == "rush" then
		return LETHAL
	end
	local seen = (s.Iw + s.Dw) / s.world_pop
	local plan = {}
	if s.research and s.cure > 0.12 then
		for _, id in SHIELDS do
			table.insert(plan, id)
		end
	end
	-- lethal once nearly every country has it (killing first strands the rest), or the cure is close
	local untouched = 0
	for c = 1, s.C do
		if s.first_tick[c] < 0 then
			untouched += 1
		end
	end
	local go_lethal = strat == "balanced" and (untouched <= 2 and seen > 0.5 or s.cure > 0.45)
	if go_lethal then
		for _, id in LETHAL do
			table.insert(plan, id)
		end
	end
	for _, id in SPREAD do
		table.insert(plan, id)
	end
	if s.pathogen.id == "virus" and strat ~= "random" then
		table.insert(plan, 1, "lock")
	end
	return plan
end

function PlagueBot._buy(self: any)
	local s = self.sim
	-- "none": never evolves (the balance check for a player who ignores the Evolve screen)
	if self.strategy == "none" then
		return
	end
	if self.strategy == "random" then
		local pool = {}
		for _, t in Traits.list do
			local ok = s:can_evolve(t.id)
			if ok then
				table.insert(pool, t.id)
			end
		end
		if #pool > 0 and s.rng:randf() < 0.5 then
			s:submit(s.pid, { type = "evolve", id = pool[s.rng:randi_range(1, #pool)] })
		end
		return
	end
	for _, id in self:_plan() do
		if not s.owned[id] and Traits.reachable(id, s.owned) then
			local ok = s:can_evolve(id)
			if ok then
				s:submit(s.pid, { type = "evolve", id = id })
			end
			return -- save up for the first wanted trait
		end
	end
end

return PlagueBot
