-- RoPlague: the country layer of every map (Data/Maps/<Module>Countries, tools/maps/make_countries.py) and a
-- headless plague match on each continent.
--   .bin/lune.exe run tests/continent_countries.luau [max_days=2500] [seed=7]   (max_days 0: the layers only;
--   the five matches take about 3 minutes)
local process = require("@lune/process")
require("./prelude")
local WorldMap = require("../src/shared/Core/WorldMap")
local Countries = require("../src/shared/Core/Plague/Countries")
local PlagueSim = require("../src/shared/Core/Plague/PlagueSim")
local Defs = require("../src/shared/Core/Defs")

local max_days = tonumber(process.args[1]) or 2500
local seed = tonumber(process.args[2]) or 7

local fails = 0
local function expect(ok: any, what: string)
	if ok then
		print("  ok   " .. what)
	else
		fails += 1
		print("FAIL " .. what)
	end
end

local MAPS = { "world", "africa", "asia", "europe", "northamerica", "southamerica" }
local CONTINENTS = { "africa", "asia", "europe", "northamerica", "southamerica" }

-- the layer ------------------------------------------------------------------------------------------------------
local layers = {}
for _, id in MAPS do
	local map = WorldMap.get(id)
	local cs = Countries.get(map)
	expect(cs ~= nil, id .. ": has a country layer")
	if cs == nil then
		continue
	end
	layers[id] = { map = map, cs = cs }
	expect(cs.count >= 1 and cs.count <= 254, ("%s: %d countries (1..254)"):format(id, cs.count))
	local empty, off_land, off_country, pop, bad_pop = {}, {}, {}, 0, {}
	for c = 1, cs.count do
		local cc = cs.list[c]
		if cc.tiles < 1 then
			table.insert(empty, cc.name)
		end
		local l = cc.label
		if l < 0 or l >= map.N or buffer.readu8(map.land, l) ~= 1 then
			table.insert(off_land, cc.name)
		elseif buffer.readu8(cs.grid, l) ~= c then
			table.insert(off_country, cc.name)
		end
		if type(cc.pop) ~= "number" or cc.pop ~= cc.pop or cc.pop < 0 then
			table.insert(bad_pop, cc.name)
		else
			pop += cc.pop
		end
	end
	expect(#empty == 0, id .. ": every country has a tile " .. table.concat(empty, ", "))
	expect(#off_land == 0, id .. ": every label is on land " .. table.concat(off_land, ", "))
	expect(#off_country == 0, id .. ": every label is inside its country " .. table.concat(off_country, ", "))
	expect(#bad_pop == 0 and pop > 0, ("%s: total pop %.0fM"):format(id, pop / 1e6))
	-- neighbours: symmetric (the same shared edge count both ways), and each border tile is the country's own
	local asym, bad_border = {}, {}
	for c = 1, cs.count do
		for _, nb in cs.list[c].neighbors do
			local o, n, t = nb[1], nb[2], nb[3]
			local back = false
			if o >= 1 and o <= cs.count then
				for _, nb2 in cs.list[o].neighbors do
					if nb2[1] == c and nb2[2] == n then
						back = true
					end
				end
			end
			if not back then
				table.insert(asym, cs.list[c].name .. " -> " .. tostring(o))
			end
			if t < 0 or t >= map.N or buffer.readu8(cs.grid, t) ~= c then
				table.insert(bad_border, cs.list[c].name .. " / " .. tostring(o))
			end
		end
	end
	expect(#asym == 0, id .. ": neighbours are symmetric " .. table.concat(asym, ", "))
	expect(#bad_border == 0, id .. ": border tiles are on their own side " .. table.concat(bad_border, ", "))
	-- the grid only marks land
	local water_marked = 0
	for i = 0, map.N - 1 do
		if buffer.readu8(cs.grid, i) ~= 0 and buffer.readu8(map.land, i) ~= 1 then
			water_marked += 1
		end
	end
	expect(water_marked == 0, id .. ": no country tile on water")
	-- a map id with a size suffix finds the same module ("europe@100" is europe at full size)
	local proxy = setmetatable({ id = id .. "@100", _countries = nil }, { __index = map })
	local cs2 = Countries.get(proxy)
	expect(cs2 ~= nil and cs2.count == cs.count, id .. "@100: the same country layer")
end

-- a headless match per continent ----------------------------------------------------------------------------------
local REASON = { [Defs.OVER_EXTINCT] = "WIN", [Defs.OVER_CURED] = "cured", [Defs.OVER_BURNOUT] = "burnout" }
local results = {}
for _, id in CONTINENTS do
	local L = layers[id]
	if L == nil or max_days <= 0 then
		continue
	end
	local ok, res = pcall(function()
		local sim = PlagueSim.new(L.map, { seed = seed, auto = true, strategy = "balanced", difficulty = 1 })
		local dt = PlagueSim.DAY_TICKS
		local zero_tick = -1
		local t0 = os.clock()
		for _ = 1, max_days * dt do
			sim:step()
			if zero_tick < 0 and sim.phase == Defs.PHASE_PLAYING then
				zero_tick = sim.tick
			end
			if sim.phase == Defs.PHASE_OVER then
				break
			end
		end
		local infected = 0
		for c = 1, sim.C do
			if sim.first_tick[c] >= 0 then
				infected += 1
			end
		end
		return {
			result = if sim.phase == Defs.PHASE_OVER then (REASON[sim.over_reason] or tostring(sim.over_reason)) else "timeout",
			days = if zero_tick >= 0 then (sim.tick - zero_tick) // dt else 0,
			infected = infected,
			C = sim.C,
			dead = sim.Dw / sim.world_pop,
			cure = sim.cure,
			ms = (os.clock() - t0) * 1000 / math.max(sim.tick, 1),
			start = if sim.start_c > 0 then sim.cs.list[sim.start_c].name else "-",
		}
	end)
	expect(ok, id .. ": a headless match runs" .. (if ok then "" else ": " .. tostring(res)))
	if ok then
		results[id] = res
		expect(res.result ~= "timeout", ("%s: the match ends (%s)"):format(id, res.result))
	end
end

print(("\nheadless PlagueSim, balanced bot, difficulty 1, seed %d, up to %d days"):format(seed, max_days))
print(("%-13s %-8s %5s %9s %6s %6s %8s  %s"):format("map", "result", "days", "infected", "dead", "cure", "ms/tick", "patient zero"))
for _, id in CONTINENTS do
	local r = results[id]
	if r ~= nil then
		print(("%-13s %-8s %5d %4d/%-4d %5.0f%% %5.0f%% %8.2f  %s"):format(id, r.result, r.days, r.infected, r.C, r.dead * 100, r.cure * 100, r.ms, r.start))
	end
end

if fails > 0 then
	error(("continent_countries: %d failures"):format(fails))
end
print("continent_countries: all passed")
