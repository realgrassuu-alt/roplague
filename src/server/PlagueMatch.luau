--!strict
-- RoPlague's multiplayer (2026-10-30; Data/PlagueModes): matchmaking on the lobby place, the match on
-- the online place (Data/Places).
--
-- On a LOBBY server (PlagueMatch.new): a player (a party leader: the party) presses a mode's card; their
-- group waits in line in MemoryStore (one list for the whole game). Every second one lobby server at a
-- time (a short lock) forms matches out of the line (PlagueMatch.form), reserves a server of the online
-- place for each and leaves its access code where the matched groups' own servers find it; each sends
-- its players there with the room in the teleport data: { rp = room }. In Studio (no teleports) the
-- match plays on this server (deps.start_local), and a lone player is matched by themselves.
--
-- room = { id, mode, map, format, expect = { user ids }, names = { [uid] = name }, roles, seed }:
-- roles = { [uid] = "plague" | "cure" } in a duel, { [uid] = plague number (1..K) } in a Plague Race
-- (one each) or a team game (one per team).
--
-- The line matches by VARIANT (Data/PlagueModes.variant: the mode with this rotation's map and format),
-- and a waiting group follows the rotation as it moves on.
--
-- On the ONLINE place: PlagueMatch.room_hooks(room) are MatchServer's lobby hooks for the match, which
-- runs on the server (Core/Plague/PlagueSim; a race and a team game are one shared world).
local PlagueMatch = {}
PlagueMatch.__index = PlagueMatch

local IS_ROBLOX = typeof(game) == "Instance"
local Modes: any = if IS_ROBLOX
	then require((game :: any):GetService("ReplicatedStorage"):WaitForChild("Airfront").Data.PlagueModes)
	else (require :: any)("../shared/Data/PlagueModes")

--- What a party too big for a mode is told.
PlagueMatch.TOO_MANY = "You have too many party members for this mode."

--- A waiting group's line entry lives this long unless its server refreshes it (REFRESH_S).
PlagueMatch.ENTRY_TTL_S = 30
PlagueMatch.REFRESH_S = 10
--- The matchmaking lock: one lobby server forms matches at a time.
PlagueMatch.LOCK_TTL_S = 4
--- A formed match waits this long for its groups' servers to pick it up.
PlagueMatch.GO_TTL_S = 60
--- Studio: a lone player in line this long is matched by themselves (to try a mode alone).
PlagueMatch.STUDIO_ALONE_S = 2
--- On the online place: a server-run match starts once everyone it expects is in, or after this.
PlagueMatch.ARRIVE_S = 25
--- Line entries read per pass at most.
PlagueMatch.MAX_READ = 200

export type Entry = {
	key: string,
	mode: string,
	--- the rotation's variant this group waits for (Data/PlagueModes.variant)
	variant: string?,
	uids: { string },
	names: { string },
	since: number,
	role: string?,
	job: string?,
}

-- =============================================================================================
-- Forming matches (pure)
-- =============================================================================================

local function sorted(entries: { Entry }): { Entry }
	local list = table.clone(entries)
	table.sort(list, function(a, b)
		if a.since ~= b.since then
			return a.since < b.since
		end
		return a.key < b.key
	end)
	return list
end

--- The sides of a duel: each player's ask where the two differ, else at random (`rand` 0..1).
function PlagueMatch.duel_roles(a: Entry, b: Entry, rand: () -> number): { [string]: string }
	local ra, rb = a.role or "any", b.role or "any"
	local a_plague
	if ra == "plague" or rb == "cure" then
		a_plague = true
	elseif ra == "cure" or rb == "plague" then
		a_plague = false
	else
		a_plague = rand() < 0.5
	end
	return {
		[a.uids[1]] = if a_plague then "plague" else "cure",
		[b.uids[1]] = if a_plague then "cure" else "plague",
	}
end

local function other(role: string?): string
	return if role == "cure" then "plague" else "cure"
end

--- A duel's pairs out of the singles in line (oldest first): a plague with a cure; someone happy with
--- either fills whichever side is short. Two players asking for the same side never meet.
local function duel_pairs(singles: { Entry }): { { Entry } }
	local want = { plague = {}, cure = {}, any = {} }
	for _, e in singles do
		local r = if e.role == "plague" or e.role == "cure" then e.role else "any"
		table.insert(want[r], e)
	end
	local out = {}
	local function take(list: { Entry }): Entry?
		return table.remove(list, 1)
	end
	while #want.plague > 0 and #want.cure > 0 do
		table.insert(out, { take(want.plague) :: Entry, take(want.cure) :: Entry })
	end
	for _, side in { "plague", "cure" } do
		while #want[side] > 0 and #want.any > 0 do
			table.insert(out, { take(want[side]) :: Entry, take(want.any) :: Entry })
		end
	end
	while #want.any >= 2 do
		table.insert(out, { take(want.any) :: Entry, take(want.any) :: Entry })
	end
	return out
end

--- The matches the line makes now: { { mode, groups = { Entry }, roles } }. A group never splits.
--- Co-op / Race: groups fill a match up to its max; it goes when full, or once the oldest has waited
--- fill_s with at least min players (a party of min or more goes at once). A duel: two single players.
--- `studio`: a lone group goes by itself after STUDIO_ALONE_S.
function PlagueMatch.form(entries: { Entry }, now: number, studio: boolean?, rand: (() -> number)?): { any }
	local r = rand or math.random
	local out = {}
	local by_variant: { [string]: { Entry } } = {}
	for _, e in sorted(entries) do
		if Modes.get(e.mode) ~= nil then
			local v = e.variant or e.mode
			by_variant[v] = by_variant[v] or {}
			table.insert(by_variant[v], e)
		end
	end
	for vid, list in by_variant do
		local mode = list[1].mode
		local m = Modes.get(mode) :: any
		local _, map, format = Modes.parse(vid)
		local fmt = Modes.format(format)
		local max = if fmt ~= nil then fmt.max else m.max
		local used: { [string]: boolean } = {}
		local function made(groups: { Entry }, roles: any)
			table.insert(out, { mode = mode, map = map or "world", format = format, groups = groups, roles = roles })
		end
		if mode == "duel" then
			local singles = {}
			for _, e in list do
				if #e.uids == 2 then
					-- a party of two plays each other: the one who pressed it took a side, the friend the other
					made({ e }, { [e.uids[1]] = if e.role == "cure" then "cure" else "plague", [e.uids[2]] = other(if e.role == "cure" then "cure" else "plague") })
				elseif #e.uids == 1 then
					table.insert(singles, e)
				end
			end
			local paired: { [string]: boolean } = {}
			for _, pair in duel_pairs(singles) do
				local a, b = pair[1], pair[2]
				paired[a.key], paired[b.key] = true, true
				made({ a, b }, PlagueMatch.duel_roles(a, b, r))
			end
			if studio then
				-- (Studio: a lone player plays the side they asked for, the plague by default)
				for _, e in singles do
					if not paired[e.key] and now - e.since >= PlagueMatch.STUDIO_ALONE_S then
						made({ e }, { [e.uids[1]] = if e.role == "cure" then "cure" else "plague" })
						break
					end
				end
			end
			continue
		end
		local idx = 1
		while idx <= #list do
			local first = list[idx]
			if used[first.key] then
				idx += 1
				continue
			end
			local groups, n = { first }, #first.uids
			for j = idx + 1, #list do
				local e = list[j]
				if not used[e.key] and n + #e.uids <= max then
					table.insert(groups, e)
					n += #e.uids
				end
			end
			local waited = now - first.since
			local go = n >= max
				or (n >= m.min and waited >= m.fill_s)
				or (studio == true and waited >= PlagueMatch.STUDIO_ALONE_S)
			if go then
				for _, g in groups do
					used[g.key] = true
				end
				made(groups, PlagueMatch.plague_roles(mode, format, groups))
			end
			idx += 1
		end
	end
	return out
end

--- Who plays which plague (a race: one each; a team game: one per team, a party kept together where its
--- team has room): uid -> plague number.
function PlagueMatch.plague_roles(mode: string, format: string?, groups: { Entry }): { [string]: number }
	local roles: { [string]: number } = {}
	local n = 0
	for _, g in groups do
		n += #g.uids
	end
	if mode ~= "teams" then
		local k = 0
		for _, g in groups do
			for _, uid in g.uids do
				k += 1
				roles[uid] = k
			end
		end
		return roles
	end
	local teams = Modes.team_count(format, n)
	local cap = math.ceil(n / teams)
	local size = table.create(teams, 0)
	-- biggest parties first, each whole onto the emptiest team with room; what doesn't fit spills
	local order = table.clone(groups)
	table.sort(order, function(a, b)
		if #a.uids ~= #b.uids then
			return #a.uids > #b.uids
		end
		return a.since < b.since
	end)
	local function emptiest(room: number): number?
		local best, best_n = nil, math.huge
		for t = 1, teams do
			if size[t] + room <= cap and size[t] < best_n then
				best, best_n = t, size[t]
			end
		end
		return best
	end
	for _, g in order do
		local t = emptiest(#g.uids)
		for _, uid in g.uids do
			local tt = t or emptiest(1) or 1
			roles[uid] = tt
			size[tt] += 1
		end
	end
	return roles
end

--- The room a formed match plays (the teleport data's `rp`).
function PlagueMatch.room_of(match: any, id: string, seed: number): any
	local expect, names = {}, {}
	for _, g in match.groups do
		for i, uid in g.uids do
			table.insert(expect, uid)
			names[uid] = g.names[i] or uid
		end
	end
	return {
		id = id,
		mode = match.mode,
		map = match.map or "world",
		format = match.format,
		expect = expect,
		names = names,
		roles = match.roles or {},
		seed = seed,
	}
end

--- A room from teleport data, checked (a client can't make one up: TeleportData comes through the
--- teleport, but the online place may be joined directly too). nil when it isn't one.
function PlagueMatch.clean_room(v: any): any?
	if type(v) ~= "table" or Modes.get(v.mode) == nil or type(v.expect) ~= "table" then
		return nil
	end
	local expect, names, roles = {}, {}, {}
	for _, uid in v.expect do
		if type(uid) == "string" and #uid <= 20 and #expect < 9 then
			table.insert(expect, uid)
			local nm = type(v.names) == "table" and v.names[uid]
			names[uid] = if type(nm) == "string" then string.sub(nm, 1, 40) else uid
			local role = type(v.roles) == "table" and v.roles[uid]
			local num = type(role) == "number" and role >= 1 and role <= 9 and role == math.floor(role)
			if role == "plague" or role == "cure" or num then
				roles[uid] = role
			end
		end
	end
	if #expect == 0 then
		return nil
	end
	local map = if type(v.map) == "string" and Modes.MAP_NAMES[v.map] ~= nil then v.map else "world"
	local format = if Modes.format(v.format) ~= nil then v.format else nil
	return {
		id = if type(v.id) == "string" then string.sub(v.id, 1, 64) else "",
		mode = v.mode,
		map = map,
		format = format,
		expect = expect,
		names = names,
		roles = roles,
		seed = math.floor(tonumber(v.seed) or 1) % 2147483646 + 1,
	}
end

-- =============================================================================================
-- The line (lobby servers)
-- =============================================================================================

--- The MemoryStore line: entries by group key, the formed matches by group key, and the lock.
function PlagueMatch.memory_store(): any
	local MSS = game:GetService("MemoryStoreService")
	local line = MSS:GetSortedMap("rp_mm_line_v1")
	local go = MSS:GetSortedMap("rp_mm_go_v1")
	return {
		put = function(key: string, e: Entry)
			line:SetAsync(key, e, PlagueMatch.ENTRY_TTL_S)
		end,
		remove = function(key: string)
			line:RemoveAsync(key)
		end,
		list = function(): { Entry }
			local out = {}
			for _, it in line:GetRangeAsync(Enum.SortDirection.Ascending, PlagueMatch.MAX_READ) do
				if type(it.value) == "table" then
					table.insert(out, it.value)
				end
			end
			return out
		end,
		lock = function(me: string, now: number): boolean
			local held = false
			go:UpdateAsync("_lock", function(old: any): any?
				if type(old) == "table" and old.job ~= me and (tonumber(old.till) or 0) > now then
					held = false
					return nil
				end
				held = true
				return { job = me, till = now + PlagueMatch.LOCK_TTL_S }
			end, PlagueMatch.LOCK_TTL_S + 2)
			return held
		end,
		put_go = function(key: string, rec: any)
			go:SetAsync("g:" .. key, rec, PlagueMatch.GO_TTL_S)
		end,
		get_go = function(key: string): any?
			return go:GetAsync("g:" .. key)
		end,
		remove_go = function(key: string)
			go:RemoveAsync("g:" .. key)
		end,
	}
end

--- The same line in this server's memory (Lune tests, a server without MemoryStore).
function PlagueMatch.local_store(): any
	local line: { [string]: Entry } = {}
	local go: { [string]: any } = {}
	return {
		put = function(key: string, e: Entry)
			line[key] = e
		end,
		remove = function(key: string)
			line[key] = nil
		end,
		list = function(): { Entry }
			local out = {}
			for _, e in line do
				table.insert(out, e)
			end
			return out
		end,
		lock = function(_me: string, _now: number): boolean
			return true
		end,
		put_go = function(key: string, rec: any)
			go[key] = rec
		end,
		get_go = function(key: string): any?
			return go[key]
		end,
		remove_go = function(key: string)
			go[key] = nil
		end,
	}
end

--- deps: { store, job, now () -> seconds, studio: boolean, reserve () -> code (a reserved server of
--- the online place), teleport (players, code, room) -> (ok, err), start_local (players, room) (Studio),
--- state (players, state, mode, extra) (op PUBLIC_STATE), new_id () -> string, seed () -> number, log }
function PlagueMatch.new(deps: { [string]: any }): any
	local self = setmetatable({}, PlagueMatch)
	self.deps = deps
	--- this server's groups in line: key -> { players, entry, refreshed }
	self.waiting = {} :: { [string]: any }
	--- searching players per mode, from the last read of the line (the cards' "N searching")
	self.counts = {} :: { [string]: number }
	self._read_at = -math.huge
	return self
end

function PlagueMatch.queued(self: any, key: string): any?
	return self.waiting[key]
end

--- `players` (a party: all of them) ask for `mode` (`role`: a duel's side). false + why when refused.
--- (`players[1]` pressed it: in a duel, `role` is their side and a friend with them gets the other.)
function PlagueMatch.join(self: any, key: string, players: { any }, mode: string, role: string?): (boolean, string?)
	local m = Modes.get(mode)
	if m == nil then
		return false, "That mode isn't on offer."
	end
	local v = Modes.variant(mode, self.deps.now())
	if #players > v.max then
		return false, PlagueMatch.TOO_MANY
	end
	if self.waiting[key] ~= nil then
		return true
	end
	local uids, names = {}, {}
	for _, p in players do
		table.insert(uids, tostring(p.UserId))
		table.insert(names, if p.DisplayName ~= "" then p.DisplayName else p.Name)
	end
	local entry: Entry = {
		key = key,
		mode = mode,
		variant = v.id,
		uids = uids,
		names = names,
		since = self.deps.now(),
		role = if role == "plague" or role == "cure" then role else nil,
		job = self.deps.job,
	}
	self.waiting[key] = { players = players, entry = entry, refreshed = entry.since }
	local ok, err = pcall(self.deps.store.put, key, entry)
	if not ok then
		self.waiting[key] = nil
		if self.deps.log then
			self.deps.log("[PlagueMatch] couldn't join the line: " .. tostring(err))
		end
		return false, "Matchmaking is busy. Try again in a moment."
	end
	self.deps.state(players, "line", mode, PlagueMatch.going_info(v))
	return true
end

--- The map a variant goes to (PUBLIC_STATE's extra: the card shows it).
function PlagueMatch.going_info(v: any): any
	return { map = v.map, map_name = v.map_name, format = v.format_label }
end

--- The group leaves the line (true when it was in it).
function PlagueMatch.cancel(self: any, key: string): boolean
	local w = self.waiting[key]
	if w == nil then
		return false
	end
	self.waiting[key] = nil
	pcall(self.deps.store.remove, key)
	self.deps.state(w.players, "idle", w.entry.mode)
	return true
end

--- A player left the server: their group leaves the line.
function PlagueMatch.player_left(self: any, player: any)
	for key, w in self.waiting do
		if table.find(w.players, player) then
			self:cancel(key)
		end
	end
end

--- The cards' rows (op LOBBIES): one per mode, with this rotation's map and format and how many are
--- searching.
function PlagueMatch.view(self: any): { any }
	local rows = {}
	local now = self.deps.now()
	for _, key in Modes.ORDER do
		local m = Modes.MODES[key]
		local v = Modes.variant(key, now)
		table.insert(rows, {
			id = key,
			mode = key,
			plague = true,
			title = m.title,
			sub = m.sub,
			map = v.map,
			map_name = v.map_name,
			format = v.format_label,
			rotate_in = v.rotate_in,
			players = self.counts[key] or 0,
			max = v.max,
			starts_in = 999,
			joinable = true,
		})
	end
	return rows
end

--- Once a second: refresh this server's entries, form matches (under the lock), pick up our groups'.
function PlagueMatch.tick(self: any)
	local deps = self.deps
	local now = deps.now()
	for key, w in self.waiting do
		-- (the rotation moved on: the group waits for the new variant, which is what the card shows)
		local v = Modes.variant(w.entry.mode, now)
		local moved = v ~= nil and v.id ~= w.entry.variant and #w.players <= v.max
		if moved then
			w.entry.variant = v.id
			deps.state(w.players, "line", w.entry.mode, PlagueMatch.going_info(v))
		end
		if moved or now - w.refreshed >= PlagueMatch.REFRESH_S then
			w.refreshed = now
			pcall(deps.store.put, key, w.entry)
		end
	end
	-- form (one server at a time, among those with players waiting; every server reads the counts now
	-- and then)
	local entries: { Entry }? = nil
	local locked_ok, locked = false, false
	if next(self.waiting) ~= nil then
		locked_ok, locked = pcall(deps.store.lock, deps.job or "", now)
	end
	if locked_ok and locked then
		local ok, list = pcall(deps.store.list)
		if ok then
			entries = list
			self:_form(list, now)
		end
	elseif now - self._read_at >= 5 then
		local ok, list = pcall(deps.store.list)
		if ok then
			entries = list
		end
	end
	if entries ~= nil then
		self._read_at = now
		local counts = {}
		for _, e in entries do
			counts[e.mode] = (counts[e.mode] or 0) + #e.uids
		end
		self.counts = counts
	end
	-- our groups' matches
	for key, w in table.clone(self.waiting) do
		local ok, rec = pcall(deps.store.get_go, key)
		if ok and type(rec) == "table" then
			self.waiting[key] = nil
			pcall(deps.store.remove_go, key)
			self:_go(w, rec)
		end
	end
end

function PlagueMatch._form(self: any, list: { Entry }, now: number)
	local deps = self.deps
	for _, match in PlagueMatch.form(list, now, deps.studio) do
		local code = "studio"
		if not deps.studio then
			local ok, c = pcall(deps.reserve)
			if not ok or type(c) ~= "string" then
				if deps.log then
					deps.log("[PlagueMatch] couldn't reserve a server: " .. tostring(c))
				end
				return
			end
			code = c
		end
		local room = PlagueMatch.room_of(match, deps.new_id(), deps.seed())
		for _, g in match.groups do
			pcall(deps.store.remove, g.key)
			pcall(deps.store.put_go, g.key, { code = code, room = room })
		end
		if deps.log then
			deps.log(("[PlagueMatch] %s match for %d players"):format(match.mode, #room.expect))
		end
	end
end

function PlagueMatch._go(self: any, w: any, rec: any)
	local deps = self.deps
	local players = {}
	for _, p in w.players do
		if p.Parent ~= nil then
			table.insert(players, p)
		end
	end
	if #players == 0 then
		return
	end
	local map = if type(rec.room) == "table" and type(rec.room.map) == "string" then rec.room.map else "world"
	deps.state(players, "going", w.entry.mode, { map = map, map_name = Modes.MAP_NAMES[map] or map })
	if rec.code == "studio" then
		deps.start_local(players, rec.room)
		return
	end
	local ok, err = deps.teleport(players, rec.code, rec.room)
	if not ok then
		deps.state(players, "idle", w.entry.mode)
		if deps.log then
			deps.log("[PlagueMatch] teleport failed: " .. tostring(err))
		end
	end
end

-- =============================================================================================
-- A server-run match (Co-op, 1v1): MatchServer's lobby hooks
-- =============================================================================================

--- deps: { now () -> seconds, present () -> { [uid] = true } (players on this server), to_lobby (peers) }
function PlagueMatch.room_hooks(room: any, deps: { [string]: any }): any
	local born = deps.now()
	local function all_in(): boolean
		local here = deps.present()
		for _, uid in room.expect do
			if not here[uid] then
				return false
			end
		end
		return true
	end
	return {
		countdown = function(): number?
			if all_in() then
				return 0
			end
			return math.max(0, born + PlagueMatch.ARRIVE_S - deps.now())
		end,
		info = function(): any
			return {
				map_id = room.map or "world",
				max = #room.expect,
				mode = room.mode,
				plague = {
					mode = room.mode,
					roles = room.roles,
					seed = room.seed,
					names = room.names,
					format = room.format,
					map = room.map or "world",
				},
			}
		end,
		party_of = function(_uid: string): string?
			return nil
		end,
		on_start = function(_humans: number, _voted: boolean?): number
			return 0
		end,
		bot_names = function(_n: number, _taken: any): { string }
			return {}
		end,
		on_vote_start = function(_seconds: number) end,
		on_closed = function() end,
		on_over = function(peers: { any })
			deps.to_lobby(peers)
		end,
	}
end

--- A race's / team game's plagues for PlagueSim (config.plagues), from the room's roles: a race's are
--- named after their players, a team's after the team ("Red Team").
function PlagueMatch.plague_specs(room: any): { any }?
	if room.mode ~= "race" and room.mode ~= "teams" then
		return nil
	end
	local K = 0
	for _, k in room.roles or {} do
		if type(k) == "number" then
			K = math.max(K, k)
		end
	end
	if K < 1 then
		return nil
	end
	local specs = {}
	for k = 1, K do
		specs[k] = { name = if room.mode == "teams" then (Modes.TEAM_NAMES[k] or ("Team " .. k)) .. " Team" else "Plague " .. k }
	end
	if room.mode == "race" then
		for _, uid in room.expect do
			local k = room.roles[uid]
			if type(k) == "number" and specs[k] ~= nil then
				specs[k].name = (room.names[uid] or uid) .. "'s Plague"
			end
		end
	end
	return specs
end

return PlagueMatch
