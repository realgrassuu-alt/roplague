--!native
-- RoPlague: the static country layer of a map (Data/Maps/<Module>Countries, made by
-- tools/maps/make_countries.py). Built once per WorldMap and cached on it; read-only afterwards.
--
--   Countries.get(map) -> {
--     count   number of countries (ids 1..count)
--     grid    buffer u8 per tile: country id (0 = water / Antarctica / nobody)
--     list    [id] = {id, name, iso, flag, pop, wealth, climate, density, label, tiles,
--                     neighbors = {{id, shared, border_tile}}, airports = {tile}, ports = {tile},
--                     tile_list = buffer i32 (its tiles, row-major), rgba}
--   } or nil when the map has no country layer.
local Coop = require("../../Net/Coop")
local Defs = require("../Defs")
local MapCodec = require("../MapCodec")
local SimColors = require("../SimColors")
local Nations = require("../../Data/Nations")

local Countries = {}

-- The ModuleScript in Roblox (nil under Lune).
local RBX_SCRIPT: any = script

--- Country colours are RoWorld's own: a country RoWorld had as a nation (Data/Nations, by ISO code)
--- keeps its colour; the others get one from the nations' palette (SimColors.human_palette), the most
--- distinct from the neighbours already coloured, and an authored colour too close to a neighbour's
--- is nudged (SimColors.nudge), as RoWorld does for nations.
local function load_module(module: string): any
	local ok, res = pcall(function(): any
		if RBX_SCRIPT ~= nil then
			local data = RBX_SCRIPT.Parent.Parent.Parent:FindFirstChild("Data")
			local maps = if data ~= nil then data:FindFirstChild("Maps") else nil
			local mod = if maps ~= nil then maps:FindFirstChild(module) else nil
			return if mod ~= nil then (require :: any)(mod) else nil
		end
		return (require :: any)("../../Data/Maps/" .. module)
	end)
	if ok and type(res) == "table" then
		return res
	end
	return nil
end

--- The map's country module name ("WorldCountries" for the World map), or nil.
local function module_of(map: any): string?
	local id = tostring(map.id or "")
	local base = string.match(id, "^(.-)@%d+$") or id
	if base == "world" or base == "" then
		return "WorldCountries"
	end
	return nil
end

function Countries.get(map: any): any
	local cached = map._countries
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local name = module_of(map)
	local data = if name ~= nil then load_module(name) else nil
	if data == nil or data.width ~= map.W or data.height ~= map.H then
		map._countries = false
		return nil
	end
	local W, N = map.W, map.N
	Coop.check()
	local raw = MapCodec.zstd_decompress(MapCodec.b64decode(data.grid))
	assert(buffer.len(raw) == N, "Countries: grid size")
	local grid = buffer.create(N)
	-- only land tiles carry a country (the sim's land mask is the authority)
	local land = map.land
	local readu8 = buffer.readu8
	for i = 0, N - 1 do
		if i % 262144 == 0 then
			Coop.check()
		end
		if readu8(land, i) == 1 then
			buffer.writeu8(grid, i, readu8(raw, i))
		end
	end
	local list = {}
	local count = #data.countries
	local fill = table.create(count + 1, 0)
	for id, c in data.countries do
		list[id] = {
			id = id,
			name = c.name,
			iso = c.iso,
			flag = c.flag,
			pop = c.pop,
			wealth = c.wealth,
			climate = c.climate,
			density = c.density,
			label = c.label,
			tiles = 0,
			neighbors = c.neighbors,
			airports = c.airports,
			ports = c.ports,
			tile_list = buffer.create(4),
			rgba = 0,
		}
	end
	-- tile lists: count, allocate, fill
	for i = 0, N - 1 do
		if i % 262144 == 0 then
			Coop.check()
		end
		local id = readu8(grid, i)
		if id ~= 0 then
			fill[id + 1] += 1
		end
	end
	for id = 1, count do
		list[id].tiles = fill[id + 1]
		list[id].tile_list = buffer.create(math.max(4, fill[id + 1] * 4))
		fill[id + 1] = 0
	end
	for i = 0, N - 1 do
		if i % 262144 == 0 then
			Coop.check()
		end
		local id = readu8(grid, i)
		if id ~= 0 then
			local k = fill[id + 1]
			buffer.writei32(list[id].tile_list, k * 4, i)
			fill[id + 1] = k + 1
		end
	end
	-- a label / airport / port that fell off the land mask: the country's first tile
	for id = 1, count do
		local c = list[id]
		local first = if c.tiles > 0 then buffer.readi32(c.tile_list, 0) else -1
		if c.label < 0 or c.label >= N or readu8(grid, c.label) ~= id then
			c.label = first
		end
		local function fix(ts: { number }): { number }
			local out = {}
			for _, t in ts do
				if t >= 0 and t < N and readu8(grid, t) == id then
					table.insert(out, t)
				end
			end
			return out
		end
		c.airports = fix(c.airports)
		c.ports = fix(c.ports)
	end
	-- colours (RoWorld's): biggest first, each kept distinct from its neighbours
	local authored = {}
	for _, n in Nations do
		if type(n.code) == "string" and type(n.color) == "string" then
			authored[string.lower(n.code)] = Defs.html_rgba(n.color)
		end
	end
	local order = {}
	for id = 1, count do
		table.insert(order, id)
	end
	table.sort(order, function(a, b)
		if list[a].tiles ~= list[b].tiles then
			return list[a].tiles > list[b].tiles
		end
		return a < b
	end)
	local labs = {}
	local palette = SimColors.human_palette()
	for _, id in order do
		local refs = {}
		for _, nb in list[id].neighbors do
			local l = labs[nb[1]]
			if l ~= nil then
				table.insert(refs, l)
			end
		end
		local own = authored[list[id].iso or ""]
		local rgba = if own ~= nil then SimColors.nudge(own, refs) else SimColors.pick(palette, refs)
		list[id].rgba = rgba
		labs[id] = SimColors.oklab(rgba)
	end
	local out = { count = count, grid = grid, list = list, W = W }
	map._countries = out
	return out
end

return Countries
