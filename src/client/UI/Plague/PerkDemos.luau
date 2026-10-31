--!nonstrict
-- RoPlague: the shop's moving pictures for the plague perks (Data/Arsenal), in RoWorld's Arsenal style:
-- each perk plays a short looping scene of what it does, on UI/ArsenalDemo's stage (its pieces: _img,
-- _fx, _text, _show, _at, _kick; `self.parts`, `self.W` x `self.H` px, `self.u`). install() adds a
-- _build_<key> / _step_<key> pair for each perk to ArsenalDemo; the Arsenal plays any item that has one.
--
-- The ground is LIVE: a real piece of the game's world (Assets/PerkMaps, tools/assets/make_perk_maps.py)
-- whose infection moves frame by frame with what the perk does, drawn pixel-crisp like the match. Every
-- scene has ONE big caption along the top saying what the perk does, and the picture shows that:
--   head_start      the DNA counter starts 6 higher; strands fly into it; France's plague takes off
--   bubble_magnet   DNA bubbles rise over West Africa's infected countries, more and more, and pop
--   super_spreader  patient zero in India, and the country floods red at once: 250 sick
--   sea_legs        a ship sails from Brazil's coast to Nigeria's and the plague lands there
--   gene_bank       an evolution hex at 10 DNA stamped down to 9, over China's growing plague
--   slow_science    two cure bars over North America: the normal one fills, the slowed one lags
--   mutagen         a locked hex over East Africa flashes and flips to evolved
--   auto_pop        DNA, cure and hotspot bubbles come up over West Africa and pop by themselves
--   stars2x         (ArsenalDemo's payout scene) on a live map instead of RoWorld's war map
local UITheme = require("../UITheme")

local PerkDemos = {}

local WHITE = Color3.new(1, 1, 1)
local DNA = Color3.fromRGB(255, 150, 60)
local RED = Color3.fromRGB(235, 52, 48)
local INK = Color3.fromRGB(10, 12, 26)
local FONT_B = Font.fromId(12187365977, Enum.FontWeight.Bold)

local IS_ROBLOX = typeof(game) == "Instance"
local MAPS: any = (function()
	local ok, m = pcall(function()
		if IS_ROBLOX then
			return require((game :: any):GetService("ReplicatedStorage"):WaitForChild("Airfront").Assets.PerkMaps)
		end
		return (require :: any)("../../../shared/Assets/PerkMaps")
	end)
	return if ok and type(m) == "table" then m else nil
end)()

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function ramp(t: number, a: number, b: number): number
	return clamp01((t - a) / (b - a))
end

local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

local function ease_out(k: number): number
	return 1 - (1 - k) ^ 3
end

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in props do
		(i :: any)[k] = v
	end
	if parent then
		i.Parent = parent
	end
	return i
end

local function fade(l: TextLabel, a: number)
	l.TextTransparency = a
	local s = l:FindFirstChildOfClass("UIStroke")
	if s ~= nil then
		s.Transparency = math.max(a, 0.15)
	end
end

local function icon(name: string): string
	return UITheme.icon(name) or ""
end

--- What each perk does, in a few words: the caption along the top of its scene.
PerkDemos.CAPTIONS = {
	head_start = "START WITH +6 DNA",
	bubble_magnet = "MORE DNA BUBBLES",
	super_spreader = "START WITH 250 SICK",
	sea_legs = "SHIPS FROM THE START",
	gene_bank = "EVOLVING COSTS 15% LESS",
	slow_science = "THE CURE TAKES LONGER",
	mutagen = "A FREE EVOLUTION EACH MATCH",
	auto_pop = "BUBBLES POP BY THEMSELVES",
}

-- ---------------------------------------------------------------------------------------------
-- The live ground
-- ---------------------------------------------------------------------------------------------

--- The scene's ground: its real map frames, cropped to the scene (pixel-crisp), under a light wash in
--- the perk's colour so what is drawn on top reads.
local function ground(self: any, key: string, tint: Color3)
	local sc = MAPS and MAPS.scenes[key]
	local p = self.parts
	-- (under the Arsenal's clipping group, like ArsenalDemo._map: a pixelated image inside the group
	-- drew nothing on an iPhone)
	local map = new("ImageLabel", {
		Name = "LiveMap",
		BackgroundColor3 = Color3.fromRGB(28, 64, 98),
		BorderSizePixel = 0,
		Image = "",
		ScaleType = Enum.ScaleType.Crop,
		ResampleMode = Enum.ResamplerMode.Pixelated,
		Size = if self.under ~= nil then UDim2.fromOffset(self.W, self.H) else UDim2.fromScale(1, 1),
		ZIndex = if self.under ~= nil then 40 else 5,
	}, self.under or self.root)
	if self.under ~= nil and self.corner ~= nil then
		new("UICorner", { CornerRadius = UDim.new(0, self.corner) }, map)
	end
	local wash = new("Frame", {
		Name = "Wash",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
	}, self.root)
	new("UIGradient", {
		Color = ColorSequence.new(tint:Lerp(Color3.new(0, 0, 0), 0.45), Color3.new(0, 0, 0)),
		Transparency = NumberSequence.new(0.55, 0.62),
		Rotation = 90,
	}, wash)
	p.map, p.map_scene, p.map_frame = map, sc, 0
	self:_frame(1)
end

--- Shows frame `f` (1..8) of the scene's map.
function PerkDemos._frame(self: any, f: number)
	local p = self.parts
	local sc = p.map_scene
	if sc == nil or MAPS == nil then
		return
	end
	f = math.clamp(math.floor(f), 1, #sc.frames)
	if p.map_frame == f then
		return
	end
	p.map_frame = f
	local fr = sc.frames[f]
	p.map.Image = MAPS.atlases[fr[1]] or ""
	p.map.ImageRectOffset = Vector2.new(fr[2], fr[3])
	p.map.ImageRectSize = MAPS.frame
end

--- A point of the scene's map (MAPS points, fractions of a frame) as fractions of the scene, where the
--- crop put it; `fallback` without one.
local function point(self: any, name: string, fallback: Vector2): Vector2
	local sc = self.parts.map_scene
	local v = sc and sc.points and sc.points[name]
	if v == nil or MAPS == nil then
		return fallback
	end
	local fw, fh = MAPS.frame.X, MAPS.frame.Y
	local W, H = self.W, self.H
	if W / H >= fw / fh then
		-- (the frame fills the width; its top and bottom are cut)
		local shown = (W * fh / fw)
		return Vector2.new(v.X, 0.5 + (v.Y - 0.5) * shown / H)
	end
	local shown = (H * fw / fh)
	return Vector2.new(0.5 + (v.X - 0.5) * shown / W, v.Y)
end

--- The map's frame for a growth that runs from t = a to t = b of the loop (held at each end).
local function grow(self: any, t: number, a: number, b: number)
	self:_frame(1 + ramp(t, a, b) * 7.999)
end

--- A dark pill so a line of text reads over the map.
local function plate(self: any, name: string, z: number): Frame
	local f = new("Frame", {
		Name = name,
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = z,
	}, self.root)
	new("UICorner", { CornerRadius = UDim.new(0, 10 * self.u) }, f)
	return f
end

local function shape(self: any, name: string, color: Color3, z: number, round: boolean?): Frame
	local f = new("Frame", {
		Name = name,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		ZIndex = z,
	}, self.root)
	new("UICorner", { CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0, 10 * self.u) }, f)
	return f
end

local function put(self: any, g: GuiObject, fx: number, fy: number, w: number, h: number?)
	g.Visible = true
	self:_at(g, fx, fy, w, h or w)
end

--- A pulsing ring on a spot of the map (patient zero, a landing).
local function spot(self: any, name: string, col: Color3)
	return self:_fx(name, "ring", 9, col)
end

local function show_spot(self: any, g: ImageLabel, at: Vector2, t: number, period: number)
	local k = (t % period) / period
	local d = self.H * (0.12 + 0.3 * k)
	self:_show(g, at.X, at.Y, d, d, k)
end

local function caption(self: any, text: string)
	local u = self.u
	local fs = math.clamp(self.H * 0.115, 11 * u, 17 * u)
	local l = self:_text("Caption", text, fs, WHITE, 20)
	l.BackgroundColor3 = INK
	l.BackgroundTransparency = 0.15
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, l)
	new("UIStroke", { Color = DNA, Thickness = 1.5 * u, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, l)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 12 * u),
		PaddingRight = UDim.new(0, 12 * u),
		PaddingTop = UDim.new(0, 4 * u),
		PaddingBottom = UDim.new(0, 4 * u),
	}, l)
	self.parts.caption = l
end

local function place_caption(self: any, t: number)
	local l = self.parts.caption
	if l == nil then
		return
	end
	self:_at(l, 0.5, 0.13)
	l.Rotation = math.sin(t * 1.8) * 1.2
end

--- The bubbles the way the match draws them (BubbleLayer.KINDS): DNA, cure, hotspot.
local BUBBLE_KINDS = {
	[0] = { Color3.fromRGB(255, 156, 66), Color3.fromRGB(226, 52, 30), Color3.fromRGB(255, 236, 214), "dna", DNA },
	[1] = { Color3.fromRGB(120, 196, 255), Color3.fromRGB(34, 98, 222), Color3.fromRGB(222, 240, 255), "cure", Color3.fromRGB(110, 190, 255) },
	[2] = { Color3.fromRGB(255, 96, 96), Color3.fromRGB(196, 18, 30), Color3.fromRGB(255, 232, 232), "infect", RED },
}

--- A bubble the way the match draws it (BubbleLayer): glow, gradient core, white rim, the glyph.
--- `kind`: 0 DNA (default), 1 cure, 2 hotspot.
local function bubble(self: any, name: string, kind: number?): any
	local k = BUBBLE_KINDS[kind or 0]
	local g = {}
	g.glow = self:_fx(name .. "Glow", "glow", 7, k[5])
	g.core = shape(self, name, WHITE, 8, true)
	new("UIGradient", { Color = ColorSequence.new(k[1], k[2]), Rotation = 90 }, g.core)
	new("UIStroke", { Color = WHITE, Thickness = 2 * self.u, Transparency = 0.1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, g.core)
	g.glyph = self:_img(name .. "Glyph", icon(k[4]), 9, k[3])
	g.ring = self:_fx(name .. "Pop", "ring", 9, k[5])
	g.pay = self:_text(name .. "Pay", "+2", math.clamp(self.H * 0.11, 10 * self.u, 15 * self.u), Color3.fromRGB(255, 220, 140), 10)
	return g
end

local function show_bubble(self: any, g: any, fx: number, fy: number, sz: number, wob: number)
	self:_show(g.glow, fx, fy, sz * 1.7, sz * 1.7, 0.5)
	put(self, g.core, fx, fy, sz * 0.86)
	self:_show(g.glyph, fx, fy, sz * 0.52, sz * 0.52)
	g.glyph.Rotation = wob
end

local function hide_bubble(g: any)
	g.glow.Visible, g.core.Visible, g.glyph.Visible = false, false, false
end

-- Head Start ------------------------------------------------------------------------------------
function PerkDemos._build_head_start(self: any, _it: any)
	local p = self.parts
	local H, u = self.H, self.u
	ground(self, "head_start", Color3.fromRGB(150, 76, 14))
	p.spot = spot(self, "Zero", RED)
	p.panel = plate(self, "Counter", 7)
	p.halo = self:_fx("Halo", "glow", 8, DNA)
	p.dna = self:_img("Dna", icon("dna"), 9, DNA)
	local fs = math.clamp(H * 0.24, 14 * u, 30 * u)
	p.count = self:_text("Count", "6", fs, WHITE, 10)
	p.fly = {}
	for i = 1, 6 do
		p.fly[i] = self:_img("Fly" .. i, icon("dna"), 11, Color3.fromRGB(255, 200, 120))
	end
end

function PerkDemos._step_head_start(self: any, t: number)
	local p = self.parts
	local H, W = self.H, self.W
	local zero = point(self, "zero", Vector2.new(0.6, 0.55))
	grow(self, t, 1.6, 4.0)
	show_spot(self, p.spot, zero, t, 1.4)
	put(self, p.panel, 0.2, 0.6, W * 0.3, H * 0.42)
	local d = H * 0.3
	self:_show(p.dna, 0.12, 0.6, d, d)
	p.dna.Rotation = math.sin(t * 2) * 8
	self:_show(p.halo, 0.12, 0.6, d * 1.9, d * 1.9, 0.5)
	local got = 0
	for i, g in p.fly do
		local t0 = 0.5 + i * 0.12
		local k = (t - t0) / 0.5
		if k >= 0 and k <= 1 then
			local e = ease_out(k)
			self:_show(g, lerp(0.5, 0.25, e), lerp(0.3, 0.6, e) - math.sin(k * math.pi) * 0.12, H * 0.13, H * 0.13, k * 0.6)
			g.Rotation = k * 200
		else
			g.Visible = false
		end
		if k >= 1 then
			got += 1
		end
	end
	p.count.Text = tostring(6 + got)
	self:_at(p.count, 0.26, 0.6)
	if got > 0 and got < 6 then
		self:_kick(t, 0.5 + got * 0.12 + 0.5, 1, 0.15)
	end
end

-- Bubble Magnet ---------------------------------------------------------------------------------
local BUBBLE_PTS = { "b1", "b2", "b3", "b4", "b5", "b1", "b3", "b2", "b4" }
function PerkDemos._build_bubble_magnet(self: any, _it: any)
	local p = self.parts
	ground(self, "bubble_magnet", Color3.fromRGB(140, 30, 24))
	p.bubbles = {}
	for i = 1, #BUBBLE_PTS do
		p.bubbles[i] = bubble(self, "Bubble" .. i)
	end
end

function PerkDemos._step_bubble_magnet(self: any, t: number)
	local p = self.parts
	local H = self.H
	grow(self, t, 0.3, 4.2)
	local life = 1.5
	for i, g in p.bubbles do
		-- more and more of them as the loop goes on: the magnet pulls them up
		local t0 = (i - 1) * 0.36
		local k = (t - t0) / life
		local at = point(self, BUBBLE_PTS[i], Vector2.new(0.2 + 0.08 * i, 0.6))
		-- (kept under the caption band, wherever the country's point is)
		local base = math.max(at.Y, 0.5)
		local top = math.max(base - 0.18, 0.4)
		if k >= 0 and k < 0.8 then
			local rise = ease_out(k / 0.8)
			local sz = H * 0.24 * (0.5 + 0.5 * ramp(k, 0, 0.18))
			show_bubble(self, g, at.X, lerp(base - 0.04, top, rise), sz, math.sin(t * 2.2 + i) * 14)
			g.ring.Visible, g.pay.Visible = false, false
		elseif k >= 0.8 and k < 1.25 then
			hide_bubble(g)
			local pk = (k - 0.8) / 0.45
			local d = H * (0.2 + 0.5 * pk)
			self:_show(g.ring, at.X, top, d, d, pk)
			g.pay.Visible = true
			self:_at(g.pay, at.X, math.max(top - 0.08 - 0.08 * pk, 0.3))
			fade(g.pay, pk)
		else
			hide_bubble(g)
			g.ring.Visible, g.pay.Visible = false, false
		end
	end
end

-- Super Spreader --------------------------------------------------------------------------------
function PerkDemos._build_super_spreader(self: any, _it: any)
	local p = self.parts
	local H, u = self.H, self.u
	ground(self, "super_spreader", Color3.fromRGB(90, 40, 120))
	p.wave = spot(self, "Wave", RED)
	p.spot = spot(self, "Zero", WHITE)
	p.walker = self:_img("Walker", icon("carrier"), 9, RED)
	p.panel = plate(self, "CountPlate", 10)
	local fs = math.clamp(H * 0.14, 12 * u, 19 * u)
	p.count = self:_text("Count", "1 SICK", fs, Color3.fromRGB(255, 120, 110), 11)
end

function PerkDemos._step_super_spreader(self: any, t: number)
	local p = self.parts
	local H, W = self.H, self.W
	local zero = point(self, "zero", Vector2.new(0.5, 0.55))
	local k = ramp(t, 0.5, 2.4)
	self:_frame(1 + k * 7.999)
	show_spot(self, p.spot, zero, t, 1.1)
	local wk = (t - 0.5) / 0.8
	if wk >= 0 and wk < 1 then
		local d = H * (0.2 + 1.3 * wk)
		self:_show(p.wave, zero.X, zero.Y, d, d, wk)
	else
		p.wave.Visible = false
	end
	local wd = H * 0.24
	self:_show(p.walker, zero.X, zero.Y - 0.14 - math.abs(math.sin(t * 5)) * 0.04, wd, wd)
	local infected = if k <= 0 then 1 else math.floor(lerp(1, 250, ease_out(k)))
	p.count.Text = tostring(infected) .. " SICK"
	put(self, p.panel, 0.5, 0.86, W * 0.34, H * 0.2)
	self:_at(p.count, 0.5, 0.86)
	self:_kick(t, 0.5, 2, 0.3)
end

-- Sea Legs ----------------------------------------------------------------------------------------
function PerkDemos._build_sea_legs(self: any, _it: any)
	local p = self.parts
	ground(self, "sea_legs", Color3.fromRGB(30, 90, 160))
	p.home = spot(self, "Home", RED)
	p.wake = {}
	for i = 1, 8 do
		p.wake[i] = shape(self, "Wake" .. i, WHITE, 7, true)
	end
	p.ship = self:_img("Ship", icon("tr_water2"), 9, WHITE)
	p.ring = self:_fx("Ring", "ring", 10, RED)
end

function PerkDemos._step_sea_legs(self: any, t: number)
	local p = self.parts
	local H = self.H
	local home = point(self, "home", Vector2.new(0.25, 0.65))
	local far = point(self, "far", Vector2.new(0.78, 0.4))
	show_spot(self, p.home, home, t, 1.2)
	local k = ramp(t, 0.4, 2.6)
	local e = ease_out(k)
	-- (the ship sails a gentle arc from one real coast to the other)
	local function path(q: number): (number, number)
		local x = lerp(home.X, far.X, q)
		local y = lerp(home.Y, far.Y, q) - math.sin(q * math.pi) * 0.12
		return x, y
	end
	local x, y = path(e)
	local sd = H * 0.3
	self:_show(p.ship, x, y - 0.06 + math.sin(t * 3) * 0.015, sd, sd)
	p.ship.Rotation = math.sin(t * 3) * 4
	for i, w in p.wake do
		local q = e - i * 0.035
		if q > 0 and k < 1 then
			local wx, wy = path(q)
			put(self, w, wx, wy + 0.04, H * 0.035)
			w.BackgroundTransparency = 0.3 + i * 0.08
		else
			w.Visible = false
		end
	end
	-- it lands: the far coast catches it, frame by frame
	self:_frame(if t < 2.6 then 1 else 1 + ramp(t, 2.6, 3.8) * 7.999)
	local rk = (t - 2.6) / 0.6
	if rk >= 0 and rk < 1 then
		local d = H * (0.2 + 0.7 * rk)
		self:_show(p.ring, far.X, far.Y, d, d, rk)
	else
		p.ring.Visible = false
	end
	self:_kick(t, 2.6, 2, 0.25)
end

-- Gene Bank ---------------------------------------------------------------------------------------
function PerkDemos._build_gene_bank(self: any, _it: any)
	local p = self.parts
	local H, u = self.H, self.u
	ground(self, "gene_bank", Color3.fromRGB(40, 120, 60))
	p.panel = plate(self, "PricePlate", 7)
	p.halo = self:_fx("Halo", "glow", 8, Color3.fromRGB(140, 255, 150))
	p.hex = self:_img("Hex", icon("hex_fill"), 8, Color3.fromRGB(70, 46, 26))
	p.ring = self:_img("HexRing", icon("hex_ring"), 9, DNA)
	p.evo = self:_img("Evo", icon("tr_air1"), 10, DNA)
	local fs = math.clamp(H * 0.2, 14 * u, 26 * u)
	p.old = self:_text("Old", "10 DNA", fs, Color3.fromRGB(200, 200, 210), 11)
	p.strike = shape(self, "Strike", Color3.fromRGB(255, 80, 80), 12, false)
	p.price = self:_text("Price", "9 DNA", fs * 1.1, DNA, 11)
end

function PerkDemos._step_gene_bank(self: any, t: number)
	local p = self.parts
	local H, W = self.H, self.W
	grow(self, t, 0.2, 4.0)
	local d = H * 0.48
	local bob = math.sin(t * 2.4) * 0.02
	self:_show(p.halo, 0.3, 0.6 + bob, d * 1.7, d * 1.7, 0.5)
	self:_show(p.hex, 0.3, 0.6 + bob, d, d)
	self:_show(p.ring, 0.3, 0.6 + bob, d, d)
	self:_show(p.evo, 0.3, 0.6 + bob, d * 0.5, d * 0.5)
	put(self, p.panel, 0.68, 0.6, W * 0.32, H * 0.5)
	local cut = ramp(t, 1.0, 1.3)
	self:_at(p.old, 0.68, 0.48)
	fade(p.old, cut * 0.45)
	p.strike.Visible = cut > 0
	if cut > 0 then
		self:_at(p.strike, 0.68, 0.48, W * 0.24 * cut, H * 0.03)
	end
	p.price.Visible = t > 1.3
	if t > 1.3 then
		self:_at(p.price, 0.68, 0.72)
		fade(p.price, 1 - ramp(t, 1.3, 1.6))
	end
	self:_kick(t, 1.3, 2, 0.25)
end

-- Slow Science ------------------------------------------------------------------------------------
function PerkDemos._build_slow_science(self: any, _it: any)
	local p = self.parts
	local H, u = self.H, self.u
	ground(self, "slow_science", Color3.fromRGB(30, 80, 160))
	p.panel = plate(self, "BarsPlate", 7)
	p.syringe = self:_img("Syringe", icon("cure"), 9, Color3.fromRGB(150, 210, 255))
	p.halo = self:_fx("Halo", "glow", 8, Color3.fromRGB(90, 170, 255))
	local fs = math.clamp(H * 0.1, 9 * u, 14 * u)
	p.l1 = self:_text("L1", "WITHOUT", fs, WHITE, 11, FONT_B)
	p.l2 = self:_text("L2", "WITH THIS PERK", fs, Color3.fromRGB(255, 210, 120), 11, FONT_B)
	p.t1 = shape(self, "Track1", Color3.fromRGB(14, 26, 54), 8, false)
	p.t2 = shape(self, "Track2", Color3.fromRGB(14, 26, 54), 8, false)
	p.f1 = shape(self, "Fill1", Color3.fromRGB(90, 190, 255), 9, false)
	p.f2 = shape(self, "Fill2", Color3.fromRGB(255, 170, 80), 9, false)
	p.f1.AnchorPoint = Vector2.new(0, 0.5)
	p.f2.AnchorPoint = Vector2.new(0, 0.5)
	p.p1 = self:_text("P1", "0%", fs, WHITE, 11)
	p.p2 = self:_text("P2", "0%", fs, WHITE, 11)
end

function PerkDemos._step_slow_science(self: any, t: number)
	local p = self.parts
	local H, W = self.H, self.W
	grow(self, t, 0.3, 4.0)
	put(self, p.panel, 0.55, 0.62, W * 0.86, H * 0.62)
	local d = H * 0.36
	self:_show(p.halo, 0.17, 0.62, d * 1.6, d * 1.6, 0.5)
	self:_show(p.syringe, 0.17, 0.62, d, d)
	p.syringe.Rotation = math.sin(t * 2) * 8
	local k = ramp(t, 0.3, 3.2)
	local bw = W * 0.5
	local x0 = 0.32
	for _, row in { { p.l1, p.t1, p.f1, p.p1, 0.5, 1.0 }, { p.l2, p.t2, p.f2, p.p2, 0.8, 0.85 } } do
		local l, tr, f, pct, fy, mult = row[1], row[2], row[3], row[4], row[5], row[6]
		local v = k * mult
		l.Visible = true
		l.AnchorPoint = Vector2.new(0, 0.5)
		self:_at(l, x0, fy - 0.11)
		put(self, tr, x0 + bw / W * 0.5, fy, bw, H * 0.08)
		f.Visible = v > 0
		local fx, fyy = self:_px(x0, fy)
		f.Position = UDim2.fromOffset(fx, fyy)
		f.Size = UDim2.fromOffset(bw * v, H * 0.08)
		pct.Text = string.format("%d%%", math.floor(v * 100 + 0.5))
		self:_at(pct, x0 + bw / W + 0.06, fy)
	end
end

-- Mutagen -----------------------------------------------------------------------------------------
function PerkDemos._build_mutagen(self: any, _it: any)
	local p = self.parts
	local H, u = self.H, self.u
	ground(self, "mutagen", Color3.fromRGB(100, 40, 160))
	p.halo = self:_fx("Halo", "glow", 7, Color3.fromRGB(190, 130, 255))
	p.hex = self:_img("Hex", icon("hex_fill"), 8, Color3.fromRGB(16, 20, 36))
	p.ring = self:_img("HexRing", icon("hex_ring"), 9, WHITE)
	p.evo = self:_img("Evo", icon("tr_hardy"), 10, Color3.fromRGB(150, 150, 170))
	p.flash = self:_img("Flash", icon("hex_glow"), 11, WHITE)
	local fs = math.clamp(H * 0.2, 14 * u, 26 * u)
	p.label = self:_text("Label", "LOCKED", fs * 0.55, Color3.fromRGB(150, 150, 170), 11, FONT_B)
	p.sparks = {}
	for i = 1, 10 do
		p.sparks[i] = shape(self, "Spark" .. i, Color3.fromRGB(230, 200, 255), 12, true)
	end
end

function PerkDemos._step_mutagen(self: any, t: number)
	local p = self.parts
	local H, W = self.H, self.W
	local flip = 1.1
	-- (once evolved, East Africa's plague moves)
	self:_frame(if t < flip then 1 else 1 + ramp(t, flip, 4.0) * 7.999)
	local d = H * 0.56
	local on = t >= flip
	local k = (t - flip) / 0.3
	local s = if k >= 0 and k < 1 then lerp(1.35, 1, ease_out(k)) else 1
	self:_show(p.halo, 0.5, 0.56, d * 1.8, d * 1.8, if on then 0.35 else 0.85)
	self:_show(p.hex, 0.5, 0.56, d * s, d * s)
	p.hex.ImageColor3 = if on then Color3.fromRGB(255, 96, 96) else Color3.fromRGB(16, 20, 36)
	self:_show(p.ring, 0.5, 0.56, d * s, d * s, if on then 0 else 0.7)
	p.ring.ImageColor3 = if on then Color3.fromRGB(255, 190, 190) else WHITE
	self:_show(p.evo, 0.5, 0.56, d * 0.5 * s, d * 0.5 * s)
	p.evo.ImageColor3 = if on then WHITE else Color3.fromRGB(110, 110, 130)
	if k >= 0 and k < 1 then
		self:_show(p.flash, 0.5, 0.56, d * (1 + k), d * (1 + k), k)
	else
		p.flash.Visible = false
	end
	for i, sp in p.sparks do
		local a = i / #p.sparks * math.pi * 2
		local sk = (t - flip) / 0.6
		if sk >= 0 and sk <= 1 then
			local r = 0.1 + 0.3 * ease_out(sk)
			put(self, sp, 0.5 + math.cos(a) * r * H / W * 1.3, 0.56 + math.sin(a) * r, H * 0.05 * (1 - sk))
		else
			sp.Visible = false
		end
	end
	p.label.Text = if on then "EVOLVED" else "LOCKED"
	p.label.TextColor3 = if on then Color3.fromRGB(110, 230, 155) else Color3.fromRGB(150, 150, 170)
	self:_at(p.label, 0.5, 0.93)
	self:_kick(t, flip, 2, 0.25)
end

--- Adds the perks' scenes to UI/ArsenalDemo (and its frame helper).
-- Auto Pop Bubbles ------------------------------------------------------------------------------
--- Its bubbles: where (BUBBLE_PTS names), what kind, and when each comes up (s into the loop). Each pops
--- AUTO_POP_S after it shows, with nobody touching it.
local AUTO_POP = {
	{ "b2", 0, 0.2, "+3 DNA" },
	{ "b4", 1, 1.0, "CURE -1%" },
	{ "b1", 2, 1.8, "INFECTED!" },
	{ "b5", 0, 2.6, "+2 DNA" },
}
local AUTO_POP_S = 0.5

function PerkDemos._build_auto_pop(self: any, _it: any)
	local p = self.parts
	ground(self, "bubble_magnet", Color3.fromRGB(40, 70, 140))
	p.pops = {}
	for i, e in AUTO_POP do
		local g = bubble(self, "Auto" .. i, e[2])
		g.pay.Text = e[4]
		g.tag = self:_text("AutoTag" .. i, "AUTO", math.clamp(self.H * 0.075, 8 * self.u, 11 * self.u), WHITE, 11, FONT_B)
		g.tag.BackgroundColor3 = INK
		g.tag.BackgroundTransparency = 0.2
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, g.tag)
		new("UIPadding", { PaddingLeft = UDim.new(0, 6 * self.u), PaddingRight = UDim.new(0, 6 * self.u) }, g.tag)
		p.pops[i] = g
	end
end

function PerkDemos._step_auto_pop(self: any, t: number)
	local p = self.parts
	local H = self.H
	grow(self, t, 0.2, 3.6)
	for i, g in p.pops do
		local e = AUTO_POP[i]
		local at = point(self, e[1], Vector2.new(0.2 + 0.15 * i, 0.62))
		local y = math.max(at.Y, 0.5) - 0.06
		local k = t - e[3]
		if k >= 0 and k < AUTO_POP_S then
			-- it comes up...
			local sz = H * 0.24 * (0.4 + 0.6 * ease_out(ramp(k, 0, 0.18)))
			show_bubble(self, g, at.X, y, sz, math.sin(t * 2.2 + i) * 12)
			g.ring.Visible, g.pay.Visible, g.tag.Visible = false, false, false
		elseif k >= AUTO_POP_S and k < AUTO_POP_S + 0.6 then
			-- ...and pops by itself
			hide_bubble(g)
			local pk = (k - AUTO_POP_S) / 0.6
			local d = H * (0.2 + 0.55 * pk)
			self:_show(g.ring, at.X, y, d, d, pk)
			g.pay.Visible = true
			self:_at(g.pay, at.X, math.max(y - 0.1 - 0.08 * pk, 0.3))
			fade(g.pay, pk)
			g.tag.Visible = true
			self:_at(g.tag, at.X, math.min(y + 0.12, 0.92))
			fade(g.tag, pk)
		else
			hide_bubble(g)
			g.ring.Visible, g.pay.Visible, g.tag.Visible = false, false, false
		end
	end
end

function PerkDemos.install(ArsenalDemo: any)
	ArsenalDemo._frame = PerkDemos._frame
	-- 2x Stars keeps ArsenalDemo's payout scene, but on our live map: RoWorld's war map image under it
	-- was the original developer's and no longer loads (the scene showed black)
	local stars_build, stars_step = ArsenalDemo._build_stars2x, ArsenalDemo._step_stars2x
	if stars_build ~= nil and stars_step ~= nil then
		ArsenalDemo._build_stars2x = function(self: any, it: any)
			ground(self, "head_start", Color3.fromRGB(150, 104, 20))
			-- (its "map is there" branch: the payout's dim over the ground just made)
			self._map = function()
				return true
			end
			stars_build(self, it)
			self._map = nil
		end
		ArsenalDemo._step_stars2x = function(self: any, t: number)
			grow(self, t, 0.2, (self.loop or 3.0) - 0.4)
			stars_step(self, t)
		end
	end
	for _, key in { "head_start", "bubble_magnet", "super_spreader", "sea_legs", "gene_bank", "slow_science", "mutagen", "auto_pop" } do
		local build = PerkDemos["_build_" .. key]
		local step = PerkDemos["_step_" .. key]
		ArsenalDemo["_build_" .. key] = function(self: any, it: any)
			build(self, it)
			caption(self, PerkDemos.CAPTIONS[key])
		end
		ArsenalDemo["_step_" .. key] = function(self: any, t: number)
			step(self, t)
			place_caption(self, t)
		end
	end
	ArsenalDemo.LOOPS.bubble_magnet = 4.6
	ArsenalDemo.LOOPS.sea_legs = 4.2
	ArsenalDemo.LOOPS.auto_pop = 4.0
end

return PerkDemos
