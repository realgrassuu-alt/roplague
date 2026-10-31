-- Dumps each country's map colour (Core/Plague/Countries) as JSON for tools/assets/make_world_scenes.py.
--   .bin/lune.exe run tools/assets/dump_country_colors.luau > build/country_colors.json
require("../../tests/prelude")
local WorldMap = require("../../src/shared/Core/WorldMap")
local Countries = require("../../src/shared/Core/Plague/Countries")
local map = WorldMap.get("world")
local cs = Countries.get(map)
local out = {}
for c = 1, cs.count do
	local rgba = cs.list[c].rgba
	table.insert(out, string.format('"%d":[%d,%d,%d]', c, (rgba // 16777216) % 256, (rgba // 65536) % 256, (rgba // 256) % 256))
end
print("{" .. table.concat(out, ",") .. "}")
