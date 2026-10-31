--!strict
-- RoPlague's multiplayer modes (2026-10-30), matchmade from the title's three cards (server/PlagueMatch),
-- in this order:
--   duel   1v1: one player is the plague, the other runs the world's cure. Always the World.
--   race   Plague Race, always on the World: every player has their own plague on one shared world,
--          spreading into free countries and ATTACKING each other's (PlagueRules.ATTACK_*); the last
--          plague standing wins (or the deadliest, if humanity goes first).
--   teams  the same war in teams: Duos / Trios / Quads / 4 Teams, each team one plague its players run
--          together. The map and the format rotate.
-- Rotation: every ROTATE_S seconds (os.time, the same on every server) the team game's map + format
-- move on (PlagueModes.variant); a player in line is matched only with others in line for the same
-- variant.
-- min / max: players in a match; fill_s: how long the oldest in line waits for more before a match
-- starts with fewer than max (never below min).
local PlagueModes = {}

export type Mode = {
	key: string,
	title: string,
	sub: string,
	short: string,
	min: number,
	max: number,
	fill_s: number,
	icon: string,
}

export type Format = {
	key: string,
	label: string,
	--- players per team (Duos / Trios / Quads), or nil: a number of teams
	size: number?,
	--- a number of teams (4 Teams), or nil
	teams: number?,
	max: number,
}

export type Variant = {
	id: string,
	mode: string,
	map: string,
	map_name: string,
	format: string?,
	format_label: string?,
	max: number,
	--- seconds until the rotation moves on
	rotate_in: number,
}

PlagueModes.ORDER = { "duel", "race", "teams" }
PlagueModes.ROTATE_S = 300

--- The maps that rotate (MapList ids with a country layer: Core/Plague/Countries).
PlagueModes.MAPS = { "world", "europe", "asia", "africa", "northamerica", "southamerica" }
PlagueModes.MAP_NAMES = {
	world = "World",
	europe = "Europe",
	asia = "Asia",
	africa = "Africa",
	northamerica = "North America",
	southamerica = "South America",
} :: { [string]: string }

PlagueModes.FORMATS = {
	{ key = "duos", label = "Duos", size = 2, max = 8 },
	{ key = "trios", label = "Trios", size = 3, max = 9 },
	{ key = "quads", label = "Quads", size = 4, max = 8 },
	{ key = "teams4", label = "4 Teams", teams = 4, max = 8 },
} :: { Format }

PlagueModes.MODES = {
	duel = {
		key = "duel",
		title = "1V1",
		sub = "World  ·  Plague vs Cure: pick your side",
		short = "Plague vs Cure",
		min = 2,
		max = 2,
		fill_s = 0,
		icon = "cure",
	},
	race = {
		key = "race",
		title = "PLAGUE RACE",
		sub = "World  ·  every player a plague: spread and attack",
		short = "World  ·  free for all",
		min = 2,
		max = 6,
		fill_s = 15,
		icon = "virus",
	},
	teams = {
		key = "teams",
		title = "TEAM PLAGUE",
		sub = "One plague per team: spread and attack",
		short = "Team game",
		min = 2,
		max = 9,
		fill_s = 20,
		icon = "party",
	},
} :: { [string]: Mode }

function PlagueModes.get(key: any): Mode?
	return if type(key) == "string" then PlagueModes.MODES[key] else nil
end

function PlagueModes.format(key: any): Format?
	for _, f in PlagueModes.FORMATS do
		if f.key == key then
			return f
		end
	end
	return nil
end

--- The roles a duel can be asked for (the title's 1v1 picker): "plague" or "cure" ("any" is accepted).
PlagueModes.ROLES = { plague = true, cure = true, any = true }

--- The rotation slot at `now` (os.time seconds).
function PlagueModes.slot(now: number): number
	return math.floor(now / PlagueModes.ROTATE_S)
end

--- What `key` plays at `now`: the map, the format (a team game) and the variant id the line matches on.
function PlagueModes.variant(key: string, now: number): Variant?
	local m = PlagueModes.get(key)
	if m == nil then
		return nil
	end
	local slot = PlagueModes.slot(now)
	local rotate_in = PlagueModes.ROTATE_S - (math.floor(now) % PlagueModes.ROTATE_S)
	local maps = PlagueModes.MAPS
	local map, format = "world", nil
	if key == "teams" then
		map = maps[(slot + 2) % #maps + 1]
		format = PlagueModes.FORMATS[slot % #PlagueModes.FORMATS + 1]
	end
	local id = key .. ":" .. map .. (if format ~= nil then ":" .. format.key else "")
	return {
		id = id,
		mode = key,
		map = map,
		map_name = PlagueModes.MAP_NAMES[map] or map,
		format = if format ~= nil then format.key else nil,
		format_label = if format ~= nil then format.label else nil,
		max = if format ~= nil then format.max else m.max,
		rotate_in = rotate_in,
	}
end

--- A variant id back to its parts (the line's entries carry it): mode, map, format.
function PlagueModes.parse(id: any): (string?, string?, string?)
	if type(id) ~= "string" then
		return nil, nil, nil
	end
	local mode, map, format = string.match(id, "^(%a+):(%a+):?(%w*)$")
	if mode == nil or PlagueModes.get(mode) == nil or PlagueModes.MAP_NAMES[map] == nil then
		return nil, nil, nil
	end
	if format == "" then
		format = nil
	end
	if format ~= nil and PlagueModes.format(format) == nil then
		return nil, nil, nil
	end
	return mode, map, format
end

--- The number of teams a format makes for `players` (at least 2, at most `players`).
function PlagueModes.team_count(format: string?, players: number): number
	local f = PlagueModes.format(format)
	local n = 2
	if f ~= nil and f.size ~= nil then
		n = math.ceil(players / f.size)
	elseif f ~= nil and f.teams ~= nil then
		n = f.teams
	end
	return math.max(2, math.min(n, math.max(2, players)))
end

--- A team's name ("Red Team"), as Core/Teams names them.
PlagueModes.TEAM_NAMES = { "Red", "Blue", "Yellow", "Green", "Purple", "Orange", "Teal", "Pink", "Lime" }

return PlagueModes
