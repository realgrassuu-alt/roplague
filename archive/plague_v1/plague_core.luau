-- RoPlague: the plague sim and its client mirror. Run: .bin/lune.exe run tests/plague_core.luau
require("./prelude")
local WorldMap = require("../src/shared/Core/WorldMap")
local PlagueSim = require("../src/shared/Core/Plague/PlagueSim")
local Countries = require("../src/shared/Core/Plague/Countries")
local GameState = require("../src/shared/Core/GameState")
local Traits = require("../src/shared/Data/Traits")
local Defs = require("../src/shared/Core/Defs")

local fails = 0
local function check(ok: boolean, what: string)
	print((if ok then "  ok   " else "  FAIL ") .. what)
	if not ok then
		fails += 1
	end
end

local map = WorldMap.get("world")
local cs = Countries.get(map)
check(cs ~= nil and cs.count > 150, "World has a country layer (" .. tostring(cs and cs.count) .. " countries)")

-- country layer integrity
local bad_port, bad_air, asym = 0, 0, 0
local nb = {}
for c = 1, cs.count do
	local cc = cs.list[c]
	for _, t in cc.ports do
		if map.coastal == nil or buffer.readu8(map.coastal, t) ~= 1 or buffer.readu8(cs.grid, t) ~= c then
			bad_port += 1
		end
	end
	for _, t in cc.airports do
		if buffer.readu8(map.land, t) ~= 1 or buffer.readu8(cs.grid, t) ~= c then
			bad_air += 1
		end
	end
	for _, n in cc.neighbors do
		nb[c * 256 + n[1]] = true
	end
end
for k in nb do
	local a, b = k // 256, k % 256
	if not nb[b * 256 + a] then
		asym += 1
	end
end
check(bad_port == 0, "every port is a coastal tile of its country (" .. bad_port .. " bad)")
check(bad_air == 0, "every airport is a land tile of its country (" .. bad_air .. " bad)")
check(asym == 0, "neighbours are symmetric (" .. asym .. " one-way)")
local reach = 0
for c = 1, cs.count do
	local cc = cs.list[c]
	if #cc.neighbors > 0 or #cc.ports > 0 or #cc.airports > 0 then
		reach += 1
	end
end
check(reach == cs.count, "every country can be reached by land, sea or air")

-- one country grows, then a lethal trait kills
local sim = PlagueSim.new(map, { seed = 3 })
local pid = sim:add_human("local", "Tester")
local gs = GameState.new(map)
gs:load_snapshot(sim:snapshot())
gs.local_owner = pid
check(gs.plague ~= nil and gs.plague.pid == pid, "the mirror loads the plague")
local china = 1
sim:submit(pid, { type = "zero", tile = cs.list[china].label })
for _ = 1, 300 do
	gs:apply_delta(sim:step())
end
check(sim.phase == Defs.PHASE_PLAYING, "patient zero starts the match")
check(sim.Ic[china] > 20, ("infection grows in patient zero's country (%d infected after 30 days)"):format(sim.Ic[china]))
check(math.abs(gs.plague.I - sim.Iw) < 1, "the mirror follows the world's infected count")
local red = 0
for i = 0, map.N - 1 do
	if bit32.band(buffer.readu8(gs.flags, i), Defs.F_INF) ~= 0 then
		red += 1
	end
end
check(red > 0 and red == sim.inf_n[china] or red >= sim.inf_n[china], "red tiles reach the mirror (" .. red .. ")")
-- determinism
local function hash(s: any): string
	return ("%.6f|%.6f|%.6f|%d|%.6f"):format(s.Hw, s.Iw, s.Dw, s.dna, s.cure)
end
local a = PlagueSim.new(map, { seed = 9, auto = true })
local b = PlagueSim.new(map, { seed = 9, auto = true })
for _ = 1, 2000 do
	a:step()
	b:step()
end
check(hash(a) == hash(b), "same seed, same game after 2000 ticks")
-- buying
sim.dna = 100
sim:submit(pid, { type = "evolve", id = "air1" })
sim:submit(pid, { type = "evolve", id = "air2" })
sim:submit(pid, { type = "evolve", id = "organs" })
gs:apply_delta(sim:step())
check(sim.owned.air1 and sim.owned.air2, "evolve buys a root and then its follower")
check(not sim.owned.organs, "a trait out of reach is refused")
check(gs.plague.owned.air2 == true, "the mirror sees owned traits")
check(sim.dna == 100 - Traits.price("air1", {}) - (Traits.price("air2", { air1 = true })), "the price is charged")
sim:submit(pid, { type = "devolve", id = "air1" })
sim:step()
check(sim.owned.air1 == true, "a trait others depend on cannot be devolved")

print(if fails == 0 then "plague_core ok" else ("plague_core: %d FAILED"):format(fails))
if fails > 0 then
	error("failures")
end
