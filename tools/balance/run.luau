-- RoPlague balance harness: plays the real PlagueSim headless with the scripted bot and reports how
-- games end. Usage (repo root):
--   .bin/lune.exe run tools/balance/run.luau [strategy=balanced] [seeds=8] [difficulty=1] [pathogen=bacterium] [max_days=2500]
-- strategy: balanced | rush | stealth | random | none | all
local process = require("@lune/process")
require("../../tests/prelude")
local WorldMap = require("../../src/shared/Core/WorldMap")
local PlagueSim = require("../../src/shared/Core/Plague/PlagueSim")
local Defs = require("../../src/shared/Core/Defs")
local Ev = require("../../src/shared/Core/Ev")

local args = process.args
local strategy = args[1] or "balanced"
local seeds = tonumber(args[2]) or 8
local difficulty = tonumber(args[3]) or 1
local pathogen = args[4] or "bacterium"
local max_days = tonumber(args[5]) or 2500

local map = WorldMap.get("world")
local REASON = { [Defs.OVER_EXTINCT] = "WIN", [Defs.OVER_CURED] = "cured", [Defs.OVER_BURNOUT] = "burnout" }

local function run(strat: string, seed: number)
	local sim = PlagueSim.new(map, { seed = seed, difficulty = difficulty, pathogen = pathogen, auto = true, strategy = strat })
	local dt = PlagueSim.DAY_TICKS
	local peak, research_day, countries, dna_total = 0, -1, 0, 0
	local zero_tick = -1
	local half_day, lethal_day = -1, -1
	-- (the end: days the dead reached half, 90% and 99% of the world)
	local dead50, dead90, dead99 = -1, -1, -1
	local t0 = os.clock()
	for _ = 1, max_days * dt do
		local d = sim:step()
		for _, e in d.ev do
			if e[1] == Ev.P_INFECTED then
				countries += 1
			elseif e[1] == Ev.P_DNA then
				dna_total += e[2]
			end
		end
		if zero_tick < 0 and sim.phase == Defs.PHASE_PLAYING then
			zero_tick = sim.tick
		end
		if research_day < 0 and sim.research then
			research_day = (sim.tick - zero_tick) // dt
		end
		peak = math.max(peak, sim.Iw / sim.world_pop)
		if half_day < 0 and (sim.Iw + sim.Dw) / sim.world_pop >= 0.5 then
			half_day = (sim.tick - zero_tick) // dt
		end
		if lethal_day < 0 and sim.leth > 0.005 then
			lethal_day = (sim.tick - zero_tick) // dt
		end
		local ds = sim.Dw / sim.world_pop
		if dead50 < 0 and ds >= 0.5 then
			dead50 = (sim.tick - zero_tick) // dt
		end
		if dead90 < 0 and ds >= 0.9 then
			dead90 = (sim.tick - zero_tick) // dt
		end
		if dead99 < 0 and ds >= 0.99 then
			dead99 = (sim.tick - zero_tick) // dt
		end
		if sim.phase == Defs.PHASE_OVER then
			break
		end
	end
	local days = (sim.tick - zero_tick) // dt
	local owned = 0
	for _, on in sim.owned do
		if on then
			owned += 1
		end
	end
	return {
		result = REASON[sim.over_reason] or "timeout",
		days = days,
		peak = peak,
		countries = countries,
		never = sim.C - countries,
		cure = sim.cure,
		research = research_day,
		dead = sim.Dw / sim.world_pop,
		traits = owned,
		dna = sim.dna_earned,
		never_names = (function()
			local t = {}
			for c = 1, sim.C do
				if sim.first_tick[c] < 0 then
					table.insert(t, sim.cs.list[c].name)
				end
			end
			return table.concat(t, ", ")
		end)(),
		half_day = half_day,
		lethal_day = lethal_day,
		dead50 = dead50,
		dead90 = dead90,
		dead99 = dead99,
		ms = (os.clock() - t0) * 1000 / math.max(sim.tick, 1),
	}
end

local strats = if strategy == "all" then { "balanced", "rush", "stealth", "random" } else { strategy }
print(("difficulty %d, pathogen %s, %d seeds, up to %d days"):format(difficulty, pathogen, seeds, max_days))
for _, strat in strats do
	local wins, sum_days, rows = 0, 0, {}
	for seed = 1, seeds do
		local r = run(strat, seed * 7919 + 13)
		table.insert(rows, r)
		if r.result == "WIN" then
			wins += 1
		end
		sum_days += r.days
		print(
			("  %-8s seed %2d  %-8s day %4d (%4.1f min @1x)  peak %3.0f%%  dead %3.0f%%  cure %3.0f%%  research day %4d  countries %3d (never %2d)  traits %2d  dna %3d  %.2f ms/tick"):format(
				strat,
				seed,
				r.result,
				r.days,
				r.days / 60,
				r.peak * 100,
				r.dead * 100,
				r.cure * 100,
				r.research,
				r.countries,
				r.never,
				r.traits,
				r.dna,
				r.ms
			)
		)
		print(("      half infected day %d, lethal from day %d, dead 50%% day %d, 90%% day %d, 99%% day %d, never: %s"):format(r.half_day, r.lethal_day, r.dead50, r.dead90, r.dead99, r.never_names))
	end
	print(("%s: %d/%d wins, mean %.0f days (%.1f min @1x)"):format(strat, wins, seeds, sum_days / seeds, sum_days / seeds / 60))
end
