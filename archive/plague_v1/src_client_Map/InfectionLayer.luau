--!native
-- RoPlague: the infection on the 2D map (DESIGN.md §5), in the place FalloutGlow had.
-- How it is made:
--   * the map's tiles carry the plague's picture in their flags (GameState.flags, Defs.F_INF for an
--     infected tile, F_INF + F_DEAD for a dead one); this layer counts them per SCALE x SCALE block
--     of tiles (4 x 4: 500 x 250 blocks on the 2000 x 1000 World map);
--   * one pixel per block in one EditableImage, stretched over the map in one ImageLabel and linearly
--     filtered, so the red reads as a soft stain rather than as squares: infected blocks a strong red
--     whose opacity follows the share of the block's land that is infected (a block with one case
--     still shows), dead blocks a near-black dark red laid over it as their share of the cases grows;
--     a faint per-block jitter keeps a big stain from looking flat. It lies over the territory fills
--     and borders (MapSurface) and under the plates, units and names; the red is the loudest colour
--     on the map.
--   * clear pixels keep the infected red's RGB at alpha 0, so the filter never darkens the stain's edge.
-- Kept current incrementally: a flags change only marks its block; the marked blocks are counted
-- again from the flags themselves (16 tile reads each) when a redraw is due, UPDATE_S apart (4 Hz),
-- and only the box of pixels that changed is written. A snapshot counts every block again, spread
-- over frames (SCAN_BUDGET_S a frame). Like FalloutGlow it is not written on a frame the map surface
-- wrote one of its images (MapSurface: Roblox shows one EditableImage update a frame), unless it has
-- waited SKIP_MAX frames, and a slow draw waits DUTY times as long before the next one.
local AssetService = game:GetService("AssetService")
local UserInputService = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local Defs = require(Airfront:WaitForChild("Core"):WaitForChild("Defs")) :: any
local FrameClock = require(script.Parent:WaitForChild("FrameClock")) :: any

local InfectionLayer = {}
InfectionLayer.__index = InfectionLayer

--- Tiles a side of a block (a multiple of 4: the counts read the flags four tiles at a time). Bigger
--- maps take a bigger block so the image stays within IMAGE_MAX.
InfectionLayer.SCALE = 4
InfectionLayer.IMAGE_MAX = 1024
-- the look (0..1)
InfectionLayer.INFECTED = { 0.93, 0.07, 0.09 }
InfectionLayer.DEAD = { 0.16, 0.012, 0.02 }
--- Opacity of a block whose land is all infected / all dead (under 1: the country borders still
--- show through).
InfectionLayer.ALPHA_INFECTED = 0.74
InfectionLayer.ALPHA_DEAD = 0.86
--- The least opacity of a block with any case (share of the full one), and the curve toward it.
InfectionLayer.ALPHA_FLOOR = 0.32
InfectionLayer.DENSITY_EXP = 0.7
--- A block's share is taken over at least this many tiles (a tiny island is not a full block of red).
InfectionLayer.DEN_MIN = 3
--- Brightness jitter between blocks (+- half of it).
InfectionLayer.JITTER = 0.16
-- pacing
InfectionLayer.UPDATE_S = 0.25
InfectionLayer.UPDATE_S_MOBILE = 0.3
InfectionLayer.DUTY = 8
InfectionLayer.SKIP_MAX = 2
--- Recount work a frame: a snapshot's full count, and the marked blocks of a redraw.
InfectionLayer.SCAN_BUDGET_S = 0.002
InfectionLayer.RECOUNT_BUDGET_S = 0.003
InfectionLayer.Z = 1 -- in the overlay, under the structure plates

local F_INF: number = Defs.F_INF
local F_DEAD: number = Defs.F_DEAD
local band = bit32.band
local rshift = bit32.rshift
local readu8 = buffer.readu8
local readu32 = buffer.readu32
local readi32 = buffer.readi32
local writeu8 = buffer.writeu8
local writeu32 = buffer.writeu32
local floor = math.floor
local clock = os.clock

local function byte(v: number): number
	return math.clamp(floor(v * 255 + 0.5), 0, 255)
end

--- A clear pixel: the infected red at alpha 0 (see the header).
local CLEAR = byte(InfectionLayer.INFECTED[1])
	+ byte(InfectionLayer.INFECTED[2]) * 256
	+ byte(InfectionLayer.INFECTED[3]) * 65536

--- The block size for a W x H map: SCALE, or a bigger multiple of 4 when the image would not fit.
function InfectionLayer.scale_for(W: number, H: number): number
	local S = InfectionLayer.SCALE
	local m = InfectionLayer.IMAGE_MAX
	while math.ceil(W / S) > m or math.ceil(H / S) > m do
		S += 4
	end
	return S
end

--- The RGBA8 pixel (packed little-endian, as WritePixelsBuffer reads it) of a block with `ni`
--- infected and `nd` dead tiles out of `land` country tiles; `h` in [0, 1) its jitter hash.
function InfectionLayer.pixel(ni: number, nd: number, land: number, h: number): number
	local n = ni + nd
	if n <= 0 then
		return CLEAR
	end
	local G = InfectionLayer
	local den = math.max(land, G.DEN_MIN, n)
	local share = n / den
	local df = nd / n
	local a = (G.ALPHA_INFECTED + (G.ALPHA_DEAD - G.ALPHA_INFECTED) * df)
		* (G.ALPHA_FLOOR + (1 - G.ALPHA_FLOOR) * share ^ G.DENSITY_EXP)
	local inf, dead = G.INFECTED, G.DEAD
	local j = 1 + (h - 0.5) * G.JITTER * (1 - df)
	local r = (inf[1] + (dead[1] - inf[1]) * df) * j
	local g = (inf[2] + (dead[2] - inf[2]) * df) * j
	local b = (inf[3] + (dead[3] - inf[3]) * df) * j
	return byte(r) + byte(g) * 256 + byte(b) * 65536 + math.max(1, byte(a)) * 16777216
end

local function hash(i: number, j: number): number
	local v = math.sin(i * 12.9898 + j * 78.233) * 43758.5453
	return v - floor(v)
end

function InfectionLayer.new(parent: Instance, view: any)
	local self = setmetatable({}, InfectionLayer) :: any
	local label = Instance.new("ImageLabel")
	label.Name = "Infection"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.ScaleType = Enum.ScaleType.Stretch
	label.ResampleMode = Enum.ResamplerMode.Default
	label.Active = false
	label.Visible = false
	label.ZIndex = InfectionLayer.Z
	label.Parent = parent
	self.label = label
	self.view = view
	self._state = nil :: any
	self._img = nil :: EditableImage?
	--- the map and block grid the image is for
	self._W, self._H, self._S = 0, 0, InfectionLayer.SCALE
	self._bw, self._bh = 0, 0
	--- the image's pixels (bw * bh RGBA8), mirrored here: a redraw writes only the box that changed
	self._pix = nil :: buffer?
	--- per block: queued for a recount (u8), and its country tiles (u8; 255 = not counted yet)
	self._queued = nil :: buffer?
	self._land = nil :: buffer?
	self._queue = {} :: { number }
	self._qn = 0
	self._qhead = 1
	--- the next block row of a snapshot's full count (-1: none running)
	self._scan_j = -1
	--- the pixel box changed since the last write (i1 < i0: none)
	self._box = { 0, 0, -1, -1 }
	--- blocks with any opacity (the label hides when none has)
	self._lit = 0
	self._next = 0.0
	self._skipped = 0
	--- scratch for a box smaller than the image (made again only when the box's size changes)
	self._out = nil :: buffer?
	self._out_cells = -1
	--- the label's last position and size (px), and Visible as last written
	self._lx, self._ly, self._lw, self._lh = math.huge, math.huge, -1, -1
	self._vis = false
	--- whether a write happened this frame (for any layer after this one)
	self.uploaded = false
	return self
end

function InfectionLayer._show(self: any, on: boolean)
	if self._vis ~= on then
		self._vis = on
		self.label.Visible = on
	end
end

function InfectionLayer.bind(self: any, state: any)
	self._state = state
	self:_reset()
end

function InfectionLayer.unbind(self: any)
	self._state = nil
	self._qn, self._qhead = 0, 1
	table.clear(self._queue)
	self._scan_j = -1
	self:_show(false)
end

function InfectionLayer.destroy(self: any)
	self:unbind()
	if self._img ~= nil then
		self._img:Destroy()
		self._img = nil
	end
	self.label:Destroy()
end

--- A state (re)loaded: every block is counted again.
function InfectionLayer.on_snapshot(self: any)
	self:_reset()
end

function InfectionLayer._reset(self: any)
	self._qn, self._qhead = 0, 1
	table.clear(self._queue)
	self._scan_j = -1
	self._lit = 0
	self:_show(false)
	local st = self._state
	if st == nil or st.map == nil or st.flags == nil then
		return
	end
	local W, H = st.map.W or Defs.W, st.map.H or Defs.H
	local S = InfectionLayer.scale_for(W, H)
	local bw, bh = math.ceil(W / S), math.ceil(H / S)
	if bw ~= self._bw or bh ~= self._bh or self._img == nil then
		if self._img ~= nil then
			self._img:Destroy()
			self._img = nil
		end
		self._bw, self._bh = bw, bh
		local ok, img = pcall(function()
			return AssetService:CreateEditableImage({ Size = Vector2.new(bw, bh) })
		end)
		if ok and img ~= nil then
			self._img = img
			self.label.ImageContent = Content.fromObject(img)
		end
		self._pix = buffer.create(bw * bh * 4)
		self._queued = buffer.create(bw * bh)
		self._land = buffer.create(bw * bh)
		self._lw, self._lh = -1, -1
	end
	self._W, self._H, self._S = W, H, S
	local pix = self._pix :: buffer
	for b = 0, bw * bh - 1 do
		writeu32(pix, b * 4, CLEAR)
	end
	buffer.fill(self._queued :: buffer, 0, 0)
	buffer.fill(self._land :: buffer, 0, 255)
	-- (the cleared image is written once, so a match that ended red leaves nothing for the next)
	local box = self._box
	box[1], box[2], box[3], box[4] = 0, 0, bw - 1, bh - 1
	self._next = 0
	-- nothing infected or dead anywhere: nothing to count
	local p = st.plague
	if p == nil or ((tonumber(p.I) or 1) <= 0 and (tonumber(p.D) or 1) <= 0) then
		return
	end
	self._scan_j = 0
end

--- GameState.flags_changed (tile * 256 + flags): the changed tiles' blocks are counted again.
function InfectionLayer.on_flags_changed(self: any, changed: { number })
	local queued = self._queued
	if self._state == nil or queued == nil then
		return
	end
	local W, S, bw = self._W, self._S, self._bw
	local queue = self._queue
	local n = self._qn
	for _, v in changed do
		local t = v // 256
		local b = ((t // W) // S) * bw + (t % W) // S
		if readu8(queued, b) == 0 then
			writeu8(queued, b, 1)
			n += 1
			queue[n] = b
		end
	end
	self._qn = n
end

--- GameState.tiles_changed (tile * 1024 + owner): a block whose land changed hands is counted again.
function InfectionLayer.on_tiles_changed(self: any, changed: { number })
	local land = self._land
	if self._state == nil or land == nil then
		return
	end
	local W, S, bw = self._W, self._S, self._bw
	local list = table.create(#changed)
	for k, v in changed do
		local t = v // 1024
		local b = ((t // W) // S) * bw + (t % W) // S
		writeu8(land, b, 255)
		list[k] = t * 256
	end
	self:on_flags_changed(list)
end

--- Counts block (i, j) from the flags (and, the first time it has a case, its country tiles) and
--- writes its pixel into the mirror, growing the changed box when it differs.
function InfectionLayer._count(self: any, flags: buffer, own: buffer?, i: number, j: number)
	local W, H, S, bw = self._W, self._H, self._S, self._bw
	local x0, y0 = i * S, j * S
	local x1, y1 = math.min(x0 + S, W), math.min(y0 + S, H)
	local whole = x1 - x0 == S
	local ni, nd = 0, 0
	for y = y0, y1 - 1 do
		local row = y * W
		if whole then
			for x = x0, x1 - 1, 4 do
				local v = readu32(flags, row + x)
				if v ~= 0 then
					for k = 0, 24, 8 do
						local f = band(rshift(v, k), 255)
						if band(f, F_DEAD) ~= 0 then
							nd += 1
						elseif band(f, F_INF) ~= 0 then
							ni += 1
						end
					end
				end
			end
		else
			for x = x0, x1 - 1 do
				local f = readu8(flags, row + x)
				if f ~= 0 then
					if band(f, F_DEAD) ~= 0 then
						nd += 1
					elseif band(f, F_INF) ~= 0 then
						ni += 1
					end
				end
			end
		end
	end
	local b = j * bw + i
	local px = CLEAR
	if ni + nd > 0 then
		local landbuf = self._land :: buffer
		local land = readu8(landbuf, b)
		if land == 255 then
			land = 0
			if own ~= nil then
				for y = y0, y1 - 1 do
					local row = y * W
					for x = x0, x1 - 1 do
						if readi32(own, (row + x) * 4) > 0 then
							land += 1
						end
					end
				end
			end
			writeu8(landbuf, b, land)
		end
		px = InfectionLayer.pixel(ni, nd, land, hash(i, j))
	end
	local pix = self._pix :: buffer
	local old = readu32(pix, b * 4)
	if old == px then
		return
	end
	writeu32(pix, b * 4, px)
	local was_lit, lit = old >= 16777216, px >= 16777216
	if was_lit ~= lit then
		self._lit += if lit then 1 else -1
	end
	local box = self._box
	if box[3] < box[1] then
		box[1], box[2], box[3], box[4] = i, j, i, j
	else
		if i < box[1] then
			box[1] = i
		elseif i > box[3] then
			box[3] = i
		end
		if j < box[2] then
			box[2] = j
		elseif j > box[4] then
			box[4] = j
		end
	end
end

--- A snapshot's full count, row by row of blocks, while the budget lasts. True when it is done.
function InfectionLayer._scan(self: any, flags: buffer, own: buffer?): boolean
	local deadline = clock() + InfectionLayer.SCAN_BUDGET_S
	local bw, bh = self._bw, self._bh
	local j = self._scan_j
	while j < bh do
		for i = 0, bw - 1 do
			self:_count(flags, own, i, j)
		end
		j += 1
		if clock() > deadline then
			break
		end
	end
	self._scan_j = if j >= bh then -1 else j
	return j >= bh
end

--- The marked blocks counted again, while the budget lasts. True when none is left.
function InfectionLayer._recount(self: any, flags: buffer, own: buffer?): boolean
	local queue, queued = self._queue, self._queued :: buffer
	local bw = self._bw
	local head, n = self._qhead, self._qn
	local deadline = clock() + InfectionLayer.RECOUNT_BUDGET_S
	local k = head
	while k <= n do
		local b = queue[k]
		writeu8(queued, b, 0)
		self:_count(flags, own, b % bw, b // bw)
		k += 1
		if (k - head) % 256 == 0 and clock() > deadline then
			break
		end
	end
	if k > n then
		table.clear(queue)
		self._qn, self._qhead = 0, 1
		return true
	end
	self._qhead = k
	return false
end

function InfectionLayer.tick(self: any, _dt: number)
	self.uploaded = false
	local st = self._state
	local img = self._img
	if st == nil or img == nil or st.flags == nil then
		return
	end
	-- (laid over the map's blocks, moved when the camera did)
	local cam = self.view.rig
	local S = self._S
	local x0, y0 = cam:map_to_screen(0, 0)
	local x1, y1 = cam:map_to_screen(self._bw * S, self._bh * S)
	if x0 ~= self._lx or y0 ~= self._ly then
		self._lx, self._ly = x0, y0
		self.label.Position = UDim2.fromOffset(x0, y0)
	end
	if x1 - x0 ~= self._lw or y1 - y0 ~= self._lh then
		self._lw, self._lh = x1 - x0, y1 - y0
		self.label.Size = UDim2.fromOffset(x1 - x0, y1 - y0)
	end
	local flags: buffer = st.flags
	local own: buffer? = st.owner
	local scanning = self._scan_j >= 0
	if scanning then
		if not self:_scan(flags, own) then
			return
		end
		self._next = 0
	end
	local now = FrameClock.now()
	if now < self._next then
		return
	end
	if self._qn >= self._qhead and not self:_recount(flags, own) then
		-- (the rest next frame: the redraw stays due)
		return
	end
	local box = self._box
	if box[3] < box[1] then
		return
	end
	local surface = self.view.surface
	if surface ~= nil and surface.uploaded and self._skipped < InfectionLayer.SKIP_MAX then
		self._skipped += 1
		return
	end
	self._skipped = 0
	local t0 = clock()
	self:_write(img)
	local wait = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		then InfectionLayer.UPDATE_S_MOBILE
		else InfectionLayer.UPDATE_S
	-- (not while a Studio film steps the clock: its frames take real time the film does not)
	if FrameClock.film == nil then
		wait = math.max(wait, (clock() - t0) * InfectionLayer.DUTY)
	end
	self._next = now + wait
end

--- Writes the changed box of the mirror into the image (the whole image as it is, or the box's rows
--- copied out), and shows the label while any block has opacity.
function InfectionLayer._write(self: any, img: EditableImage)
	local box = self._box
	local i0, j0, i1, j1 = box[1], box[2], box[3], box[4]
	box[1], box[2], box[3], box[4] = 0, 0, -1, -1
	local bw, bh = self._bw, self._bh
	local w, h = i1 - i0 + 1, j1 - j0 + 1
	local pix = self._pix :: buffer
	if w == bw and h == bh then
		img:WritePixelsBuffer(Vector2.zero, Vector2.new(bw, bh), pix)
	else
		if self._out_cells ~= w * h then
			self._out_cells = w * h
			self._out = buffer.create(w * h * 4)
		end
		local out = self._out :: buffer
		local row_bytes = w * 4
		for y = 0, h - 1 do
			buffer.copy(out, y * row_bytes, pix, ((j0 + y) * bw + i0) * 4, row_bytes)
		end
		img:WritePixelsBuffer(Vector2.new(i0, j0), Vector2.new(w, h), out)
	end
	self.uploaded = true
	self:_show(self._lit > 0)
end

return InfectionLayer
