-- RoPlague multiplayer matchmaking (server/PlagueMatch, Data/PlagueModes): the rotation, forming matches
-- out of the line, the rooms.   .bin/lune.exe run tests/plague_match.luau
require("./prelude")
local PlagueMatch = require("../src/server/PlagueMatch")
local Modes = require("../src/shared/Data/PlagueModes")

local fails = 0
local function expect(ok: any, what: string)
	if ok then
		print("  ok   " .. what)
	else
		fails += 1
		print("FAIL " .. what)
	end
end

local function e(key: string, mode: string, n: number, since: number, role: string?, variant: string?): any
	local uids, names = {}, {}
	for i = 1, n do
		table.insert(uids, key .. i)
		table.insert(names, "P" .. key .. i)
	end
	return { key = key, mode = mode, variant = variant, uids = uids, names = names, since = since, role = role }
end

-- the rotation
do
	expect(Modes.ORDER[1] == "duel" and Modes.ORDER[2] == "race" and Modes.ORDER[3] == "teams", "cards: 1v1, Plague Race, teams")
	local seen_maps, seen_formats = {}, {}
	for slot = 0, 23 do
		local now = slot * Modes.ROTATE_S + 7
		local d = Modes.variant("duel", now) :: any
		local r = Modes.variant("race", now) :: any
		local t = Modes.variant("teams", now) :: any
		if d.map ~= "world" then
			expect(false, "1v1 is always the World")
		end
		seen_maps[t.map] = true
		seen_formats[t.format_label] = true
		expect(r.map == "world" and r.format == nil, "") -- (quiet unless it fails)
		local m, map, fmt = Modes.parse(t.id)
		if not (m == "teams" and map == t.map and fmt == t.format) then
			expect(false, "a variant id parses back: " .. t.id)
		end
		if t.max ~= (Modes.format(t.format) :: any).max then
			expect(false, "a team game's max is its format's")
		end
	end
	local n = 0
	for _ in seen_maps do
		n += 1
	end
	expect(n == #Modes.MAPS, "teams: every map comes round; 1v1 stays on the World")
	expect(seen_formats.Duos and seen_formats.Trios and seen_formats.Quads and seen_formats["4 Teams"], "teams: every format comes round")
	local v = Modes.variant("duel", 1000) :: any
	expect(v.rotate_in > 0 and v.rotate_in <= Modes.ROTATE_S, "a variant says when it rotates")
	expect(Modes.team_count("duos", 6) == 3 and Modes.team_count("quads", 3) == 2 and Modes.team_count("teams4", 3) == 3, "team counts")
end

-- 1v1: strictly opposite sides
do
	local m = PlagueMatch.form({ e("a", "duel", 1, 0, "cure"), e("b", "duel", 1, 1, "plague") }, 5)
	expect(#m == 1 and #m[1].groups == 2, "a cure and a plague make a match")
	expect(m[1].roles.a1 == "cure" and m[1].roles.b1 == "plague", "each plays the side they picked")
	local same = PlagueMatch.form({ e("a", "duel", 1, 0, "plague"), e("b", "duel", 1, 1, "plague") }, 5)
	expect(#same == 0, "two plagues never meet")
	local three = PlagueMatch.form(
		{ e("a", "duel", 1, 0, "plague"), e("b", "duel", 1, 1, "plague"), e("c", "duel", 1, 2, "cure") },
		5
	)
	expect(#three == 1 and three[1].roles.a1 == "plague" and three[1].roles.c1 == "cure", "the oldest plague meets the cure")
	local m2 = PlagueMatch.form({ e("a", "duel", 1, 0, "plague") }, 100)
	expect(#m2 == 0, "a lone 1v1 player waits")
	local m4 = PlagueMatch.form({ e("a", "duel", 1, 0, "cure") }, 100, true)
	expect(#m4 == 1 and m4[1].roles.a1 == "cure", "Studio: a lone player plays the side they picked")
	local party = PlagueMatch.form({ e("p", "duel", 2, 0, "cure") }, 1)
	expect(#party == 1 and party[1].roles.p1 == "cure" and party[1].roles.p2 == "plague", "a party of two plays each other")
	local mixed = PlagueMatch.form(
		{ e("a", "duel", 1, 0, "plague", "duel:asia"), e("b", "duel", 1, 0, "cure", "duel:europe") },
		5
	)
	expect(#mixed == 0, "players on different rotations don't meet")
end

-- Plague Race / teams: fill up to max, go when full or after fill_s with min
do
	local now = 100
	local early = PlagueMatch.form({ e("a", "race", 1, now - 2), e("b", "race", 1, now - 1) }, now)
	expect(#early == 0, "race: two players wait a moment for more")
	local late = PlagueMatch.form({ e("a", "race", 1, now - 20), e("b", "race", 1, now - 1) }, now)
	expect(#late == 1 and #late[1].groups == 2, "race: after fill_s, two is enough")
	expect(late[1].roles.a1 ~= late[1].roles.b1 and late[1].map == "world", "race: one plague each, on the World")
	local alone = PlagueMatch.form({ e("a", "race", 1, now - 60) }, now)
	expect(#alone == 0, "race: one player never races alone")
	local full = {}
	for i = 1, 6 do
		table.insert(full, e("r" .. i, "race", 1, now))
	end
	expect(#PlagueMatch.form(full, now) == 1, "race: six go at once")
	local tv = "teams:asia:duos"
	local t = PlagueMatch.form({ e("a", "teams", 2, now - 30, nil, tv), e("b", "teams", 1, now - 30, nil, tv), e("c", "teams", 1, now - 30, nil, tv) }, now)
	expect(#t == 1 and t[1].map == "asia" and t[1].format == "duos", "teams: the variant's map and format")
	local r = t[1].roles
	expect(r.a1 == r.a2 and r.b1 == r.c1 and r.a1 ~= r.b1, "teams: a party is one team, the rest fill the other")
	local q = PlagueMatch.plague_roles("teams", "teams4", {
		e("a", "teams", 1, 1),
		e("b", "teams", 1, 2),
		e("c", "teams", 1, 3),
		e("d", "teams", 1, 4),
		e("f", "teams", 1, 5),
	})
	local per = {}
	for _, k in q do
		per[k] = (per[k] or 0) + 1
	end
	expect(#per == 4, "4 Teams: four teams")
end

-- rooms
do
	local m = PlagueMatch.form({ e("a", "duel", 1, 0, "plague", "teams:europe:duos"), e("b", "duel", 1, 1, "cure", "teams:europe:duos") }, 5)[1]
	local room = PlagueMatch.room_of(m, "id1", 42)
	expect(#room.expect == 2 and room.names.a1 == "Pa1" and room.roles.b1 == "cure", "a room carries players, names and sides")
	expect(room.map == "europe", "a room carries its map")
	local clean = PlagueMatch.clean_room(room)
	expect(clean ~= nil and clean.mode == "duel" and clean.seed > 0 and clean.map == "europe", "a room survives the teleport data check")
	expect(PlagueMatch.clean_room({ mode = "war", expect = { "1" } }) == nil, "an unknown mode is no room")
	expect(PlagueMatch.clean_room({ mode = "race", expect = {} }) == nil, "a room with nobody is no room")
	local bad = PlagueMatch.clean_room({ mode = "race", map = "mars", expect = { "1" }, roles = { ["1"] = 99 } })
	expect(bad ~= nil and bad.map == "world" and bad.roles["1"] == nil, "a made-up map or role is cleaned")
	local rr = PlagueMatch.room_of(PlagueMatch.form({ e("a", "race", 1, 0), e("b", "race", 1, 0) }, 30)[1], "r", 1)
	local specs = PlagueMatch.plague_specs(rr)
	expect(specs ~= nil and #specs == 2 and specs[rr.roles.a1].name == "Pa1's Plague", "race: a plague per player, named after them")
	local now = 0
	local here = {}
	local hooks = PlagueMatch.room_hooks(room, {
		now = function()
			return now
		end,
		present = function()
			return here
		end,
		to_lobby = function() end,
	})
	expect((hooks.countdown() or 0) > 0, "a room waits for its players")
	here = { a1 = true, b1 = true }
	expect(hooks.countdown() == 0, "... and starts once they're all in")
	here = { a1 = true }
	now = PlagueMatch.ARRIVE_S + 1
	expect(hooks.countdown() == 0, "... or after ARRIVE_S")
	expect(hooks.info().plague.mode == "duel" and hooks.on_start(1) == 0, "no bots in a plague room")
	expect(hooks.info().map_id == "europe", "the match plays the room's map")
end

-- the line, end to end on one server
do
	local t = 0
	local states, started = {}, {}
	local mm = PlagueMatch.new({
		store = PlagueMatch.local_store(),
		job = "j1",
		now = function()
			return t
		end,
		studio = false,
		reserve = function()
			return "code1"
		end,
		teleport = function(players, code, room)
			table.insert(started, { players = players, code = code, room = room })
			return true
		end,
		start_local = function() end,
		state = function(players, st, mode, extra)
			for _, p in players do
				states[p.UserId] = { st, mode, extra }
			end
		end,
		new_id = function()
			return "m1"
		end,
		seed = function()
			return 7
		end,
	})
	local p1 = { UserId = 1, Name = "One", DisplayName = "One", Parent = true }
	local p2 = { UserId = 2, Name = "Two", DisplayName = "", Parent = true }
	local p3 = { UserId = 3, Name = "Three", DisplayName = "", Parent = true }
	expect(mm:join("u:1", { p1 }, "duel", "cure") == true and states[1][1] == "line", "join puts a player in line")
	expect(states[1][3] ~= nil and states[1][3].map ~= nil, "... and says the map")
	local ok3, why = mm:join("p:x", { p1, p2, p3 }, "duel", "plague")
	expect(ok3 == false and why == PlagueMatch.TOO_MANY, "a party of three is too many for 1v1")
	mm:join("u:2", { p2 }, "duel", "plague")
	mm:tick()
	expect(#started == 2 and started[1].code == "code1" and started[2].code == "code1", "two 1v1 players are teleported to one reserved server")
	local room = if #started > 0 then started[1].room else nil
	expect(room ~= nil and room.roles["1"] == "cure" and room.roles["2"] == "plague", "... with their sides")
	expect(states[1][1] == "going" and states[2][1] == "going", "... and told they're going")
	expect(mm:queued("u:1") == nil, "... and out of the line")
	-- a party of two in 1v1: they play each other
	started = {}
	mm:join("p:y", { p1, p2 }, "duel", "plague")
	mm:tick()
	local pr = if #started > 0 then started[1].room else nil
	expect(pr ~= nil and pr.roles["1"] == "plague" and pr.roles["2"] == "cure", "a party of two plays each other")
	-- the rotation moves while waiting: the group follows it
	mm:join("u:3", { p3 }, "teams")
	local v0 = mm:queued("u:3").entry.variant
	t += Modes.ROTATE_S
	mm:tick()
	local w = mm:queued("u:3")
	expect(w ~= nil and w.entry.variant ~= v0, "a waiting group follows the rotation")
	expect(mm:cancel("u:3") and states[3][1] == "idle", "cancel leaves the line")
	local view = mm:view()
	expect(#view == 3 and view[1].mode == "duel" and view[1].map_name ~= nil and view[3].format ~= nil, "the cards: one row per mode, with the map")
end

if fails > 0 then
	error(("plague_match: %d failures"):format(fails))
end
print("plague_match: all passed")
