--!native
-- RoPlague: the bubbles on the 2D map (GameState.bubbles, DESIGN.md §4.1 / §5): a DNA bubble
-- (kind 0) is orange-red, a cure bubble (kind 1) blue, each a round button over its tile showing
-- what it pays.
--   * size: BASE_PX at REF_ZOOM (px per full-size tile), growing gently with the zoom
--     ((zoom / REF_ZOOM) ^ ZOOM_EXP), never under MIN_PX (a finger has to hit it) nor over MAX_PX;
--   * it pops in (a Back ease over POP_IN_S), bobs BOB_PX up and down, bobs faster and pulses in
--     its last URGENT_TICKS; a bubble collected (bubble_removed, popped) swells and fades over POP_S,
--     one that ran out (not popped) shrinks and fades over FADE_S;
--   * a press fires MapView.bubble_clicked(id) (the UI sends the intent); the button is Active, so the
--     press never also reaches the map (MapInput: a press the GUI processed is not the map's).
-- The bubbles live in their own ScreenGui above the names (MapView), so a bubble at a country's
-- label point is never under its name. Pooled; every object is written only what changed.
local RS = game:GetService("ReplicatedStorage")
local Airfront = RS:WaitForChild("Airfront")
local Defs = require(Airfront:WaitForChild("Core"):WaitForChild("Defs")) :: any
local Rules = require(Airfront:WaitForChild("Core"):WaitForChild("Rules")) :: any
local FrameClock = require(script.Parent:WaitForChild("FrameClock")) :: any

local BubbleLayer = {}
BubbleLayer.__index = BubbleLayer

BubbleLayer.BASE_PX = 34
BubbleLayer.MIN_PX = 28
BubbleLayer.MAX_PX = 48
BubbleLayer.REF_ZOOM = 2.0
BubbleLayer.ZOOM_EXP = 0.25
--- The bubble's centre sits this share of its size above its tile.
BubbleLayer.LIFT = 0.55
BubbleLayer.BOB_PX = 3.0
BubbleLayer.BOB_HZ = 0.6
BubbleLayer.URGENT_TICKS = 20
BubbleLayer.URGENT_HZ = 2.2
BubbleLayer.POP_IN_S = 0.3
BubbleLayer.POP_S = 0.24
BubbleLayer.POP_SCALE = 0.7
BubbleLayer.FADE_S = 0.45
--- A press dips the bubble for PRESS_S; a second press within DEBOUNCE_S is not sent again.
BubbleLayer.PRESS_S = 0.12
BubbleLayer.DEBOUNCE_S = 0.4
BubbleLayer.HOVER_SCALE = 1.1
BubbleLayer.FONT = Font.fromId(12187365977, Enum.FontWeight.Bold)
--- (top, bottom) of each kind's gradient, and its rim
BubbleLayer.KINDS = {
	[0] = { Color3.fromRGB(255, 156, 66), Color3.fromRGB(226, 52, 30), Color3.fromRGB(255, 236, 214) },
	[1] = { Color3.fromRGB(120, 196, 255), Color3.fromRGB(34, 98, 222), Color3.fromRGB(222, 240, 255) },
}
BubbleLayer.POOL_SPARE = 8
BubbleLayer.Z = 30

type Gui = {
	btn: TextButton,
	scale: UIScale,
	grad: UIGradient,
	rim: UIStroke,
	shine: Frame,
	value: TextLabel,
	vstroke: UIStroke,
	kind: number,
	text: string?,
	vis: boolean,
	x: number,
	y: number,
	px: number,
	s: number,
	t: number,
	--- the bubble shown (set while in use)
	id: number,
	hover: boolean,
	pressed_at: number,
	sent_at: number,
}
type Entry = {
	id: number,
	g: Gui,
	tile: number,
	expire: number,
	t0: number,
	--- set once it is going: when, and whether it was collected
	die_t: number?,
	popped: boolean,
	phase: number,
}

local function back_out(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	local u = t - 1
	return 1 + c3 * u * u * u + c1 * u * u
end

function BubbleLayer.new(parent: Instance, view: any)
	local self = setmetatable({}, BubbleLayer) :: any
	local root = Instance.new("Frame")
	root.Name = "Bubbles"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = BubbleLayer.Z
	root.Parent = parent
	self.root = root
	self.view = view
	self._state = nil :: any
	--- id -> its entry (while shown, the dying ones included)
	self._live = {} :: { [number]: Entry }
	self._pool = {} :: { Gui }
	return self
end

function BubbleLayer.bind(self: any, state: any)
	self:unbind()
	self._state = state
	self:_sync(false)
end

function BubbleLayer.unbind(self: any)
	self._state = nil
	for id, e in self._live do
		self:_release(e.g)
		self._live[id] = nil
	end
end

function BubbleLayer.destroy(self: any)
	self:unbind()
	for _, g in self._pool do
		g.btn:Destroy()
	end
	table.clear(self._pool)
	self.root:Destroy()
end

--- A state (re)loaded: the bubbles are those of state.bubbles now.
function BubbleLayer.on_snapshot(self: any)
	for id, e in self._live do
		self:_release(e.g)
		self._live[id] = nil
	end
	self:_sync(true)
end

--- Shows every bubble of the state that has no entry yet (`pop_in`: with its pop-in).
function BubbleLayer._sync(self: any, pop_in: boolean)
	local st = self._state
	if st == nil or st.bubbles == nil then
		return
	end
	for id, b in st.bubbles do
		if self._live[id] == nil then
			self:_add(b, pop_in)
		end
	end
end

--- GameState.bubble_added(id).
function BubbleLayer.on_bubble_added(self: any, id: number)
	local st = self._state
	local b = if st ~= nil and st.bubbles ~= nil then st.bubbles[id] else nil
	if b ~= nil and self._live[id] == nil then
		self:_add(b, true)
	end
end

--- GameState.bubble_removed(id, popped) (fired while the bubble is still in state.bubbles).
function BubbleLayer.on_bubble_removed(self: any, id: number, popped: boolean?)
	local e = self._live[id]
	if e ~= nil and e.die_t == nil then
		e.die_t = FrameClock.now()
		e.popped = popped == true
		e.g.btn.Active = false
	end
end

function BubbleLayer._add(self: any, b: any, pop_in: boolean)
	local g = self:_acquire(if b.kind == 1 then 1 else 0)
	g.id = b.id
	g.hover = false
	g.pressed_at = -1
	g.sent_at = -1
	g.btn.Active = true
	local text = "+" .. tostring(math.floor(tonumber(b.value) or 0))
	if g.text ~= text then
		g.text = text
		g.value.Text = text
	end
	local now = FrameClock.now()
	self._live[b.id] = {
		id = b.id,
		g = g,
		tile = b.tile,
		expire = tonumber(b.expire_tick) or math.huge,
		t0 = if pop_in then now else now - BubbleLayer.POP_IN_S,
		die_t = nil,
		popped = false,
		-- (each its own phase, so bubbles close together do not bob in step)
		phase = (b.id * 0.618034) % 1 * math.pi * 2,
	}
end

-- ---------------------------------------------------------------------------------------------
-- Pool
-- ---------------------------------------------------------------------------------------------

function BubbleLayer._paint(_self: any, g: Gui, kind: number)
	g.kind = kind
	local c = BubbleLayer.KINDS[kind] or BubbleLayer.KINDS[0]
	g.grad.Color = ColorSequence.new(c[1], c[2])
	g.rim.Color = c[3]
	g.vstroke.Color = c[2]:Lerp(Color3.new(0, 0, 0), 0.45)
end

function BubbleLayer._acquire(self: any, kind: number): Gui
	local g = table.remove(self._pool)
	if g ~= nil then
		if g.kind ~= kind then
			self:_paint(g, kind)
		end
		return g
	end
	local btn = Instance.new("TextButton")
	btn.Name = "Bubble"
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.AutoButtonColor = false
	btn.BackgroundColor3 = Color3.new(1, 1, 1)
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.Active = true
	btn.Selectable = false
	btn.ZIndex = BubbleLayer.Z
	btn.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = btn
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Parent = btn
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Thickness = 2
	rim.Parent = btn
	local scale = Instance.new("UIScale")
	scale.Parent = btn
	-- a soft highlight up and left
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(0.34, 0.3)
	shine.Size = UDim2.fromScale(0.32, 0.22)
	shine.Rotation = -30
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.45
	shine.BorderSizePixel = 0
	shine.Active = false
	shine.ZIndex = BubbleLayer.Z + 1
	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0.5, 0)
	sc.Parent = shine
	shine.Parent = btn
	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.AnchorPoint = Vector2.new(0.5, 0.5)
	value.Position = UDim2.fromScale(0.5, 0.54)
	value.Size = UDim2.fromScale(1, 0.62)
	value.BackgroundTransparency = 1
	value.FontFace = BubbleLayer.FONT
	value.TextScaled = true
	value.TextColor3 = Color3.new(1, 1, 1)
	value.Active = false
	value.ZIndex = BubbleLayer.Z + 2
	local vstroke = Instance.new("UIStroke")
	vstroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	vstroke.LineJoinMode = Enum.LineJoinMode.Round
	vstroke.Thickness = 1.5
	vstroke.Parent = value
	value.Parent = btn
	btn.Parent = self.root
	g = {
		btn = btn,
		scale = scale,
		grad = grad,
		rim = rim,
		shine = shine,
		value = value,
		vstroke = vstroke,
		kind = -1,
		text = nil,
		vis = false,
		x = math.huge,
		y = math.huge,
		px = -1,
		s = -1,
		t = -1,
		id = -1,
		hover = false,
		pressed_at = -1,
		sent_at = -1,
	}
	local gg = g :: Gui
	self:_paint(gg, kind)
	btn.MouseEnter:Connect(function()
		gg.hover = true
	end)
	btn.MouseLeave:Connect(function()
		gg.hover = false
	end)
	btn.Activated:Connect(function()
		self:_press(gg)
	end)
	return gg
end

function BubbleLayer._release(self: any, g: Gui)
	g.id = -1
	g.hover = false
	if #self._pool >= BubbleLayer.POOL_SPARE then
		g.btn:Destroy()
		return
	end
	if g.vis then
		g.vis = false
		g.btn.Visible = false
	end
	table.insert(self._pool, g)
end

--- A press on a bubble: MapView.bubble_clicked(id), once (DEBOUNCE_S), not for one already going and
--- not on the title screen's backdrop.
function BubbleLayer._press(self: any, g: Gui)
	local id = g.id
	local e = self._live[id]
	if e == nil or e.die_t ~= nil or self._state == nil then
		return
	end
	local view = self.view
	if view == nil or view._attract then
		return
	end
	local now = FrameClock.now()
	g.pressed_at = now
	if g.sent_at >= 0 and now - g.sent_at < BubbleLayer.DEBOUNCE_S then
		return
	end
	g.sent_at = now
	local sig = view.bubble_clicked
	if sig ~= nil then
		sig:Fire(id)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------------------------

function BubbleLayer.tick(self: any, _dt: number)
	local st = self._state
	if st == nil or next(self._live) == nil then
		return
	end
	local cam = self.view.rig
	local now = FrameClock.now()
	local rt = st.render_tick or st.tick or 0
	local W = st.map.W or Defs.W
	local k = tonumber(st.map and st.map.k_lin) or Rules.K_LIN or 1
	local zoom = cam.scale / k
	local base = math.clamp(
		BubbleLayer.BASE_PX * (zoom / BubbleLayer.REF_ZOOM) ^ BubbleLayer.ZOOM_EXP,
		BubbleLayer.MIN_PX,
		BubbleLayer.MAX_PX
	)
	local px = math.round(base)
	for id, e in self._live do
		local g = e.g
		-- a bubble the state no longer has (and no event said so): it fades like one that ran out
		if e.die_t == nil and (st.bubbles == nil or st.bubbles[id] == nil) then
			e.die_t = now
			g.btn.Active = false
		end
		local s, tr = 1.0, 0.0
		local bob_hz, pulse = BubbleLayer.BOB_HZ, 0.0
		local die_t = e.die_t
		if die_t ~= nil then
			local dur = if e.popped then BubbleLayer.POP_S else BubbleLayer.FADE_S
			local u = (now - die_t) / dur
			if u >= 1 then
				self:_release(g)
				self._live[id] = nil
				continue
			end
			local ease = 1 - (1 - u) * (1 - u)
			if e.popped then
				s = 1 + BubbleLayer.POP_SCALE * ease
				tr = u * u
			else
				s = 1 - 0.3 * ease
				tr = ease
			end
		else
			local u = (now - e.t0) / BubbleLayer.POP_IN_S
			if u < 1 then
				s = math.max(0.05, back_out(math.max(u, 0)))
			end
			local left = e.expire - rt
			if left < BubbleLayer.URGENT_TICKS then
				bob_hz = BubbleLayer.URGENT_HZ
				pulse = 0.5 + 0.5 * math.sin(now * math.pi * 2 * BubbleLayer.URGENT_HZ)
				tr = 0.25 * pulse
			end
			if g.hover then
				s *= BubbleLayer.HOVER_SCALE
			end
			if g.pressed_at >= 0 and now - g.pressed_at < BubbleLayer.PRESS_S then
				s *= 0.88
			end
		end
		local tile = e.tile
		local x, y = cam:map_to_screen(tile % W + 0.5, tile // W + 0.5)
		y -= px * BubbleLayer.LIFT
		if die_t == nil then
			y += math.sin(now * math.pi * 2 * bob_hz + e.phase) * BubbleLayer.BOB_PX
		end
		local btn = g.btn
		local on = cam:on_screen(x, y, px)
		if g.vis ~= on then
			g.vis = on
			btn.Visible = on
		end
		if not on then
			continue
		end
		local rx, ry = math.round(x), math.round(y)
		if g.x ~= rx or g.y ~= ry then
			g.x, g.y = rx, ry
			btn.Position = UDim2.fromOffset(rx, ry)
		end
		if g.px ~= px then
			g.px = px
			btn.Size = UDim2.fromOffset(px, px)
			g.rim.Thickness = math.max(1.5, px * 0.06)
			g.vstroke.Thickness = math.max(1, px * 0.045)
		end
		local sq = math.round(s * 100) / 100
		if g.s ~= sq then
			g.s = sq
			g.scale.Scale = sq
		end
		local tq = math.round(tr * 50) / 50
		if g.t ~= tq then
			g.t = tq
			btn.BackgroundTransparency = tq
			g.rim.Transparency = 0.1 + 0.9 * tq
			g.shine.BackgroundTransparency = 0.45 + 0.55 * tq
			g.value.TextTransparency = tq
			g.vstroke.Transparency = tq
		end
	end
end

--- The bubble drawn nearest `pos` (viewport px) within `radius_px`, or -1 (for a UI that wants to
--- route a tap itself; the buttons already take their own).
function BubbleLayer.bubble_at_screen(self: any, pos: Vector2, radius_px: number): number
	local best, best_d = -1, radius_px
	for id, e in self._live do
		local g = e.g
		if e.die_t == nil and g.vis then
			local d = (Vector2.new(g.x, g.y) - pos).Magnitude
			if d <= best_d then
				best, best_d = id, d
			end
		end
	end
	return best
end

return BubbleLayer
