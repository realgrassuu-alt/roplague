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
local TweenService = game:GetService("TweenService")
--- RoPlague's glyphs (Assets/PlagueIcons): a DNA bubble is a glowing, spinning virus; a cure one a syringe
local ICONS: any = (function()
	local ok, m = pcall(function()
		return require(Airfront:WaitForChild("Assets"):WaitForChild("PlagueIcons")) :: any
	end)
	return if ok and type(m) == "table" then m else {}
end)()
local VIRUS: string = ICONS.virus or ""
local CURE_ICON: string = ICONS.cure or VIRUS
local DNA_ICON: string = ICONS.dna or VIRUS

local BubbleLayer = {}
BubbleLayer.__index = BubbleLayer

BubbleLayer.BASE_PX = 58
BubbleLayer.MIN_PX = 46
BubbleLayer.MAX_PX = 80
--- A bubble never sits on a country's name or the line under it (NameLayer's plates): it is pushed
--- above the plate, and a thin stem runs from it down to the spot it is for. CLEAR_PX of air around.
BubbleLayer.CLEAR_PX = 5
--- Bubbles on one spot are set side by side: these multiples of a bubble's width, the first free one.
BubbleLayer.SPREAD = { 0, 1, -1, 2, -2, 3, -3 }
BubbleLayer.GLIDE = 10
BubbleLayer.REF_ZOOM = 2.0
BubbleLayer.ZOOM_EXP = 0.25
--- The bubble's centre sits this share of its size above its tile.
BubbleLayer.LIFT = 0.55
BubbleLayer.BOB_PX = 3.0
BubbleLayer.BOB_HZ = 0.6
BubbleLayer.URGENT_TICKS = 20
BubbleLayer.URGENT_HZ = 2.2
BubbleLayer.POP_IN_S = 0.3
BubbleLayer.POP_S = 0.42
BubbleLayer.POP_SCALE = 0.9
--- On a pop: this many particles fly out, and a shock ring grows to RING_POP times the bubble.
BubbleLayer.POP_SPARKS = 10
BubbleLayer.RING_POP = 2.6
--- The virus turns this many degrees a second; the ring around it pulses at RING_HZ.
BubbleLayer.SPIN_DPS = 40
BubbleLayer.RING_HZ = 1.1
BubbleLayer.FADE_S = 0.45
--- A press dips the bubble for PRESS_S; a second press within DEBOUNCE_S is not sent again.
BubbleLayer.PRESS_S = 0.12
BubbleLayer.DEBOUNCE_S = 0.4
BubbleLayer.HOVER_SCALE = 1.1
--- A bubble that grew (another added to it) swells by PUNCH_SCALE over PUNCH_S.
BubbleLayer.PUNCH_S = 0.4
BubbleLayer.PUNCH_SCALE = 0.45
BubbleLayer.FONT = Font.fromId(12187365977, Enum.FontWeight.Bold)
--- (top, bottom) of each kind's gradient, and its rim
BubbleLayer.KINDS = {
	[0] = { Color3.fromRGB(255, 156, 66), Color3.fromRGB(226, 52, 30), Color3.fromRGB(255, 236, 214) },
	[1] = { Color3.fromRGB(120, 196, 255), Color3.fromRGB(34, 98, 222), Color3.fromRGB(222, 240, 255) },
	-- a hotspot over an uninfected neighbour: pop it and the country is infected
	[2] = { Color3.fromRGB(255, 96, 96), Color3.fromRGB(196, 18, 30), Color3.fromRGB(255, 232, 232) },
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
		local gg = g :: any
		gg.stem:Destroy()
		gg.pin:Destroy()
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

--- GameState.bubble_added(id). A bubble already shown came again: another was added to it (the
--- sim's cap, PlagueRules.MAX_DNA_BUBBLES): it shows its new value, lives on and gives a punch.
function BubbleLayer.on_bubble_added(self: any, id: number)
	local st = self._state
	local b = if st ~= nil and st.bubbles ~= nil then st.bubbles[id] else nil
	if b == nil then
		return
	end
	local e = self._live[id]
	if e == nil then
		self:_add(b, true)
	elseif e.die_t == nil then
		local text = "+" .. tostring(math.floor(tonumber(b.value) or 0))
		if e.g.text ~= text then
			e.g.text = text
			e.g.value.Text = text
		end
		e.expire = tonumber(b.expire_tick) or e.expire
		e.punch_t = FrameClock.now()
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
	local g = self:_acquire(if b.kind == 1 or b.kind == 2 then b.kind else 0)
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

function BubbleLayer._paint(_self: any, g: any, kind: number)
	g.kind = kind
	local c = BubbleLayer.KINDS[kind] or BubbleLayer.KINDS[0]
	g.glow.BackgroundColor3 = c[2]
	g.core.BackgroundColor3 = Color3.new(1, 1, 1)
	g.core_grad.Color = ColorSequence.new(c[1], c[2])
	g.ring_stroke.Color = c[1]
	g.pin.BackgroundColor3 = c[2]
	g.stem.BackgroundColor3 = c[3]
	g.icon.Image = if kind == 1 then CURE_ICON elseif kind == 2 then VIRUS else DNA_ICON
	g.icon.ImageColor3 = c[3]
	g.badge.BackgroundColor3 = Color3.fromRGB(228, 36, 44)
	g.badge_stroke.Color = Color3.new(1, 1, 1)
	g.color = c[1]
end

local function circle(name: string, parent: Instance, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = z
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = f
	f.Parent = parent
	return f
end

function BubbleLayer._acquire(self: any, kind: number): any
	local g = table.remove(self._pool)
	if g ~= nil then
		if g.kind ~= kind then
			self:_paint(g, kind)
		end
		return g
	end
	-- the button is only the press area; the bubble is drawn inside it
	local btn = Instance.new("TextButton")
	btn.Name = "Bubble"
	btn.AnchorPoint = Vector2.new(0.5, 0.5)
	btn.AutoButtonColor = false
	btn.BackgroundTransparency = 1
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.Active = true
	btn.Selectable = false
	btn.ZIndex = BubbleLayer.Z
	btn.Visible = false
	local scale = Instance.new("UIScale")
	scale.Parent = btn
	-- a soft glow, a drop shadow, a pulsing ring, a glossy core with a white rim and a highlight, and
	-- the glyph (DNA / syringe / virus) in it
	local glow = circle("Glow", btn, BubbleLayer.Z)
	glow.Size = UDim2.fromScale(1.6, 1.6)
	glow.BackgroundTransparency = 0.74
	local shadow = circle("Shadow", btn, BubbleLayer.Z)
	shadow.Position = UDim2.fromScale(0.5, 0.6)
	shadow.Size = UDim2.fromScale(0.9, 0.9)
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.62
	local ring = circle("Ring", btn, BubbleLayer.Z + 1)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	local ring_stroke = Instance.new("UIStroke")
	ring_stroke.Thickness = 2
	ring_stroke.Parent = ring
	local core = circle("Core", btn, BubbleLayer.Z + 1)
	core.Size = UDim2.fromScale(0.86, 0.86)
	core.BackgroundTransparency = 0
	local cg = Instance.new("UIGradient")
	cg.Rotation = 90
	cg.Parent = core
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = Color3.new(1, 1, 1)
	rim.Transparency = 0.1
	rim.Thickness = 2.5
	rim.Parent = core
	local gloss = circle("Gloss", btn, BubbleLayer.Z + 2)
	gloss.Position = UDim2.fromScale(0.38, 0.3)
	gloss.Size = UDim2.fromScale(0.34, 0.18)
	gloss.Rotation = -24
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.55
	local icon = Instance.new("ImageLabel")
	icon.Name = "Virus"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.52)
	icon.Size = UDim2.fromScale(0.6, 0.6)
	icon.BackgroundTransparency = 1
	icon.Active = false
	icon.ZIndex = BubbleLayer.Z + 3
	icon.Parent = btn
	-- the spot it is for, and a stem up to the bubble (it is lifted off any name in the way)
	local stem = Instance.new("Frame")
	stem.Name = "BubbleStem"
	stem.AnchorPoint = Vector2.new(0.5, 0.5)
	stem.BorderSizePixel = 0
	stem.BackgroundTransparency = 0.3
	stem.Active = false
	stem.Visible = false
	stem.ZIndex = BubbleLayer.Z - 2
	stem.Parent = self.root
	local pin = circle("BubblePin", self.root, BubbleLayer.Z - 1)
	pin.Size = UDim2.fromOffset(9, 9)
	pin.Visible = false
	local pin_stroke = Instance.new("UIStroke")
	pin_stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	pin_stroke.Color = Color3.new(1, 1, 1)
	pin_stroke.Thickness = 2
	pin_stroke.Parent = pin
	-- what it pays: a round red badge with a white rim in its top right corner
	local badge = Instance.new("TextLabel")
	badge.Name = "Value"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.86, 0.16)
	badge.Size = UDim2.fromScale(0.5, 0.5)
	badge.BorderSizePixel = 0
	badge.FontFace = BubbleLayer.FONT
	badge.TextScaled = true
	badge.TextColor3 = Color3.new(1, 1, 1)
	badge.Active = false
	badge.ZIndex = BubbleLayer.Z + 3
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = badge
	local badge_stroke = Instance.new("UIStroke")
	badge_stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	badge_stroke.Thickness = 2
	badge_stroke.Parent = badge
	local bp = Instance.new("UIPadding")
	bp.PaddingLeft = UDim.new(0.14, 0)
	bp.PaddingRight = UDim.new(0.14, 0)
	bp.PaddingTop = UDim.new(0.16, 0)
	bp.PaddingBottom = UDim.new(0.16, 0)
	bp.Parent = badge
	badge.Visible = false
	badge.Parent = btn
	btn.Parent = self.root
	g = {
		btn = btn,
		scale = scale,
		glow = glow,
		ring = ring,
		ring_stroke = ring_stroke,
		core = core,
		core_grad = cg,
		rim = rim,
		gloss = gloss,
		shadow = shadow,
		stem = stem,
		pin = pin,
		pin_stroke = pin_stroke,
		icon = icon,
		badge = badge,
		badge_stroke = badge_stroke,
		value = badge,
		kind = -1,
		color = Color3.new(1, 1, 1),
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
	local gg = g
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

--- A popped bubble bursts: a white flash, a shock ring and particles fly out from (x, y), in its colour.
function BubbleLayer._burst(self: any, x: number, y: number, px: number, col: Color3)
	local ring = circle("PopRing", self.root, BubbleLayer.Z + 4)
	ring.Position = UDim2.fromOffset(x, y)
	ring.Size = UDim2.fromOffset(px, px)
	ring.BackgroundTransparency = 1
	local st = Instance.new("UIStroke")
	st.Color = col
	st.Thickness = math.max(2, px * 0.08)
	st.Parent = ring
	local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, info, { Size = UDim2.fromOffset(px * BubbleLayer.RING_POP, px * BubbleLayer.RING_POP) }):Play()
	TweenService:Create(st, info, { Transparency = 1, Thickness = 1 }):Play()
	local flash = circle("PopFlash", self.root, BubbleLayer.Z + 4)
	flash.Position = UDim2.fromOffset(x, y)
	flash.Size = UDim2.fromOffset(px * 1.1, px * 1.1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 0.2
	TweenService:Create(flash, TweenInfo.new(0.25), { BackgroundTransparency = 1, Size = UDim2.fromOffset(px * 1.6, px * 1.6) }):Play()
	local n = BubbleLayer.POP_SPARKS
	for k = 1, n do
		local a = (k / n) * math.pi * 2 + math.random() * 0.5
		local r = px * (0.9 + math.random() * 0.9)
		local d = circle("PopSpark", self.root, BubbleLayer.Z + 4)
		local sz = math.max(4, px * (0.1 + math.random() * 0.08))
		d.Position = UDim2.fromOffset(x, y)
		d.Size = UDim2.fromOffset(sz, sz)
		d.BackgroundColor3 = col:Lerp(Color3.new(1, 1, 1), math.random() * 0.5)
		TweenService:Create(d, TweenInfo.new(0.5 + math.random() * 0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(x + math.cos(a) * r, y + math.sin(a) * r),
			Size = UDim2.fromOffset(2, 2),
			BackgroundTransparency = 1,
		}):Play()
		task.delay(0.75, function()
			d:Destroy()
		end)
	end
	task.delay(0.5, function()
		ring:Destroy()
		flash:Destroy()
	end)
end

--- What a pop (or a new country) paid: a dark pill "+N [DNA]" with an orange rim that springs up over
--- (x, y) (viewport px), rises and fades. It sits ABOVE the burst, so the flash never covers the number.
BubbleLayer.PAY_S = 1.15
BubbleLayer.PAY_RISE = 46
BubbleLayer.PAY_ORANGE = Color3.fromRGB(255, 170, 60)
function BubbleLayer.pay(self: any, x: number, y: number, amount: number, px: number?)
	local n = math.floor(amount * 10 + 0.5) / 10
	local txt = "+" .. (if n == math.floor(n) then tostring(math.floor(n)) else string.format("%.1f", n))
	local fs = math.clamp((px or BubbleLayer.BASE_PX) * 0.42, 17, 26)
	local pill = Instance.new("Frame")
	pill.Name = "DnaPay"
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.fromOffset(x, y)
	pill.AutomaticSize = Enum.AutomaticSize.XY
	pill.Size = UDim2.fromOffset(0, 0)
	pill.BackgroundColor3 = Color3.fromRGB(26, 14, 6)
	pill.BackgroundTransparency = 0.12
	pill.BorderSizePixel = 0
	pill.Active = false
	pill.ZIndex = BubbleLayer.Z + 6
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = BubbleLayer.PAY_ORANGE
	rim.Thickness = 2
	rim.Parent = pill
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, math.floor(fs * 0.45))
	pad.PaddingRight = UDim.new(0, math.floor(fs * 0.35))
	pad.PaddingTop = UDim.new(0, 3)
	pad.PaddingBottom = UDim.new(0, 3)
	pad.Parent = pill
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 3)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = pill
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, fs + 2)
	label.FontFace = BubbleLayer.FONT
	label.TextSize = fs
	label.Text = txt
	label.TextColor3 = Color3.new(1, 1, 1)
	label.LayoutOrder = 1
	label.ZIndex = BubbleLayer.Z + 7
	label.Parent = pill
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = DNA_ICON
	icon.ImageColor3 = BubbleLayer.PAY_ORANGE
	icon.Size = UDim2.fromOffset(fs + 2, fs + 2)
	icon.LayoutOrder = 2
	icon.ZIndex = BubbleLayer.Z + 7
	icon.Parent = pill
	local sc = Instance.new("UIScale")
	sc.Scale = 0.3
	sc.Parent = pill
	pill.Parent = self.root
	TweenService:Create(sc, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(pill, TweenInfo.new(BubbleLayer.PAY_S, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(x, y - BubbleLayer.PAY_RISE),
	}):Play()
	task.delay(BubbleLayer.PAY_S - 0.35, function()
		local out = TweenInfo.new(0.35)
		TweenService:Create(pill, out, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(rim, out, { Transparency = 1 }):Play()
		TweenService:Create(label, out, { TextTransparency = 1 }):Play()
		TweenService:Create(icon, out, { ImageTransparency = 1 }):Play()
	end)
	task.delay(BubbleLayer.PAY_S + 0.05, function()
		pill:Destroy()
	end)
end

function BubbleLayer._release(self: any, g: Gui)
	g.id = -1
	g.hover = false
	local gg = g :: any
	gg.stem.Visible = false
	gg.pin.Visible = false
	if #self._pool >= BubbleLayer.POOL_SPARE then
		g.btn:Destroy()
		gg.stem:Destroy()
		gg.pin:Destroy()
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

function BubbleLayer.tick(self: any, dt: number)
	local st = self._state
	if st == nil or next(self._live) == nil then
		return
	end
	local cam = self.view.rig
	local labels = self.view.layers and self.view.layers.labels
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
	-- (where this frame's bubbles went: one landing on another moves aside, BubbleLayer.SPREAD)
	local placed = {}
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
				tr = math.min(1, u * 1.6)
				if not e.burst and g.vis then
					e.burst = true
					self:_burst(g.x, g.y, g.px, g.color)
					local v = tonumber(string.sub(g.text or "", 2)) or 0
					-- (not on the title screen's backdrop: the bot's pops there are not the player's DNA)
					if v > 0 and not self.view._attract then
						self:pay(g.x, g.y - g.px * 0.55, v, g.px)
					end
				end
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
			-- (something was added to it: a quick swell)
			local pt = e.punch_t
			if pt ~= nil then
				local pu = (now - pt) / BubbleLayer.PUNCH_S
				if pu < 1 then
					s *= 1 + BubbleLayer.PUNCH_SCALE * math.sin(pu * math.pi) * (1 - pu)
				else
					e.punch_t = nil
				end
			end
		end
		local tile = e.tile
		local ax, ay = cam:map_to_screen(tile % W + 0.5, tile // W + 0.5)
		-- (lifted off its spot, and further up when a country's name or its line is in the way)
		local by = ay - px * BubbleLayer.LIFT
		local plates = labels and labels._plates
		if plates ~= nil then
			local half = px * 0.5 + BubbleLayer.CLEAR_PX
			for _ = 1, 4 do
				local hit = false
				for _, pl in plates do
					if pl.shown then
						local r = pl.rect
						if ax + half > r[1] and ax - half < r[3] and by + half > r[2] and by - half < r[4] then
							by = r[2] - half
							hit = true
						end
					end
				end
				if not hit then
					break
				end
			end
		end
		-- (and aside, when another bubble already sits there)
		local step = px + 6
		local side = 0
		for _, k in BubbleLayer.SPREAD do
			local cx = ax + k * step
			local clash = false
			for _, r in placed do
				if math.abs(cx - r[1]) < px + 2 and math.abs(by - r[2]) < px + 2 then
					clash = true
					break
				end
			end
			if not clash then
				side = k * step
				break
			end
		end
		table.insert(placed, { ax + side, by })
		local want = by - ay
		local oy, ox = e.oy, e.ox
		if oy == nil or die_t ~= nil then
			oy = if oy == nil then want else oy
			ox = if ox == nil then side else ox
		else
			local a = math.min(1, dt * BubbleLayer.GLIDE)
			oy += (want - oy) * a
			ox = (ox or side) + (side - (ox or side)) * a
		end
		e.oy, e.ox = oy, ox
		local x, y = ax + ox, ay + oy
		if die_t == nil then
			y += math.sin(now * math.pi * 2 * bob_hz + e.phase) * BubbleLayer.BOB_PX
		end
		local btn = g.btn
		local on = cam:on_screen(x, y, px)
		if g.vis ~= on then
			g.vis = on
			btn.Visible = on
		end
		-- the spot and its stem (not for a bubble already going)
		local gg = g :: any
		local show_pin = on and die_t == nil
		if gg.pin.Visible ~= show_pin then
			gg.pin.Visible = show_pin
		end
		local sx, sy = x - ax, (y + px * 0.4) - ay
		local len = math.sqrt(sx * sx + sy * sy)
		local show_stem = show_pin and len > 4 and sy < 0
		if gg.stem.Visible ~= show_stem then
			gg.stem.Visible = show_stem
		end
		if show_pin then
			gg.pin.Position = UDim2.fromOffset(math.round(ax), math.round(ay))
			if show_stem then
				gg.stem.Position = UDim2.fromOffset(math.round(ax + sx * 0.5), math.round(ay + sy * 0.5))
				gg.stem.Size = UDim2.fromOffset(2, math.round(len))
				gg.stem.Rotation = math.deg(math.atan2(sx, -sy))
			end
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
			g.ring_stroke.Thickness = math.max(1.5, px * 0.06)
			gg.rim.Thickness = math.max(2, px * 0.05)
			g.badge_stroke.Thickness = math.max(1.5, px * 0.05)
		end
		-- the virus turns, the ring breathes out and back
		g.icon.Rotation = if g.kind == 0
			then math.sin(now * 2.2 + e.phase) * 14
			else (now * BubbleLayer.SPIN_DPS + e.phase * 57) % 360
		local rp = (now * BubbleLayer.RING_HZ + e.phase) % 1
		g.ring.Size = UDim2.fromScale(1 + 0.45 * rp, 1 + 0.45 * rp)
		g.ring_stroke.Transparency = math.max(tr, 0.15 + 0.85 * rp)
		local sq = math.round(s * 100) / 100
		if g.s ~= sq then
			g.s = sq
			g.scale.Scale = sq
		end
		local tq = math.round(tr * 50) / 50
		if g.t ~= tq then
			g.t = tq
			g.glow.BackgroundTransparency = 0.78 + 0.22 * tq
			g.core.BackgroundTransparency = tq
			gg.rim.Transparency = 0.1 + 0.9 * tq
			gg.gloss.BackgroundTransparency = 0.55 + 0.45 * tq
			gg.shadow.BackgroundTransparency = 0.62 + 0.38 * tq
			g.icon.ImageTransparency = tq
			g.badge.BackgroundTransparency = tq
			g.badge.TextTransparency = tq
			g.badge_stroke.Transparency = tq
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
