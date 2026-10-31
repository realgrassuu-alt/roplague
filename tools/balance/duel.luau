-- RoPlague 1v1 balance: the scripted plague bot against a scripted cure player who spends every fund
-- as soon as it can (a strong human) and pops every cure bubble. Reports how games end.
--   .bin/lune.exe run tools/balance/duel.luau [seeds=8] [cure=greedy|idle] [strategy=balanced] [max_days=1500]
local process = require("@lune/process")
require("../../tests/prelude")
local WorldMap = require("../../src/shared/Core/WorldMap")
local PlagueSim = require("../../src/shared/Core/Plague/PlagueSim")
local R = require("../../src/shared/Core/Plague/PlagueRules")
local Defs = require("../../src/shared/Core/Defs")

local args = process.args
local seeds = tonumber(args[1]) or 8
local cure_mode = args[2] or "greedy"
local strategy = args[3] or "balanced"
local max_days = tonumber(args[4]) or 1500

local map = WorldMap.get("world")
local REASON = { [Defs.OVER_EXTINCT] = "PLAGUE", [Defs.OVER_CURED] = "CURE", [Defs.OVER_BURNOUT] = "burnout" }

--- What the cure player does now (one action a tick at most): a list of {kind, country}.
local function cure_move(sim: any): { any }?
	local cost = R.DUEL_COSTS
	local funds = sim.cure_funds
	if not sim.research then
		if cost.alert ~= nil and funds >= cost.alert then
			return { "alert", 0 }
		end
		return nil
	end
	local list = sim.cs.list
	local function has(c: number, k: string): boolean
		local b = sim.buildings[c]
		return b ~= nil and b[k] ~= nil
	end
	-- the richest, biggest country without the building; the most infected without it
	local function richest(k: string): number
		local best, best_w = 0, -1
		for c = 1, sim.C do
			local w = list[c].wealth ^ 1.5 * math.sqrt(list[c].pop)
			if not has(c, k) and sim.Hc[c] > 0 and w > best_w then
				best, best_w = c, w
			end
		end
		return best
	end
	local function sickest(k: string): number
		local best, best_i = 0, 0
		for c = 1, sim.C do
			if not has(c, k) and sim.Ic[c] > best_i then
				best, best_i = c, sim.Ic[c]
			end
		end
		return best
	end
	for _, k in R.BUILD_ORDER do
		local b = R.BUILDINGS[k]
		if funds >= b.cost then
			local target = if k == "lab" then richest(k) else sickest(k)
			if target > 0 then
				return { "build_" .. k, target }
			end
		end
	end
	return nil
end

local function run(seed: number)
	local sim = PlagueSim.new(map, {
		seed = seed,
		difficulty = 1,
		mode = "duel",
		auto = true,
		strategy = strategy,
		roles = { cure = "cure" },
	})
	sim:add_human("cure", "Cure")
	local dt = PlagueSim.DAY_TICKS
	local acts = 0
	for _ = 1, max_days * dt do
		if cure_mode == "greedy" and sim.phase == Defs.PHASE_PLAYING then
			local m = cure_move(sim)
			if m ~= nil then
				sim:submit(sim.cure_pid, { type = "cure", kind = m[1], target = m[2] })
				acts += 1
			end
			for _, b in sim.bubbles do
				if b.kind == PlagueSim.B_CURE then
					sim:submit(sim.cure_pid, { type = "pop", id = b.id })
				end
			end
		end
		sim:step()
		if sim.phase == Defs.PHASE_OVER then
			break
		end
	end
	return REASON[sim.over_reason] or "timeout", math.floor(sim.tick / dt), sim.cure, acts
end

local wins = { PLAGUE = 0, CURE = 0 }
for seed = 1, seeds do
	local why, days, cure, acts = run(seed)
	wins[why] = (wins[why] or 0) + 1
	print(("  seed %2d  %-8s day %4d  cure %3d%%  cure moves %d"):format(seed, why, days, math.floor(cure * 100), acts))
end
print(("duel (%s cure, %s plague): plague %d / cure %d of %d"):format(cure_mode, strategy, wins.PLAGUE, wins.CURE, seeds))
