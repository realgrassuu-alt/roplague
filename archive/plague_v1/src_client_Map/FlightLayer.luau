--!native
-- RoPlague: flights on the 2D map (GameState.flights, DESIGN.md §3.4 / §5).
--   * a plane flies the nukes' arc (Rules.nuke_arc: a cubic Bezier raised toward the top of the map,
--     flown at constant speed along it) from its airport to the other, over flight_ticks from
--     launch_tick, at the smoothed render tick;
--   * the sprite is the map's airfield glyph (Assets/MapSprites `ui.airfield`: a white plane seen
--     from above, nose up), turned along the arc and tinted: red when the flight carries the
--     disease, a pale grey-white when it does not; a soft dark copy under it is its shadow, falling
--     further from it the higher it flies (mid-flight), and the plane swells a little up there too;
--   * a short dotted trail behind it in its colour, the dots fixed along the arc (they do not crawl
--     with the plane: a still camera rewrites only the newest), fading toward the tail; all the
--     flights share TRAIL_BUDGET dots, so a sky full of planes keeps a fixed number of objects;
--   * it fades in on take-off and out on landing; GameState.flight_ended takes it off the map.
-- Like UnitLayer, every pooled object remembers what it was last given and is written only what
-- changed, and the pools keep POOL_SPARE spares.
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local Defs = require(Airfront:WaitForChild("Core"):WaitForChild("Defs")) :: any
local Rules = require(Airfront:WaitForChild("Core"):WaitForChild("Rules")) :: any
local Sprites = require(Airfront:WaitForChild("Assets"):WaitForChild("MapSprites")) :: any

local FlightLayer = {}
FlightLayer.__index = FlightLayer

--- A plane is this many full-size tiles across (at least MIN_PX, at most MAX_PX on screen).
FlightLayer.PLANE_SIZE = 16
FlightLayer.MIN_PX = 12
FlightLayer.MAX_PX = 30
--- How much bigger it is at the top of its arc, and how far its shadow falls there (share of its size).
FlightLayer.CLIMB_SCALE = 0.22
FlightLayer.SHADOW_NEAR = 0.08
FlightLayer.SHADOW_FAR = 0.32
FlightLayer.SHADOW_T = 0.55
--- Share of the flight over which it fades in on take-off and out on landing.
FlightLayer.FADE = 0.06
FlightLayer.INFECTED = Color3.fromRGB(255, 52, 44)
FlightLayer.CLEAN = Color3.fromRGB(236, 238, 244)
--- Trail: dots DOT_GAP_PX apart on screen, TRAIL_DOTS at most, DOT_PX wide, their transparency from
--- DOT_T0 (the newest) to DOT_T1 (the oldest); all flights together draw TRAIL_BUDGET at most.
FlightLayer.DOT_GAP_PX = 8
FlightLayer.TRAIL_DOTS = 7
FlightLayer.DOT_PX = 3
FlightLayer.DOT_T0 = 0.2
FlightLayer.DOT_T1 = 0.85
FlightLayer.TRAIL_BUDGET = 360
FlightLayer.POOL_SPARE = 24
--- Over the ships (UnitLayer.Z 14), under the effects (FxLayer.Z 16).
FlightLayer.Z = 15

--- The plane image: the airfield glyph (nil: planes are drawn from frames).
local PLANE_IMAGE: string? = if type(Sprites.ui) == "table" and type(Sprites.ui.airfield) == "string"
	then Sprites.ui.airfield
	else nil

type Plane = {
	plane: GuiObject,
	shadow: GuiObject,
	--- (frames-drawn planes: the parts to tint, the plane's and its shadow's)
	parts: { Frame }?,
	sparts: { Frame }?,
	vis: boolean,
	x: number,
	y: number,
	sx: number,
	sy: number,
	px: number,
	rot: number,
	col: Color3?,
	t: number,
}
type Dot = { f: Frame, vis: boolean, x: number, y: number, px: number, col: Color3?, t: number }

local function centre(t: number, W: number): (number, number)
	return t % W + 0.5, t // W + 0.5
end

--- A flight's arc (built once per flight): the nukes' Bezier, or the same curve worked out here
--- should the rules no longer have it.
function FlightLayer.arc_of(st: any, f: any): any
	local arc = f._arc
	if arc ~= nil then
		return arc
	end
	local R = st.rules or Rules
	local W, H = st.map.W or Defs.W, st.map.H or Defs.H
	if type(R.nuke_arc) == "function" then
		arc = R.nuke_arc(W, H, f.from_tile, f.to_tile)
	else
		local sx, sy = centre(f.from_tile, W)
		local dx, dy = centre(f.to_tile, W)
		local ddx, ddy = dx - sx, dy - sy
		local dist = math.sqrt(ddx * ddx + ddy * ddy)
		local hmax = math.max(dist / 3, 50 / (tonumber(st.map.k_lin) or 1))
		local p1x, p1y = sx + ddx / 4, math.clamp(sy + ddy / 4 - hmax, 0, H - 1)
		local p2x, p2y = sx + ddx * 3 / 4, math.clamp(sy + ddy * 3 / 4 - hmax, 0, H - 1)
		local n = 64
		local xs, ys, lens = table.create(n + 1), table.create(n + 1), table.create(n + 1)
		local total, px, py = 0.0, sx, sy
		for i = 0, n do
			local t = i / n
			local u = 1 - t
			local a, b, c, d = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
			local x = a * sx + b * p1x + c * p2x + d * dx
			local y = a * sy + b * p1y + c * p2y + d * dy
			if i > 0 then
				total += math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
			end
			xs[i + 1], ys[i + 1], lens[i + 1] = x, y, total
			px, py = x, y
		end
		arc = { xs = xs, ys = ys, lens = lens, length = total }
	end
	f._arc = arc
	return arc
end

--- Map point at arc-length fraction s (Rules.nuke_arc_at, or the same lookup).
function FlightLayer.arc_at(arc: any, s: number): (number, number)
	if type(Rules.nuke_arc_at) == "function" then
		return Rules.nuke_arc_at(arc, s)
	end
	local xs, ys, lens = arc.xs, arc.ys, arc.lens
	local total = arc.length
	if total <= 0 then
		return xs[1], ys[1]
	end
	local want = math.clamp(s, 0, 1) * total
	local lo, hi = 1, #lens
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if lens[mid] < want then
			lo = mid
		else
			hi = mid
		end
	end
	local seg = lens[hi] - lens[lo]
	local k = if seg > 0 then (want - lens[lo]) / seg else 0
	return xs[lo] + (xs[hi] - xs[lo]) * k, ys[lo] + (ys[hi] - ys[lo]) * k
end

--- The flight fraction (0..1) of `f` at render tick `rt`.
function FlightLayer.progress(f: any, rt: number): number
	return math.clamp((rt - f.launch_tick) / math.max(f.flight_ticks, 1), 0, 1)
end

function FlightLayer.new(parent: Instance, view: any)
	local self = setmetatable({}, FlightLayer) :: any
	local root = Instance.new("Frame")
	root.Name = "Flights"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = FlightLayer.Z
	root.Parent = parent
	self.root = root
	self.view = view
	self._state = nil :: any
	--- uid -> its plane (while it flies)
	self._planes = {} :: { [number]: Plane }
	self._pool = {} :: { Plane }
	self._dots = {} :: { Dot }
	self._dots_used = 0
	return self
end

function FlightLayer.bind(self: any, state: any)
	self:unbind()
	self._state = state
end

function FlightLayer.unbind(self: any)
	self._state = nil
	for uid, p in self._planes do
		self:_release(p)
		self._planes[uid] = nil
	end
	for _, d in self._dots do
		if d.vis then
			d.vis = false
			d.f.Visible = false
		end
	end
end

function FlightLayer.destroy(self: any)
	self:unbind()
	self.root:Destroy()
end

--- A state (re)loaded: the planes are found again from state.flights on the next frame.
function FlightLayer.on_snapshot(self: any)
	for uid, p in self._planes do
		self:_release(p)
		self._planes[uid] = nil
	end
end

--- GameState.flight_added: drawn from the next frame (tick walks state.flights).
function FlightLayer.on_flight_added(_self: any, _uid: number) end

--- GameState.flight_ended (fired while the flight is still in state.flights): its plane goes.
function FlightLayer.on_flight_ended(self: any, uid: number, _seeded: boolean?)
	local p = self._planes[uid]
	if p ~= nil then
		self:_release(p)
		self._planes[uid] = nil
	end
	local st = self._state
	local f = if st ~= nil then st.flights[uid] else nil
	if f ~= nil then
		f._gone = true
	end
end

-- ---------------------------------------------------------------------------------------------
-- Pools
-- ---------------------------------------------------------------------------------------------

--- A plane drawn from frames (a fuselage, wings and a tail, nose up), for when there is no image.
local function frame_plane(name: string, z: number): (Frame, { Frame })
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundTransparency = 1
	f.ZIndex = z
	local parts = {}
	local function part(px: number, py: number, sx: number, sy: number)
		local p = Instance.new("Frame")
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.fromScale(px, py)
		p.Size = UDim2.fromScale(sx, sy)
		p.BorderSizePixel = 0
		p.ZIndex = z
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = p
		p.Parent = f
		table.insert(parts, p)
	end
	part(0.5, 0.5, 0.16, 0.9) -- fuselage
	part(0.5, 0.5, 0.9, 0.16) -- wings
	part(0.5, 0.86, 0.42, 0.12) -- tail
	return f, parts
end

local function image_plane(name: string, z: number): ImageLabel
	local l = Instance.new("ImageLabel")
	l.Name = name
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.BackgroundTransparency = 1
	l.Image = PLANE_IMAGE :: string
	l.ScaleType = Enum.ScaleType.Fit
	l.ZIndex = z
	return l
end

function FlightLayer._acquire(self: any): Plane
	local p = table.remove(self._pool)
	if p then
		return p
	end
	local plane: GuiObject, shadow: GuiObject
	local parts: { Frame }?, sparts: { Frame }? = nil, nil
	if PLANE_IMAGE ~= nil then
		plane = image_plane("Plane", FlightLayer.Z + 1)
		local sh = image_plane("Shadow", FlightLayer.Z)
		sh.ImageColor3 = Color3.new(0, 0, 0)
		shadow = sh
	else
		local fp, ps = frame_plane("Plane", FlightLayer.Z + 1)
		plane, parts = fp, ps
		local fs, sps = frame_plane("Shadow", FlightLayer.Z)
		for _, s in sps do
			s.BackgroundColor3 = Color3.new(0, 0, 0)
		end
		shadow, sparts = fs, sps
	end
	plane.Visible = false
	shadow.Visible = false
	shadow.Parent = self.root
	plane.Parent = self.root
	return {
		plane = plane,
		shadow = shadow,
		parts = parts,
		sparts = sparts,
		vis = false,
		x = math.huge,
		y = math.huge,
		sx = math.huge,
		sy = math.huge,
		px = -1,
		rot = math.huge,
		col = nil,
		t = -1,
	}
end

function FlightLayer._release(self: any, p: Plane)
	if #self._pool >= FlightLayer.POOL_SPARE then
		p.plane:Destroy()
		p.shadow:Destroy()
		return
	end
	if p.vis then
		p.vis = false
		p.plane.Visible = false
		p.shadow.Visible = false
	end
	table.insert(self._pool, p)
end

local function set_t(o: GuiObject, parts: { Frame }?, t: number)
	if parts ~= nil then
		for _, f in parts do
			f.BackgroundTransparency = t
		end
	else
		(o :: ImageLabel).ImageTransparency = t
	end
end

function FlightLayer._dot(self: any, x: number, y: number, px: number, col: Color3, t: number)
	self._dots_used += 1
	local d = self._dots[self._dots_used]
	if d == nil then
		local f = Instance.new("Frame")
		f.Name = "Trail"
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BorderSizePixel = 0
		f.ZIndex = FlightLayer.Z - 1
		f.Parent = self.root
		d = { f = f, vis = true, x = math.huge, y = math.huge, px = -1, col = nil, t = -1 }
		self._dots[self._dots_used] = d
	end
	local f = d.f
	if not d.vis then
		d.vis = true
		f.Visible = true
	end
	local rx, ry = math.round(x), math.round(y)
	if d.x ~= rx or d.y ~= ry then
		d.x, d.y = rx, ry
		f.Position = UDim2.fromOffset(rx, ry)
	end
	if d.px ~= px then
		d.px = px
		f.Size = UDim2.fromOffset(px, px)
	end
	if d.col ~= col then
		d.col = col
		f.BackgroundColor3 = col
	end
	if d.t ~= t then
		d.t = t
		f.BackgroundTransparency = t
	end
end

-- ---------------------------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------------------------

function FlightLayer.tick(self: any, _dt: number)
	local st = self._state
	if st == nil then
		return
	end
	local flights = st.flights
	self._dots_used = 0
	if flights == nil or next(flights) == nil then
		if next(self._planes) ~= nil then
			for uid, p in self._planes do
				self:_release(p)
				self._planes[uid] = nil
			end
		end
		self:_trim_dots()
		return
	end
	local cam = self.view.rig
	local rt = st.render_tick or st.tick or 0
	local k = tonumber(st.map and st.map.k_lin) or Rules.K_LIN or 1
	local base = math.clamp(FlightLayer.PLANE_SIZE / k * cam.scale, FlightLayer.MIN_PX, FlightLayer.MAX_PX)
	local n_flying = 0
	for _, f in flights do
		if not f._gone then
			n_flying += 1
		end
	end
	local dots_each = math.min(FlightLayer.TRAIL_DOTS, FlightLayer.TRAIL_BUDGET // math.max(n_flying, 1))
	local dot_px = math.max(2, math.round(FlightLayer.DOT_PX * math.clamp(cam.scale / k, 0.75, 1.4)))
	local seen = self._seen
	if seen == nil then
		seen = {}
		self._seen = seen
	else
		table.clear(seen)
	end
	for uid, f in flights do
		if f._gone then
			continue
		end
		local arc = FlightLayer.arc_of(st, f)
		local t = FlightLayer.progress(f, rt)
		local u, v = FlightLayer.arc_at(arc, t)
		local x, y = cam:map_to_screen(u, v)
		local climb = math.sin(math.pi * t)
		local px = math.round(base * (1 + FlightLayer.CLIMB_SCALE * climb))
		local col = if f.infected then FlightLayer.INFECTED else FlightLayer.CLEAN
		-- the trail: dots at fixed points along the arc behind the plane (newest first)
		local len_px = arc.length * cam.scale
		if dots_each > 0 and len_px > FlightLayer.DOT_GAP_PX * 2 then
			local step = FlightLayer.DOT_GAP_PX / len_px
			local newest = math.floor(t / step)
			local skip = px * 0.55 / len_px -- (none under the plane itself)
			local drawn = 0
			for idx = newest, math.max(0, newest - dots_each - 1), -1 do
				local s = idx * step
				if t - s < skip then
					continue
				end
				if drawn >= dots_each then
					break
				end
				local du, dv = FlightLayer.arc_at(arc, s)
				local dx, dy = cam:map_to_screen(du, dv)
				if cam:on_screen(dx, dy, dot_px) then
					local a = FlightLayer.DOT_T0
						+ (FlightLayer.DOT_T1 - FlightLayer.DOT_T0) * drawn / math.max(dots_each - 1, 1)
					self:_dot(dx, dy, dot_px, col, math.round(a * 20) / 20)
				end
				drawn += 1
			end
		end
		if not cam:on_screen(x, y, px * 2) then
			continue
		end
		seen[uid] = true
		local p = self._planes[uid]
		if p == nil then
			p = self:_acquire()
			self._planes[uid] = p
		end
		-- heading: along the arc here (the glyph's nose points up: +90 degrees)
		local ea, eb = math.max(0, t - 0.01), math.min(1, t + 0.01)
		local au, av = FlightLayer.arc_at(arc, ea)
		local bu, bv = FlightLayer.arc_at(arc, eb)
		local rot = math.round(math.deg(math.atan2(bv - av, bu - au)) + 90)
		local fade = FlightLayer.FADE
		local vis_t = 1 - math.clamp(math.min(t, 1 - t) / fade, 0, 1)
		local tr = math.round(vis_t * 20) / 20
		local plane, shadow = p.plane, p.shadow
		if not p.vis then
			p.vis = true
			plane.Visible = true
			shadow.Visible = true
		end
		if p.px ~= px then
			p.px = px
			plane.Size = UDim2.fromOffset(px, px)
			shadow.Size = UDim2.fromOffset(px, px)
		end
		if p.rot ~= rot then
			p.rot = rot
			plane.Rotation = rot
			shadow.Rotation = rot
		end
		local rx, ry = math.round(x), math.round(y)
		if p.x ~= rx or p.y ~= ry then
			p.x, p.y = rx, ry
			plane.Position = UDim2.fromOffset(rx, ry)
		end
		local off = px * (FlightLayer.SHADOW_NEAR + (FlightLayer.SHADOW_FAR - FlightLayer.SHADOW_NEAR) * climb)
		local sx, sy = math.round(x + off * 0.6), math.round(y + off)
		if p.sx ~= sx or p.sy ~= sy then
			p.sx, p.sy = sx, sy
			shadow.Position = UDim2.fromOffset(sx, sy)
		end
		if p.col ~= col then
			p.col = col
			if p.parts ~= nil then
				for _, part in p.parts do
					part.BackgroundColor3 = col
				end
			else
				(plane :: ImageLabel).ImageColor3 = col
			end
		end
		if p.t ~= tr then
			p.t = tr
			set_t(plane, p.parts, tr)
			set_t(shadow, p.sparts, 1 - (1 - FlightLayer.SHADOW_T) * (1 - tr))
		end
	end
	for uid, p in self._planes do
		if not seen[uid] then
			self:_release(p)
			self._planes[uid] = nil
		end
	end
	self:_trim_dots()
end

--- The dots not used this frame hide; past POOL_SPARE spares they go.
function FlightLayer._trim_dots(self: any)
	local spare = FlightLayer.POOL_SPARE
	for i = #self._dots, self._dots_used + 1, -1 do
		local d = self._dots[i]
		if i > self._dots_used + spare then
			d.f:Destroy()
			self._dots[i] = nil
		elseif d.vis then
			d.vis = false
			d.f.Visible = false
		end
	end
end

return FlightLayer
