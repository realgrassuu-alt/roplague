-- RoPlague multiplayer (2026-10-30): the server-run plague (Co-op, 1v1) and its wire intents.
--   .bin/lune.exe run tests/plague_mp.luau
require("./prelude")
local WorldMap = require("../src/shared/Core/WorldMap")
local PlagueSim = require("../src/shared/Core/Plague/PlagueSim")
local R = require("../src/shared/Core/Plague/PlagueRules")
local Defs = require("../src/shared/Core/Defs")
local Protocol = require("../src/shared/Net/Protocol")

local fails = 0
local function expect(ok: any, what: string)
	if ok then
		print("  ok   " .. what)
	else
		fails += 1
		print("FAIL " .. what)
	end
end

local map = WorldMap.get("world")
local function country(sim: any, name: string): number
	for c = 1, sim.C do
		if sim.cs.list[c].name == name then
			return c
		end
	end
	return 0
end
local function run(sim: any, ticks: number)
	for _ = 1, ticks do
		sim:step()
	end
end

-- Co-op: everyone plays the one plague
do
	local sim = PlagueSim.new(map, { seed = 7, mode = "coop" })
	local a = sim:add_human("1", "Ann")
	local b = sim:add_human("2", "Bob")
	expect(a == sim.pid and b == sim.pid, "co-op: every player plays the plague")
	local india = country(sim, "India")
	sim:submit(b, { type = "zero", tile = sim.cs.list[india].label })
	run(sim, 1)
	expect(sim.phase == Defs.PHASE_PLAYING and sim.start_c == india, "co-op: any player picks patient zero")
	sim.dna = 100
	sim:submit(a, { type = "evolve", kind = "water1" })
	run(sim, 1)
	expect(sim.owned.water1 == true, "co-op: an evolution off the wire (kind) is bought")
	sim:remove_human(a)
	run(sim, 5)
	expect(sim.phase == Defs.PHASE_PLAYING, "co-op: a player leaving doesn't end it")
end

-- Nobody picks patient zero: the match starts by itself
do
	local sim = PlagueSim.new(map, { seed = 3, mode = "coop" })
	sim:add_human("1", "Ann")
	run(sim, R.MP_ZERO_TICKS + 2)
	expect(sim.phase == Defs.PHASE_PLAYING and sim.start_c > 0, "an idle spawn phase picks patient zero")
	local solo = PlagueSim.new(map, { seed = 3 })
	solo:add_human("1", "Ann")
	run(solo, R.MP_ZERO_TICKS + 2)
	expect(solo.phase == Defs.PHASE_SPAWN, "solo still waits for its player")
end

-- 1v1: the plague and the cure
do
	local sim = PlagueSim.new(map, { seed = 11, mode = "duel", roles = { ["10"] = "plague", ["20"] = "cure" } })
	local plague = sim:add_human("10", "Pat")
	local cure = sim:add_human("20", "Cora")
	expect(plague == sim.pid and cure == sim.cure_pid and cure ~= plague, "1v1: two sides, two owners")
	local snap = sim:snapshot()
	local found = false
	for _, o in snap.owners do
		if o[1] == cure then
			found = true
		end
	end
	expect(found, "1v1: the cure is an owner in the snapshot")
	-- the cure can't play the plague
	local india = country(sim, "India")
	sim:submit(cure, { type = "zero", tile = sim.cs.list[india].label })
	run(sim, 1)
	expect(sim.phase == Defs.PHASE_SPAWN, "1v1: the cure can't pick patient zero")
	sim:submit(plague, { type = "zero", tile = sim.cs.list[india].label })
	run(sim, 1)
	expect(sim.phase == Defs.PHASE_PLAYING, "1v1: the plague picks it")
	-- alert before research, then close a country
	local funds = sim.cure_funds
	sim:submit(cure, { type = "cure", kind = "alert" })
	run(sim, 1)
	expect(sim.aware >= R.DUEL_ALERT_AWARE - 1e-6 and sim.cure_funds <= funds - R.DUEL_COSTS.alert + 1, "1v1: ALERT raises awareness, costs funds")
	sim.cure_funds = 50
	local china = country(sim, "China")
	sim:submit(cure, { type = "cure", kind = "build_post", target = china })
	run(sim, 1)
	expect(bit32.band(sim.closed[china], 4) == 0 and sim.cure_funds == 50, "1v1: buildings wait for research")
	sim.research = true
	local Ev = require("../src/shared/Core/Ev")
	sim:submit(cure, { type = "cure", kind = "build_post", target = china })
	local d = sim:step()
	local added = nil
	for _, e in d.ev do
		if e[1] == Ev.STRUCT_ADD then
			added = e
		end
	end
	expect(bit32.band(sim.closed[china], 4) ~= 0, "1v1: a Border Post shuts its land borders")
	expect(added ~= nil and added[4] == sim.cure_pid and added[3] == R.BUILDINGS.post.struct, "1v1: it is a RoWorld structure of the cure's")
	expect(sim.cure_funds == 50 - R.BUILDINGS.post.cost, "1v1: and costs funds")
	local before = sim.cure_funds
	sim:submit(cure, { type = "cure", kind = "build_post", target = china })
	run(sim, 1)
	expect(sim.cure_funds == before, "1v1: a second one in the same country is refused")
	sim:submit(cure, { type = "cure", kind = "build_control", target = china })
	sim:submit(cure, { type = "cure", kind = "build_lab", target = china })
	sim:submit(cure, { type = "cure", kind = "build_camp", target = china })
	sim:submit(cure, { type = "cure", kind = "build_hospital", target = china })
	run(sim, 1)
	expect(bit32.band(sim.closed[china], 4 + 2 + 1 + 8) == 15, "1v1: control shuts ports and airports, the camp quarantines")
	expect(sim.funding[china] >= 1 and sim.buildings[china].lab ~= nil and sim.buildings[china].hospital ~= nil, "1v1: a lab funds research, a hospital stands")
	local snap = sim:snapshot()
	local n = 0
	for _, row in snap.structs do
		if row[3] == sim.cure_pid then
			n += 1
		end
	end
	expect(n == 5, "1v1: the snapshot has the cure's five buildings")
	-- the plague can't act for the cure
	local q = sim.closed[country(sim, "Brazil")]
	sim:submit(plague, { type = "cure", kind = "close", target = country(sim, "Brazil") })
	run(sim, 1)
	expect(sim.closed[country(sim, "Brazil")] == q, "1v1: the plague can't use the cure's actions")
	-- funds come in over time
	local f0 = sim.cure_funds
	run(sim, 200)
	expect(sim.cure_funds > f0, "1v1: the cure earns funds")
	-- a cure bubble popped by the cure speeds the cure
	sim:_add_bubble(PlagueSim.B_CURE, china, sim.cs.list[china].label, 2)
	local id = sim.bubbles[#sim.bubbles].id
	local c0 = sim.cure
	sim:submit(cure, { type = "pop", uid = id })
	run(sim, 1)
	expect(sim.cure > c0, "1v1: the cure's player pops a cure bubble: the cure speeds up")
	-- the cure's win
	sim.cure = 0.9999
	run(sim, 20)
	expect(sim.phase == Defs.PHASE_OVER and sim.winner == cure, "1v1: a finished cure is the cure player's win")
end

-- Plague intents survive the wire
do
	local checks = {
		{ type = "zero", tile = 1234 },
		{ type = "evolve", id = "air1" },
		{ type = "devolve", id = "air1" },
		{ type = "pop", id = 17 },
		{ type = "ability", key = "spores" },
		{ type = "infect", target = 33 },
		{ type = "cure", kind = "close", target = 33 },
	}
	for _, it in checks do
		local b = Protocol.encode_intent(it)
		local back = if b ~= nil then Protocol.decode_intent(b) else nil
		local ok = back ~= nil and back.type == it.type
		if ok and it.id ~= nil then
			ok = (back.kind == it.id) or (back.uid == it.id)
		end
		if ok and it.key ~= nil then
			ok = back.kind == it.key
		end
		if ok and it.target ~= nil then
			ok = back.target == it.target
		end
		if ok and it.tile ~= nil then
			ok = back.tile == it.tile
		end
		expect(ok, "wire: " .. it.type)
	end
end


-- A shared world (Plague Race, team games): several plagues, countries taken by attacks
local Ev = require("../src/shared/Core/Ev")
local function race(seed: number, n: number?)
	local specs = {}
	for k = 1, n or 2 do
		specs[k] = { name = "P" .. k }
	end
	local roles = {}
	for k = 1, n or 2 do
		roles[tostring(k * 10)] = k
	end
	return PlagueSim.new(map, { seed = seed, mode = "race", plagues = specs, roles = roles })
end
local function has_ev(evs: any, id: number): any
	for _, e in evs do
		if e[1] == id then
			return e
		end
	end
	return nil
end
do
	local sim = race(5)
	local a = sim:add_human("10", "Ann")
	local b = sim:add_human("20", "Bob")
	expect(sim.multi and sim.K == 2, "race: two plagues")
	expect(a == sim.C + 1 and b == sim.C + 2, "race: each player their own plague")
	expect(sim:owner_count() >= sim.C + 2, "race: every plague is an owner")
	local france, india, spain = country(sim, "France"), country(sim, "India"), country(sim, "Spain")
	sim:submit(a, { type = "zero", tile = sim.cs.list[france].label })
	run(sim, 1)
	expect(sim.phase == Defs.PHASE_SPAWN, "race: still waiting for the other plague")
	expect(sim.holder[france] == 1, "race: patient zero holds its country")
	sim:submit(b, { type = "zero", tile = sim.cs.list[france].label })
	run(sim, 1)
	expect(sim.phase == Defs.PHASE_SPAWN and sim:_pget(2, "start_c") == 0, "race: can't start in a country another took")
	sim:submit(b, { type = "zero", tile = sim.cs.list[india].label })
	run(sim, 1)
	expect(sim.phase == Defs.PHASE_PLAYING, "race: everyone placed, it starts")
	expect(sim.holder[india] == 2, "race: the second plague holds its own start")

	-- run a while: every sick country has one holder, nobody spreads into an enemy's
	local switched = false
	local last = table.clone(sim.holder)
	for _ = 1, 400 do
		local d = sim:step()
		local caps = {}
		for _, e in d.ev do
			if e[1] == Ev.P_CAPTURE then
				caps[e[2]] = true
			end
		end
		for c = 1, sim.C do
			local h = sim.holder[c]
			if last[c] ~= 0 and h ~= 0 and h ~= last[c] and not caps[c] then
				switched = true
			end
		end
		last = table.clone(sim.holder)
	end
	expect(not switched, "race: a country only changes hands by an attack")
	local ok = true
	for c = 1, sim.C do
		if sim.Ic[c] >= 1 and sim.holder[c] == 0 then
			ok = false
		end
	end
	expect(ok, "race: every sick country is held")
	local held = { 0, 0 }
	for c = 1, sim.C do
		local h = sim.holder[c]
		if h > 0 then
			held[h] += 1
		end
	end
	expect(held[1] > 1 and held[2] > 1, ("race: both plagues spread (%d, %d countries)"):format(held[1], held[2]))
	local pl = sim:_pl_rows(true)
	expect(pl.plagues ~= nil and #pl.plagues == 2 and pl.plagues[2].pid == b, "race: the rows carry every plague")
	local row7 = false
	for _, r in pl.c do
		if r[1] == france and r[7] == a then
			row7 = true
		end
	end
	expect(row7, "race: a country row names its holder")

	-- an attack, RoWorld's way: Spain held by the second plague, France (bordering) by the first
	sim.holder[spain] = 2
	sim.Ic[spain] = 200000
	sim.Hc[spain] = math.max(sim.Hc[spain], 1000000)
	sim.Ic[france] = math.max(sim.Ic[france], 2000000)
	sim.holder[france] = 1
	sim.shield[spain] = 0
	for _, f in sim.flights do
		if f.target == spain then
			f.arrive = sim.tick + 99999
			f.target = 0
		end
	end
	sim:_use(1)
	local kind, src, cost = sim:route(spain)
	expect(kind == "land" and cost == R.INFECT_LAND_DNA + R.ATTACK_DNA, "attack: an enemy country costs more")
	sim:_pset(1, "dna", 100)
	local src_before = sim.Ic[src]
	sim:submit(a, { type = "infect", target = spain })
	local d0 = sim:step()
	local started = has_ev(d0.ev, Ev.ATTACK)
	expect(started ~= nil and started[3] == a and started[4] == b and started[8] == spain, "attack: across a border it starts at once (Ev.ATTACK)")
	expect(started ~= nil and started[5] >= math.floor(src_before * R.ATTACK_SHARE) - 1, "attack: it carries half the bordering country's infected")
	local flew = false
	for _, f in sim.flights do
		if f.target == spain then
			flew = true
		end
	end
	expect(not flew, "attack: no traveller walks there")
	expect(sim.Ic[src] < src_before, "attack: the attackers leave their country")
	local captured, ended = false, false
	local fought = 0
	for _ = 1, 200 do
		fought += 1
		local d = sim:step()
		local e = has_ev(d.ev, Ev.P_CAPTURE)
		if e ~= nil and e[2] == spain then
			captured = e[3] == a and e[4] == b
		end
		if has_ev(d.ev, Ev.ATTACK_END) then
			ended = true
		end
		if captured then
			break
		end
	end
	expect(captured and sim.holder[spain] == 1, "attack: a big attack on a few defenders takes the country")
	expect(fought > 2, ("attack: it is a fight over several ticks (%d)"):format(fought))
	expect(ended and #sim.attacks == 0, "attack: and ends")
	expect(sim.Ic[spain] >= 1, "attack: the attackers move in")
	expect(sim:_pget(1, "dna") <= 100 - cost + 30, "attack: it was paid for")
	sim:_use(2)
	local k2, _, _, why = sim:route(spain)
	expect(k2 == nil and why ~= nil and why:find("taken") ~= nil, "attack: a country just taken is shielded")
	sim:_use(1)
	local k3 = sim:route(spain)
	expect(k3 == nil, "attack: you can't attack your own country")
	-- a small attack on a big defence is beaten back
	sim.shield[spain] = 0
	sim.Ic[spain] = math.max(sim.Ic[spain], 3000000)
	sim.Hc[spain] = math.max(sim.Hc[spain], 1000000)
	local portugal = country(sim, "Portugal")
	sim.holder[portugal] = 2
	sim.Ic[portugal] = 20000
	sim.Hc[portugal] = math.max(sim.Hc[portugal], 50000)
	sim:_use(2)
	sim.beta_c[portugal] = sim:_beta_of(portugal)
	sim:_pset(2, "dna", 100)
	local before = sim:_pget(2, "dna")
	sim:submit(b, { type = "infect", target = spain })
	local failed = false
	for _ = 1, 200 do
		local d = sim:step()
		for _, e in d.ev do
			if e[1] == Ev.MSG and e[2] == b and tostring(e[4]):find("beaten back") then
				failed = true
			end
		end
		if failed then
			break
		end
	end
	expect(failed and sim.holder[spain] == 1, "attack: a small attack is beaten back, the defender keeps it")
	expect(sim:_pget(2, "dna") < before, "attack: a lost attack still costs DNA")
	-- retreat: the troops go home
	sim.shield[portugal] = 0
	sim:_use(1)
	sim:_pset(1, "dna", 100)
	sim.Ic[spain] = 2000000
	sim.Ic[portugal] = 5000000
	sim:submit(a, { type = "infect", target = portugal })
	sim:step()
	local aid = if #sim.attacks > 0 then sim.attacks[1].aid else -1
	local home_before = sim.Ic[spain]
	sim:submit(a, { type = "retreat", attack_id = aid })
	local d1 = sim:step()
	expect(aid > 0 and has_ev(d1.ev, Ev.ATTACK_END) ~= nil and #sim.attacks == 0, "retreat: the attack is called off")
	expect(sim.Ic[spain] > home_before, "retreat: its troops are back home")
	local snap = sim:snapshot()
	expect(type(snap.attacks) == "table", "the snapshot carries the attacks")

	-- bubbles: a DNA bubble is its plague's; the cure's anyone's
	local bub
	for _, x in sim.bubbles do
		if x.owner == a then
			bub = x
		end
	end
	if bub == nil then
		sim:_use(1)
		sim:_add_bubble(PlagueSim.B_DNA, france, sim.cs.list[france].label, 3)
		bub = sim.bubbles[#sim.bubbles]
	end
	expect(bub.owner == a, "bubbles: a DNA bubble names its plague")
	sim:submit(b, { type = "pop", uid = bub.id })
	run(sim, 1)
	local still = false
	for _, x in sim.bubbles do
		if x.id == bub.id then
			still = true
		end
	end
	expect(still, "bubbles: another plague can't pop it")
	sim:submit(a, { type = "pop", uid = bub.id })
	run(sim, 1)
	still = false
	for _, x in sim.bubbles do
		if x.id == bub.id then
			still = true
		end
	end
	expect(not still, "bubbles: its own plague pops it")

	-- the last plague standing
	for c = 1, sim.C do
		if sim.holder[c] == 2 then
			sim.Hc[c] += sim.Ic[c]
			sim.Ic[c] = 0
			sim.holder[c] = 0
		end
	end
	sim.flights, sim.ships = {}, {}
	run(sim, 11)
	expect(sim:_pget(2, "out") == true, "over: a plague with nobody sick is out")
	expect(sim.phase == Defs.PHASE_OVER and sim.over_reason == Defs.OVER_LAST and sim.winner == a, "over: the last plague standing wins")
end

-- Nobody picks: each plague is placed by itself, never in the same country
do
	local sim = race(9, 3)
	sim:add_human("10", "Ann")
	run(sim, R.MP_ZERO_TICKS + 2)
	local s1, s2, s3 = sim:_pget(1, "start_c"), sim:_pget(2, "start_c"), sim:_pget(3, "start_c")
	expect(sim.phase == Defs.PHASE_PLAYING and s1 > 0 and s2 > 0 and s3 > 0, "race: an idle spawn places every plague")
	expect(s1 ~= s2 and s2 ~= s3 and s1 ~= s3, "race: in different countries")
	run(sim, 300)
	expect(sim.phase == Defs.PHASE_PLAYING or sim.phase == Defs.PHASE_OVER, "race: three plagues run")
	local evs_ok = true
	local d = sim:step()
	for _, e in d.ev do
		if e[1] == Ev.P_DNA and e[5] == nil then
			evs_ok = false
		end
	end
	expect(evs_ok, "race: DNA events carry their plague")
end

if fails > 0 then
	error(("plague_mp: %d failures"):format(fails))
end
print("plague_mp: all passed")
