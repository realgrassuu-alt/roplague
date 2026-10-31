-- RoPlague: what the plague's infected tiles look like (PlagueSim.tstate), for checking how a country fills
-- in. Plays the balanced bot to `day` and writes a PPM of a crop of the world map:
--   .bin/lune.exe run tools/balance/tiles_png.luau [day=260] [x0 y0 x1 y1 = 1215 239 1685 474] [seed=1]
-- -> build/tiles_day<day>.ppm (sea blue, land grey, queued light, infected red, dead dark red).
local fs = require("@lune/fs")
local process = require("@lune/process")
require("../../tests/prelude")
local WorldMap = require("../../src/shared/Core/WorldMap")
local PlagueSim = require("../../src/shared/Core/Plague/PlagueSim")
local Defs = require("../../src/shared/Core/Defs")

local a = process.args
local day = tonumber(a[1]) or 260
local x0, y0, x1, y1 = tonumber(a[2]) or 1215, tonumber(a[3]) or 239, tonumber(a[4]) or 1685, tonumber(a[5]) or 474
local seed = tonumber(a[6]) or 1

local map = WorldMap.get("world")
local sim = PlagueSim.new(map, { seed = seed, difficulty = 1, pathogen = "bacterium", auto = true, strategy = "balanced" })
local zero = -1
for _ = 1, 4000 * PlagueSim.DAY_TICKS do
	sim:step()
	if zero < 0 and sim.phase == Defs.PHASE_PLAYING then
		zero = sim.tick
	end
	if zero >= 0 and (sim.tick - zero) // PlagueSim.DAY_TICKS >= day or sim.phase == Defs.PHASE_OVER then
		break
	end
end

local W = sim.W
local ts, grid = sim.tstate, sim.cs.grid
local w, h = x1 - x0, y1 - y0
local out = buffer.create(w * h * 3)
local COL = {
	[0] = { 150, 150, 150 },
	[1] = { 200, 180, 180 },
	[2] = { 214, 28, 40 },
	[3] = { 70, 10, 16 },
}
for y = 0, h - 1 do
	for x = 0, w - 1 do
		local t = (y0 + y) * W + (x0 + x)
		local c = if buffer.readu8(grid, t) == 0 then { 60, 110, 160 } else COL[buffer.readu8(ts, t)]
		local o = (y * w + x) * 3
		buffer.writeu8(out, o, c[1])
		buffer.writeu8(out, o + 1, c[2])
		buffer.writeu8(out, o + 2, c[3])
	end
end
local path = ("build/tiles_day%d.ppm"):format(day)
fs.writeFile(path, ("P6\n%d %d\n255\n"):format(w, h) .. buffer.tostring(out))
print("wrote", path, "infected world", math.floor(sim.Iw / sim.world_pop * 1000) / 10 .. "%")
