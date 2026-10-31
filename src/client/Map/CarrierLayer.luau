--!native
-- RoPlague: the infected travellers on the 2D map (GameState.flights). A land infection (the "infect"
-- click on a bordering country) is carried by a sick person who walks from inside the infected
-- country to the border, over flight_ticks from launch_tick at the smoothed render tick; the
-- plague lands when they arrive (the sim seeds the country then; FxLayer.infect draws the wave).
-- Drawn the way RoWorld draws its ships (Map/UnitLayer), so the two read as one family:
--   * a pixel sprite (Assets/PlagueIcons `walker_pixel`, tools/assets/make_pixel_walker.py: body
--     white, rim grey, two frames) tinted in the infection colour the plague wears (Data/Strains.tint,
--     as its ships are), UNIT_SIZE full-size tiles wide like a ship, never under MIN_PX;
--   * it walks the straight line to the border, its two frames swapping every STEP_S, mirrored when
--     it walks to the left;
--   * behind it a wake: the way walked so far, in the plague's colour at TRAIL_ALPHA (a ship's wake);
--   * it fades in when it sets off and out when it arrives.
-- Every pooled object remembers what it was last given and is written only what changed.
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local FrameClock = require(script.Parent:WaitForChild("FrameClock")) :: any
local Strains = require(Airfront:WaitForChild("Data"):WaitForChild("Strains")) :: any

local CarrierLayer = {}
CarrierLayer.__index = CarrierLayer

--- As wide as a ship (UnitLayer.UNIT_SIZE full-size tiles), within MIN_PX..MAX_PX on screen.
CarrierLayer.UNIT_SIZE = 13
CarrierLayer.MIN_PX = 20
CarrierLayer.MAX_PX = 64
--- The sprite sheet: FRAMES frames of CELL px in one row; a frame lasts STEP_S.
CarrierLayer.FRAMES = 2
CarrierLayer.CELL = 128
CarrierLayer.STEP_S = 0.2
--- The wake (UnitLayer.TRAIL_ALPHA): its opacity, and its least width on screen.
CarrierLayer.TRAIL_ALPHA = 0.588
CarrierLayer.TRAIL_MIN_PX = 2
--- Share of the walk over which it fades in; how long it takes to fade out on arrival.
CarrierLayer.FADE = 0.06
CarrierLayer.ARRIVE_S = 0.3
CarrierLayer.COLOR = Color3.fromRGB(228, 52, 60)
--- Over the ships (UnitLayer.Z 14), under the effects (FxLayer.Z 16).
CarrierLayer.Z = 15

local SHEET: string = ""
do
	local ok, icons = pcall(function()
		return require(Airfront:WaitForChild("Assets"):WaitForChild("PlagueIcons")) :: any
	end)
	if ok and type(icons) == "table" then
		SHEET = icons.walker_pixel or ""
	end
end

type Walker = {
	uid: number,
	from_u: number,
	from_v: number,
	to_u: number,
	to_v: number,
	launch: number,
	ticks: number,
	left: boolean,
	--- set once it has arrived (FrameClock time)
	gone_t: number?,
	g: any,
}

function CarrierLayer.new(parent: Instance, view: any)
	local self = setmetatable({}, CarrierLayer) :: any
	local root = Instance.new("Frame")
	root.Name = "Carriers"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = CarrierLayer.Z
	root.Parent = parent
	self.root = root
	self.view = view
	self._state = nil :: any
	self._live = {} :: { [number]: Walker }
	self._pool = {} :: { any }
	return self
end

function CarrierLayer.bind(self: any, state: any)
	self:unbind()
	self._state = state
	self:on_snapshot()
end

function CarrierLayer.unbind(self: any)
	for uid, w in self._live do
		self:_release(w.g)
		self._live[uid] = nil
	end
	self._state = nil
end

function CarrierLayer.destroy(self: any)
	self:unbind()
	self.root:Destroy()
end

function CarrierLayer.on_snapshot(self: any)
	for uid, w in self._live do
		self:_release(w.g)
		self._live[uid] = nil
	end
	local st = self._state
	if st == nil or st.flights == nil then
		return
	end
	for uid in st.flights do
		self:on_flight_added(uid)
	end
end

function CarrierLayer.on_flight_added(self: any, uid: number)
	local st = self._state
	local f = if st ~= nil and st.flights ~= nil then st.flights[uid] else nil
	if f == nil or self._live[uid] ~= nil then
		return
	end
	local W = st.map.W
	local fu, fv = f.from_tile % W + 0.5, f.from_tile // W + 0.5
	local tu, tv = f.to_tile % W + 0.5, f.to_tile // W + 0.5
	self._live[uid] = {
		uid = uid,
		from_u = fu,
		from_v = fv,
		to_u = tu,
		to_v = tv,
		launch = f.launch_tick,
		ticks = math.max(1, f.flight_ticks),
		left = tu < fu,
		gone_t = nil,
		g = self:_acquire(),
	}
end

function CarrierLayer.on_flight_ended(self: any, uid: number, _seeded: boolean?)
	local w = self._live[uid]
	if w ~= nil and w.gone_t == nil then
		w.gone_t = FrameClock.now()
	end
end

function CarrierLayer._acquire(self: any): any
	local g = table.remove(self._pool)
	if g ~= nil then
		g.holder.Visible = true
		return g
	end
	local Z = CarrierLayer.Z
	local holder = Instance.new("Frame")
	holder.Name = "Carrier"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = Z
	holder.Parent = self.root
	local wake = Instance.new("Frame")
	wake.Name = "Wake"
	wake.AnchorPoint = Vector2.new(0.5, 0.5)
	wake.BorderSizePixel = 0
	wake.ZIndex = Z
	wake.Parent = holder
	local img = Instance.new("ImageLabel")
	img.Name = "Walker"
	img.BackgroundTransparency = 1
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Image = SHEET
	img.ImageRectSize = Vector2.new(CarrierLayer.CELL, CarrierLayer.CELL)
	img.ResampleMode = Enum.ResamplerMode.Pixelated
	img.ZIndex = Z + 1
	img.Parent = holder
	return {
		holder = holder,
		wake = wake,
		img = img,
		px = -1,
		frame = -1,
		left = nil,
		col = nil,
		x = -1e9,
		y = -1e9,
	}
end

function CarrierLayer._release(self: any, g: any)
	g.holder.Visible = false
	g.x, g.y = -1e9, -1e9
	table.insert(self._pool, g)
end

--- The plague's colour: the infection colour it wears (Data/Strains), like its ships and its patches.
function CarrierLayer._color(self: any): Color3
	local ok, c = pcall(function()
		return Strains.tint(Strains.worn(self._state), FrameClock.now())
	end)
	return if ok and typeof(c) == "Color3" then c else CarrierLayer.COLOR
end

function CarrierLayer.tick(self: any, _dt: number)
	local st = self._state
	if st == nil or next(self._live) == nil then
		return
	end
	local cam = self.view.rig
	local now = FrameClock.now()
	local rt = st.render_tick or st.tick or 0
	local k = tonumber(st.map and st.map.k_lin) or 1
	local tile_px = cam.scale / k
	local px = math.clamp(math.round(CarrierLayer.UNIT_SIZE * tile_px), CarrierLayer.MIN_PX, CarrierLayer.MAX_PX)
	local col = self:_color()
	for uid, w in self._live do
		local g = w.g
		local alpha = 1.0
		if w.gone_t ~= nil then
			local a = (now - w.gone_t) / CarrierLayer.ARRIVE_S
			if a >= 1 then
				self:_release(g)
				self._live[uid] = nil
				continue
			end
			alpha = 1 - a
		end
		local p = if w.gone_t ~= nil then 1 else math.clamp((rt - w.launch) / w.ticks, 0, 1)
		if p < CarrierLayer.FADE then
			alpha = math.min(alpha, math.max(0.05, p / CarrierLayer.FADE))
		end
		local u = w.from_u + (w.to_u - w.from_u) * p
		local v = w.from_v + (w.to_v - w.from_v) * p
		local x, y = cam:map_to_screen(u, v)
		local sx, sy = cam:map_to_screen(w.from_u, w.from_v)
		local on = cam:on_screen(x, y, px * 2) or cam:on_screen(sx, sy, px * 2)
		g.holder.Visible = on
		if not on then
			continue
		end
		if g.col ~= col then
			g.col = col
			g.img.ImageColor3 = col
			g.wake.BackgroundColor3 = col
		end
		if g.px ~= px then
			g.px = px
			g.img.Size = UDim2.fromOffset(px, px)
		end
		-- two frames, swapping while it walks; mirrored to face the way it goes
		local f = if w.gone_t ~= nil then 1 else math.floor(now / CarrierLayer.STEP_S) % CarrierLayer.FRAMES
		if g.frame ~= f or g.left ~= w.left then
			g.frame, g.left = f, w.left
			local c = CarrierLayer.CELL
			-- (a negative rect width mirrors the image)
			g.img.ImageRectOffset = Vector2.new(if w.left then (f + 1) * c else f * c, 0)
			g.img.ImageRectSize = Vector2.new(if w.left then -c else c, c)
		end
		local rx, ry = math.round(x), math.round(y)
		if rx ~= g.x or ry ~= g.y then
			g.x, g.y = rx, ry
			g.img.Position = UDim2.fromOffset(rx, ry)
		end
		g.img.ImageTransparency = 1 - alpha
		-- the wake: from where it set off to its feet
		local dx, dy = x - sx, y - sy
		local len = math.sqrt(dx * dx + dy * dy)
		local wake = g.wake
		if len < 1 then
			wake.Visible = false
		else
			wake.Visible = true
			local width = math.max(CarrierLayer.TRAIL_MIN_PX, math.round(tile_px))
			wake.Position = UDim2.fromOffset((sx + x) * 0.5, (sy + y) * 0.5)
			wake.Size = UDim2.fromOffset(len, width)
			wake.Rotation = math.deg(math.atan2(dy, dx))
			wake.BackgroundTransparency = 1 - CarrierLayer.TRAIL_ALPHA * alpha
		end
	end
end

return CarrierLayer
