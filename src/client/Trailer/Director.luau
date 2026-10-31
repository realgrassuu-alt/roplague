--!nonstrict
-- RoPlague: the in-game trailer (2026-10-31). A ~28 s cut of real gameplay that the owner records at full
-- quality in the live game (OBS or similar): press F6 and it plays itself, start to finish, with the music.
--
-- It copies the shape of RoWorld's own store trailer (studied frame by frame, 2026-10-31): gameplay only,
-- the HUD left on, a short black call-to-action pill with a gold edge at the top left for each beat, hard
-- cuts on the music's bars, and an end card with the game's name over the dimmed map and the music credit.
-- Their music is the last stretch of Rodrigo Flores' "March of War" (fingerprinted against our Soundtrack:
-- their 16.9 s start 108.5 s into it, through its breakdown and its last hit). Ours starts two bars and a
-- half earlier on a bar line (MUSIC_FROM), so the same breakdown and the same last hit land under our
-- last two beats. The track is CC BY 4.0: the end card carries the credit.
--
-- Who can run it: Studio, the owner (OWNER_IDS) and the group's top ranks. Nobody else gets the key.
-- F6 starts it (a black screen while the match is made, then 3, 2, 1); F6 again stops it. It never earns
-- anything: Session.start_trailer plays a local match with no Stars and no solo report.
--
-- The match is a local shared world (Session.start_trailer): the player's plague and a rival this
-- script plays. Everything it does goes through the same calls a player's clicks do (PlagueLink.on_click,
-- on_bubble, the Evolve screen's own buttons), so the sounds, walkers, ships, attacks and celebrations
-- are the real ones. Only two things are staged through Session.trailer_apply, because 28 s is not a
-- whole match: the far side of the world catching the plague, and the last wave of deaths.
local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Director = {}

Director.HOTKEY = Enum.KeyCode.F6
--- shown on the prep screen, so a recording of an old build is caught before it is made
Director.VERSION = "v6"
--- Who may run it besides Studio: the owner, and ranks from GROUP_RANK up in the game's group.
Director.OWNER_IDS = { [3007483] = true }
Director.GROUP_ID = 439068166
Director.GROUP_RANK = 254

--- The music: Soundtrack key, where it starts (s into the track, on a bar line) and one bar (s).
Director.MUSIC_KEY = "march_of_war"
Director.MUSIC_FROM = 97.37
Director.MUSIC_VOLUME = 0.9
Director.BAR = 2.47
--- The end card comes up on the last hit's second bar; the music has died away by END_AT.
Director.CARD_AT = 24.70
Director.END_AT = 28.4

--- The world's beats, on the music's bars (s from its first frame).
local B = Director.BAR
Director.BEATS = {
	{ at = 0.0, cta = "START AN OUTBREAK" },
	{ at = B * 1.0, cta = "SPREAD ACROSS BORDERS" },
	{ at = B * 2.5, cta = "SAIL ACROSS THE SEAS" },
	{ at = B * 4.0, cta = "EVOLVE YOUR PLAGUE" },
	{ at = B * 5.5, cta = "BATTLE RIVAL PLAGUES" },
	{ at = B * 7.0, cta = "RACE THE CURE" },
	{ at = B * 9.0, cta = "INFECT THE WORLD TO WIN" },
}

--- Where it happens (WorldCountries names).
Director.HOME = "India"
Director.RIVAL_HOME = "Myanmar"
Director.RIVAL_NAME = "Swamp Flu"
Director.RIVAL_COLOR = "shop_toxic"
Director.BORDERS = { "Bangladesh", "Bhutan" }
--- where the rival walks while we spread (its own travellers, green)
Director.RIVAL_REACH = { "Thailand", "Laos", "Cambodia", "Vietnam", "Malaysia", "Thailand" }
--- the battle: the rival's green block taken one country at a time, on the beats
Director.CONQUER = { "Myanmar", "Thailand", "Laos", "Cambodia", "Vietnam" }
--- the one ship the camera rides (a long open-sea crossing from India)
Director.SEA = "Somalia"
--- the battle's sim speed: how fast the red front eats the rival's country (tuned to take it in ~3 s)
Director.BATTLE_SPEED = 7
--- bought on screen in the Evolve beat; Water Supply (water1, ships) is bought quietly at the start
Director.EVOLVE = { "air1", "cough", "rodent1", "insect1" }
--- the Evolve beat's camera: from the ship to the middle of the map, all the way out, over this many s
Director.EVOLVE_ZOOM_OUT = 1.1
--- the last beat's dying, per second of the music: it eases in from DIE_RATE[1] to DIE_RATE[1] +
--- DIE_RATE[2] by the end card (about 85% of the sick dead by then), while CATCH_RATE of the healthy
--- fall sick; and the last of the world catches it SEED_STEP countries a step, nearest first
Director.DIE_RATE = { 0.25, 1.6 }
Director.CATCH_RATE = 0.5
Director.SEED_LAST = 60
Director.SEED_STEP = 3

local player = Players.LocalPlayer

-- =============================================================================================
-- Small helpers
-- =============================================================================================

local FONT_HEAVY = Font.fromId(12187365977, Enum.FontWeight.Heavy)
local FONT_BOLD = Font.fromId(12187365977, Enum.FontWeight.Bold)

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local o = Instance.new(class)
	for k, v in props do
		(o :: any)[k] = v
	end
	if parent ~= nil then
		o.Parent = parent
	end
	return o
end

local function tween(o: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function viewport(): Vector2
	local cam = workspace.CurrentCamera
	return if cam ~= nil then cam.ViewportSize else Vector2.new(1920, 1080)
end

-- =============================================================================================
-- The overlay: the call-to-action pill, the end card and the black cover
-- =============================================================================================

local Overlay = {}
Overlay.__index = Overlay

function Overlay.new(): any
	local self = setmetatable({}, Overlay)
	local pg = player:WaitForChild("PlayerGui")
	local gui = make("ScreenGui", {
		Name = "RoPlagueTrailer",
		DisplayOrder = 5000,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, pg)
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.None
	end)
	self.gui = gui

	-- the call to action (RoWorld's: a dark pill, a gold edge on its left, white heavy capitals)
	local pill = make("Frame", {
		Name = "Cta",
		AnchorPoint = Vector2.new(0, 0),
		BackgroundColor3 = Color3.fromRGB(14, 20, 38),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		ZIndex = 10,
	}, gui)
	make("UICorner", { CornerRadius = UDim.new(0.16, 0) }, pill)
	local stroke = make("UIStroke", {
		Color = Color3.fromRGB(255, 255, 255),
		Transparency = 1,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, pill)
	local edge = make("Frame", {
		Name = "Edge",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(255, 196, 46),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 11,
	}, pill)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, edge)
	local text = make("TextLabel", {
		Name = "Text",
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		FontFace = FONT_HEAVY,
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 12,
	}, pill)
	local pad = make("UIPadding", {}, pill)
	self.pill, self.pill_stroke, self.pill_edge, self.pill_text, self.pill_pad = pill, stroke, edge, text, pad
	self.pill_scale = make("UIScale", { Scale = 1 }, pill)

	-- the end card: the map dimmed, the name, the music credit
	local dim = make("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(4, 6, 14),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 20,
	}, gui)
	local word = make("TextLabel", {
		Name = "Word",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(0.9, 0.2),
		BackgroundTransparency = 1,
		FontFace = FONT_HEAVY,
		Text = "ROPLAGUE",
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		ZIndex = 22,
	}, gui)
	-- (the title wordmark's own colours: white at the top to a warm gold, TitleScreen.GradientText)
	make("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.35, Color3.new(1, 0.95, 0.82)),
			ColorSequenceKeypoint.new(1, Color3.new(1.0, 0.72, 0.36)),
		}),
	}, word)
	local word_stroke = make("UIStroke", {
		Color = Color3.new(0.02, 0.03, 0.09),
		Transparency = 1,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, word)
	local word_scale = make("UIScale", { Scale = 1 }, word)
	local credit = make("TextLabel", {
		Name = "Credit",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.575),
		Size = UDim2.fromScale(0.6, 0.032),
		BackgroundTransparency = 1,
		FontFace = FONT_BOLD,
		Text = "MUSIC BY RODRIGO FLORES",
		TextScaled = true,
		TextColor3 = Color3.fromRGB(225, 230, 245),
		TextTransparency = 1,
		ZIndex = 22,
	}, gui)
	local credit_stroke = make("UIStroke", {
		Color = Color3.new(0.02, 0.03, 0.09),
		Transparency = 1,
		Thickness = 1.5,
	}, credit)
	self.dim, self.word, self.word_stroke, self.word_scale = dim, word, word_stroke, word_scale
	self.credit, self.credit_stroke = credit, credit_stroke

	-- the black cover (while the match is made, the countdown, and the very end)
	local cover = make("Frame", {
		Name = "Cover",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 100,
	}, gui)
	local note = make("TextLabel", {
		Name = "Note",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.05),
		BackgroundTransparency = 1,
		FontFace = FONT_BOLD,
		Text = "",
		TextScaled = true,
		TextColor3 = Color3.fromRGB(120, 128, 150),
		ZIndex = 101,
	}, cover)
	self.cover, self.note = cover, note
	self:layout()
	self._conn = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		self:layout()
	end)
	return self
end

--- Sizes in pixels from the screen's height, as RoWorld's trailer has them (measured on its 1280x720
--- frames: the pill's left edge at 5.2% of the width, its top at 11.1% of the height, 8.9% tall).
function Overlay.layout(self)
	local vp = viewport()
	local h = vp.Y
	local ph = math.floor(h * 0.074 + 0.5)
	self.pill.Position = UDim2.fromOffset(math.floor(vp.X * 0.026), math.floor(h * 0.135))
	self.pill.Size = UDim2.fromOffset(0, ph)
	self.pill_text.TextSize = math.floor(ph * 0.56 + 0.5)
	self.pill_pad.PaddingLeft = UDim.new(0, math.floor(ph * 0.42))
	self.pill_pad.PaddingRight = UDim.new(0, math.floor(ph * 0.36))
	self.pill_edge.Size = UDim2.fromOffset(math.max(3, math.floor(ph * 0.075)), math.floor(ph * 0.62))
	self.pill_edge.Position = UDim2.new(0, -math.floor(ph * 0.42) + math.floor(ph * 0.16), 0.5, 0)
	self.pill_stroke.Thickness = math.max(1, math.floor(h / 720 + 0.5))
	self.word_stroke.Thickness = math.max(3, math.floor(h * 0.011))
	self.credit_stroke.Thickness = math.max(1, math.floor(h * 0.0025))
end

--- Shows the call to action `text` (a new one slides in; the old one goes at once, a hard cut).
function Overlay.cta(self, text: string?)
	local pill = self.pill
	if text == nil then
		pill.Visible = false
		return
	end
	self.pill_text.Text = text
	pill.Visible = true
	local x = pill.Position
	pill.Position = x - UDim2.fromOffset(math.floor(viewport().Y * 0.03), 0)
	pill.BackgroundTransparency = 0.6
	self.pill_text.TextTransparency = 0.6
	self.pill_edge.BackgroundTransparency = 0.6
	self.pill_stroke.Transparency = 1
	self.pill_scale.Scale = 1.06
	tween(pill, 0.22, { Position = x, BackgroundTransparency = 0.12 }, Enum.EasingStyle.Quart)
	tween(self.pill_text, 0.16, { TextTransparency = 0 })
	tween(self.pill_edge, 0.16, { BackgroundTransparency = 0 })
	tween(self.pill_stroke, 0.3, { Transparency = 0.86 })
	tween(self.pill_scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end

function Overlay.card(self)
	self:cta(nil)
	tween(self.dim, 0.7, { BackgroundTransparency = 0.42 }, Enum.EasingStyle.Sine)
	self.word_scale.Scale = 1.22
	tween(self.word, 0.32, { TextTransparency = 0 })
	tween(self.word_stroke, 0.32, { Transparency = 0 })
	tween(self.word_scale, 0.55, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(0.35, function()
		tween(self.credit, 0.5, { TextTransparency = 0 })
		tween(self.credit_stroke, 0.5, { Transparency = 0.2 })
	end)
end

function Overlay.clear_card(self)
	self:cta(nil)
	self.dim.BackgroundTransparency = 1
	self.word.TextTransparency = 1
	self.word_stroke.Transparency = 1
	self.credit.TextTransparency = 1
	self.credit_stroke.Transparency = 1
end

function Overlay.cover_to(self, alpha: number, t: number)
	if t <= 0 then
		self.cover.BackgroundTransparency = alpha
		self.note.TextTransparency = alpha
		return
	end
	tween(self.cover, t, { BackgroundTransparency = alpha }, Enum.EasingStyle.Sine)
	tween(self.note, t, { TextTransparency = alpha }, Enum.EasingStyle.Sine)
end

function Overlay.destroy(self)
	if self._conn ~= nil then
		self._conn:Disconnect()
	end
	self.gui:Destroy()
end

-- =============================================================================================
-- The run
-- =============================================================================================

local Main = nil
local run = nil -- the trailer playing, or nil

local function stopped(r: any): boolean
	return run ~= r or r.dead
end

--- Waits until `t` s of the music have played. False when the run was stopped meanwhile.
local function at(r: any, t: number): boolean
	while not stopped(r) and r.clock() < t do
		RunService.RenderStepped:Wait()
	end
	return not stopped(r)
end

local function country_by_name(r: any, name: string): number
	return r.by_name[name] or 0
end

local function label(r: any, c: number): number
	local e = r.cs.list[c]
	return if e ~= nil then e.label else -1
end

--- A country's (or several's) box in map units (u, v: tiles), from its tile list.
local function bbox(r: any, list: { number }): (number, number, number, number)
	local W = r.W
	local u0, v0, u1, v1 = math.huge, math.huge, -math.huge, -math.huge
	for _, c in list do
		local cached = r.boxes[c]
		if cached == nil then
			local e = r.cs.list[c]
			local a, b, x, y = math.huge, math.huge, -math.huge, -math.huge
			local tl = e.tile_list
			local n = buffer.len(tl) // 4
			local step = math.max(1, n // 4000)
			for i = 0, n - 1, step do
				local t = buffer.readi32(tl, i * 4)
				local u, v = t % W, t // W
				if u < a then a = u end
				if u > x then x = u end
				if v < b then b = v end
				if v > y then y = v end
			end
			cached = { a, b, x + 1, y + 1 }
			r.boxes[c] = cached
		end
		u0 = math.min(u0, cached[1])
		v0 = math.min(v0, cached[2])
		u1 = math.max(u1, cached[3])
		v1 = math.max(v1, cached[4])
	end
	return u0, v0, u1, v1
end

--- The zoom that fits a box of `w` x `h` tiles on screen with `pad` (a share of the screen) around it.
local function fit_scale(r: any, w: number, h: number, pad: number?): number
	local vp = r.rig:viewport_size()
	local k = 1 - (pad or 0.18)
	return r.rig:clamp_scale(math.min(vp.X * k / math.max(w, 1), vp.Y * k / math.max(h, 1)))
end

--- The camera glides to frame these countries (names) over `secs` (0: a cut). `zoom` > 1 goes closer.
local function frame(r: any, names: { string }, secs: number, zoom: number?, du: number?, dv: number?)
	local list = {}
	for _, n in names do
		local c = country_by_name(r, n)
		if c > 0 then
			table.insert(list, c)
		end
	end
	if #list == 0 then
		return
	end
	local u0, v0, u1, v1 = bbox(r, list)
	local s = fit_scale(r, u1 - u0, v1 - v0) * (zoom or 1)
	local u, v = (u0 + u1) / 2 + (du or 0), (v0 + v1) / 2 + (dv or 0)
	local rig = r.rig
	rig.attract = false
	if secs <= 0 then
		rig._focus_active = false
		rig._vel = Vector2.zero
		rig:set_scale_immediate(rig:clamp_scale(s))
		rig:look_at(u, v)
	else
		rig:focus(u, v, rig:clamp_scale(s), secs)
	end
end

--- The whole world in view (`zoom` < 1 is wider still), over `secs`.
local function frame_world(r: any, secs: number, zoom: number?)
	local rig = r.rig
	rig.attract = false
	-- (the band people live in: Greenland's top and Antarctica stay out of frame; on a 16:9 screen the
	-- Pacific's edges go too, which is where nothing happens)
	local vp = rig:viewport_size()
	local s = math.max(vp.Y / (r.H * 0.66), vp.X / r.W) * (zoom or 1)
	rig:focus(r.W * 0.53, r.H * 0.40, rig:clamp_scale(s), secs)
end

--- A click on a country, exactly as the player's (PlagueLink.on_click): patient zero, a walker across a
--- border, a ship across a sea, or an attack on the rival's.
local function click(r: any, name: string)
	local c = country_by_name(r, name)
	if c <= 0 then
		return
	end
	r.dna(400)
	pcall(r.PlagueLink.on_click, r.ui, label(r, c))
end

--- Pops (as the player would) up to `n` of our bubbles that are on screen.
local function pop(r: any, n: number)
	local st = r.session.state
	if st == nil or st.bubbles == nil then
		return
	end
	local rig = r.rig
	local list = {}
	for id, b in st.bubbles do
		if b.kind ~= 1 and type(b.tile) == "number" and b.tile >= 0 then
			local x, y = rig:tile_to_screen(b.tile)
			if rig:on_screen(x, y, -40) then
				table.insert(list, id)
			end
		end
	end
	table.sort(list)
	for i = 1, math.min(n, #list) do
		pcall(r.PlagueLink.on_bubble, r.ui, list[i])
	end
end

--- Our newest ship on the mirror (a U_TRANSPORT unit), or nil.
local function newest_ship(r: any): any?
	local st = r.session.state
	if st == nil or st.units == nil then
		return nil
	end
	local me = st.local_owner
	local pick = nil
	for uid, u in st.units do
		if u.kind == 0 and u.owner == me and type(u.path) == "table" and #u.path > 1 then
			if pick == nil or uid > pick.uid then
				pick = u
			end
		end
	end
	return pick
end

--- Where ship `u` is drawn (map units), from its path and the render tick; and its last tile.
local function ship_uv(r: any, u: any): (number?, number?, number?, number?)
	local st = r.session.state
	local path = u.path
	local n = #path
	if st == nil or n == 0 then
		return nil, nil, nil, nil
	end
	local rt = st.render_tick or st.tick
	local d = math.max(0, (rt - u.start_tick) * 100 / math.max(u.ticks_per_tile_x100, 1))
	local i = math.clamp(math.floor(d) + 1, 1, n)
	local j = math.min(i + 1, n)
	local f = math.clamp(d - math.floor(d), 0, 1)
	local W = r.W
	local a, b, z = path[i], path[j], path[n]
	local u0, v0 = a % W + 0.5, a // W + 0.5
	local u1, v1 = b % W + 0.5, b // W + 0.5
	return u0 + (u1 - u0) * f, v0 + (v1 - v0) * f, z % W + 0.5, z // W + 0.5
end

--- The far side of the world catches it (staged: 28 s is not a whole match). `frac` of each country's
--- people, entering at its label, a few countries at a time, nearest Asia first.
local function seed_far(r: any, names: { string }?, count: number, frac: number)
	r.session:trailer_apply(function(sim)
		sim:_use(1)
		local todo = {}
		if names ~= nil then
			for _, n in names do
				local c = country_by_name(r, n)
				if c > 0 then
					table.insert(todo, c)
				end
			end
		else
			for c = 1, sim.C do
				if sim.first_tick[c] < 0 and sim.holder[c] == 0 and sim.Hc[c] >= 1 then
					table.insert(todo, c)
				end
			end
			-- (nearest the home country first: the red sweeps outward instead of popping up at random)
			local home = r.home_uv
			local W = sim.W
			local function d2(c: number): number
				local t = sim.cs.list[c].label
				local du, dv = t % W - home.X, t // W - home.Y
				return du * du + dv * dv
			end
			table.sort(todo, function(a, b)
				return d2(a) < d2(b)
			end)
		end
		local done = 0
		for _, c in todo do
			if done >= count then
				break
			end
			if sim.holder[c] == 0 or sim.holder[c] == 1 then
				if sim:_seed(c, -1, math.max(6, math.floor(sim.Hc[c] * frac)), true) then
					done += 1
				end
			end
		end
		sim._pl_dirty = true
	end)
end

--- Everyone our plague holds: `frac` of the infected die (the last wave). Leaves the healthy alone, so
--- the match goes on (no game-over screen over the end card).
local function kill_wave(r: any, frac: number, grow: number)
	r.session:trailer_apply(function(sim)
		sim:_use(1)
		local died = 0
		for c = 1, sim.C do
			if sim.holder[c] == 1 then
				local h = sim.Hc[c]
				local catch = math.floor(h * grow)
				sim.Hc[c] -= catch
				sim.Ic[c] += catch
				local k = math.floor(sim.Ic[c] * frac)
				sim.Ic[c] -= k
				sim.Dc[c] += k
				died += k
			end
		end
		sim.kills = (sim.kills or 0) + died
		sim._pl_dirty = true
	end)
end

--- Our countries fill up faster than a real match would (`frac` of each one's healthy fall sick):
--- the red visibly blooms from where it landed instead of creeping. Staged, like the far side.
local function grow_ours(r: any, frac: number)
	local skip = r.spread_skip or {}
	r.session:trailer_apply(function(sim)
		sim:_use(1)
		for c = 1, sim.C do
			if sim.holder[c] == 1 and sim.Ic[c] >= 1 and not skip[c] then
				local n = math.floor(sim.Hc[c] * frac)
				if n > 0 then
					sim.Hc[c] -= n
					sim.Ic[c] += n
				end
			end
		end
		sim._pl_dirty = true
	end)
end

--- The cure's bar is staged too: research under way, and its share of the work at `v` (0..1).
local function set_cure(r: any, v: number)
	r.session:trailer_apply(function(sim)
		sim.research = true
		sim.cure = math.min(v, 0.985)
	end)
end

local function set_speed(r: any, x: number)
	r.session.local_speed = x
end

-- =============================================================================================
-- Start / stop
-- =============================================================================================

local function hide_chrome(r: any)
	r.saved = {
		mouse = UserInputService.MouseIconEnabled,
		music = Main.audio ~= nil and Main.audio._music_on,
		core = {},
		chat = {},
	}
	-- (each CoreGui as it was: the game keeps the player list, backpack and health off for good, so
	-- "All on" afterwards would be wrong)
	for _, t in Enum.CoreGuiType:GetEnumItems() do
		if t ~= Enum.CoreGuiType.All then
			local ok, on = pcall(function()
				return StarterGui:GetCoreGuiEnabled(t)
			end)
			if ok then
				r.saved.core[t] = on
			end
		end
	end
	UserInputService.MouseIconEnabled = false
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)
	-- (the new topbar keeps chat's button unless chat itself is off: named, and TextChatService's own
	-- window and input bar too. Roblox's logo and menu buttons cannot be hidden by a game at all)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
	end)
	pcall(function()
		local tcs = game:GetService("TextChatService")
		for _, cls in { "ChatWindowConfiguration", "ChatInputBarConfiguration", "ChannelTabsConfiguration" } do
			local cfg = tcs:FindFirstChildOfClass(cls)
			if cfg ~= nil then
				r.saved.chat[cfg] = cfg.Enabled
				cfg.Enabled = false
			end
		end
	end)
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", false)
	end)
	if Main.audio ~= nil and type(Main.audio._set_music) == "function" then
		pcall(Main.audio._set_music, Main.audio, false, false)
	end
end

local function restore_chrome(r: any)
	local s = r.saved or {}
	UserInputService.MouseIconEnabled = if s.mouse == nil then true else s.mouse
	for t, on in s.core or {} do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(t, on)
		end)
	end
	for cfg, on in s.chat or {} do
		pcall(function()
			cfg.Enabled = on
		end)
	end
	pcall(function()
		StarterGui:SetCore("TopbarEnabled", true)
	end)
	if Main.audio ~= nil and type(Main.audio._set_music) == "function" and s.music then
		pcall(Main.audio._set_music, Main.audio, true, false)
	end
end

local function finish(r: any, back_to_title: boolean)
	if r.finished then
		return
	end
	r.finished = true
	r.dead = true
	if run == r then
		run = nil
	end
	if r.music ~= nil then
		r.music:Stop()
		r.music:Destroy()
	end
	if r.hold ~= nil then
		r.hold:Disconnect()
	end
	if r.cam ~= nil then
		r.cam:Disconnect()
	end
	if r.hover_was ~= nil then
		r.PlagueLink.on_hover = r.hover_was
	end
	if r.banner_was ~= nil then
		r.banner_mod.make = r.banner_was
	end
	for _, w in r.widgets or {} do
		pcall(function()
			w.gui.Visible = w.visible == true
		end)
	end
	pcall(function()
		local cw = r.cure_w
		if cw ~= nil then
			cw.gui.Visible = cw.visible == true
		end
		local bw = r.bar_w
		if bw ~= nil then
			bw.gui.Visible = bw.visible == true
		end
		if r.topbar ~= nil then
			r.topbar.Enabled = true
		end
		local layers = Main.world.layers or {}
		if layers.bubbles ~= nil then
			layers.bubbles.root.Visible = true
		end
		if layers.fx ~= nil then
			layers.fx.root.Visible = true
		end
		Main.world:set_labels_visible(r.ui.labels_on ~= false)
	end)
	local ov = r.overlay
	if ov ~= nil and not back_to_title then
		ov:destroy()
	end
	restore_chrome(r)
	for _, e in r.patched or {} do
		e[1][e[2]] = nil
	end
	if back_to_title then
		-- (black until the title world is up, so the recording never shows the match coming apart)
		if ov ~= nil then
			ov:cover_to(0, 0.12)
		end
		local seen = false
		local conn = r.session.state_ready:Connect(function()
			seen = true
		end)
		pcall(function()
			r.session:start_title()
		end)
		task.spawn(function()
			local t0 = os.clock()
			while not seen and os.clock() - t0 < 5 do
				task.wait(0.05)
			end
			conn:Disconnect()
			task.wait(0.9)
			if ov ~= nil then
				ov:clear_card()
				ov.note.Text = ""
				ov:cover_to(1, 0.5)
				task.wait(0.6)
				ov:destroy()
			end
		end)
	end
end

--- The shots, on the music's clock.
local function play(r: any)
	local p = r.ui.plague
	local ov = r.overlay

	-- the spread driver: while r.spread > 0, our countries fill by that share of their healthy a second
	task.spawn(function()
		while not stopped(r) do
			local k = r.spread or 0
			if k > 0 then
				grow_ours(r, k * 0.1)
			end
			task.wait(0.1)
		end
	end)

	-- 1. START AN OUTBREAK: close on the home country; the click lands on the first beat and the red
	-- blooms out from it
	frame(r, { Director.HOME }, 0, 1.35)
	if not at(r, 0) then
		return
	end
	ov:cta(Director.BEATS[1].cta)
	frame(r, { Director.HOME }, 2.4, 1.6)
	if not at(r, 0.31) then
		return
	end
	click(r, Director.HOME)
	set_speed(r, 4)
	if not at(r, 0.6) then
		return
	end
	-- (Water Supply, quietly: ships need it, and the sea beat comes before the Evolve one)
	r.dna(400)
	pcall(function()
		r.session:send_now({ type = "evolve", id = "water1" })
	end)
	-- (the rival is already sick next door: its first few million, in its own colour)
	r.rival_boost(0.004)
	r.spread = 0.045

	-- 2. SPREAD ACROSS BORDERS: close on India's north-east border; a traveller walks into each
	-- neighbour, one at a time, and each one lights up and fills as you watch
	if not at(r, Director.BEATS[2].at) then
		return
	end
	ov:cta(Director.BEATS[2].cta)
	-- (one traveller at a time: the camera on Bangladesh with India's side of the border in frame; it
	-- walks over, Bangladesh floods red; then the next one into Bhutan, just north)
	frame(r, { "Bangladesh", "Bhutan" }, 0, 0.72, -9, 2)
	frame(r, { "Bangladesh", "Bhutan" }, B * 1.5, 0.8, -7, 0)
	set_speed(r, 3)
	r.spread = 0.4
	r.spread_skip = { [country_by_name(r, Director.HOME)] = true }
	for i, name in Director.BORDERS do
		if not at(r, Director.BEATS[2].at + 0.06 + (i - 1) * B * 0.62) then
			return
		end
		click(r, name)
		-- (the rival walks out of Myanmar too, east, away from the camera)
		r.rival_click(Director.RIVAL_REACH[i])
	end
	r.rival_boost(0.02)

	-- 3. SAIL ACROSS THE SEAS: one ship, and the camera rides it close all the way across. Its speed is
	-- worked out so it lands just before the next cut
	if not at(r, Director.BEATS[3].at) then
		return
	end
	ov:cta(Director.BEATS[3].cta)
	set_speed(r, 3)
	r.spread = 0.05
	r.spread_skip = nil
	click(r, Director.SEA)
	local ship = nil
	local t_wait = os.clock()
	while ship == nil and not stopped(r) and os.clock() - t_wait < 0.6 do
		ship = newest_ship(r)
		if ship == nil then
			RunService.RenderStepped:Wait()
		end
	end
	if stopped(r) then
		return
	end
	if ship ~= nil then
		local land_at = Director.BEATS[4].at - 0.45
		local secs = math.max(1.5, land_at - r.clock())
		local ticks = #ship.path * math.max(ship.ticks_per_tile_x100, 1) / 100
		set_speed(r, math.clamp(ticks / secs / 10, 1.5, 14))
		local u0, v0 = ship_uv(r, ship)
		local rig = r.rig
		rig:set_scale_immediate(rig:clamp_scale(rig:viewport_size().Y / 72))
		r.follow = { unit = ship, u = u0, v = v0 }
		rig:look_at(u0, v0)
	end
	r.rival_click(Director.RIVAL_REACH[6])
	if not at(r, Director.BEATS[4].at) then
		return
	end
	r.follow = nil

	-- 4. EVOLVE YOUR PLAGUE: the real Evolve screen, a buy on each beat. The world keeps going behind
	-- it (fast: this is where the match makes up its time); India fills up for the fight to come, the
	-- rival only a little, so the next shot's front moves our way
	ov:cta(Director.BEATS[4].cta)
	-- (2026-10-31: the camera leaves the ship's close-up of the coast and glides back to the middle of
	-- the map, all the way out, as RoWorld's own zoom-out does: the whole world sits behind the panel)
	do
		local rig = r.rig
		rig.attract = false
		rig._vel = Vector2.zero
		rig:focus(r.W * 0.5, r.H * 0.5, rig:min_scale(), Director.EVOLVE_ZOOM_OUT)
	end
	pcall(r.PlagueLink.open_evolve, r.ui)
	r.unpause = true
	set_speed(r, 18)
	r.spread = 0.06
	-- (the rival takes its whole block now, out of sight, and it is green all through by the fight)
	for _, n in { "Thailand", "Laos", "Cambodia", "Vietnam" } do
		r.rival_click(n)
	end
	r.rival_boost(0.3)
	local ev = p and p.evolve
	local bought = 0
	for _, id in Director.EVOLVE do
		if bought >= 3 then
			break
		end
		if ev ~= nil and ev:_status(id) == "buy" then
			if not at(r, Director.BEATS[4].at + 0.45 + bought * B * 0.5) then
				return
			end
			r.dna(400)
			pcall(ev._select, ev, id, true)
			if not at(r, Director.BEATS[4].at + 0.45 + bought * B * 0.5 + B * 0.25) then
				return
			end
			r.dna(400)
			pcall(ev._press, ev, id)
			bought += 1
		end
	end
	r.rival_boost(0.35)
	-- (closed early enough that its fade is over by the cut)
	if not at(r, Director.BEATS[5].at - 0.3) then
		return
	end
	if ev ~= nil then
		pcall(ev.close, ev, true)
	end
	pcall(function()
		r.ui:_update_pause()
	end)

	-- 5. BATTLE RIVAL PLAGUES: the rival's green block (Myanmar, Thailand, Laos, Cambodia, Vietnam), and
	-- our red taking it one country at a time on the beats, RoWorld's attacks with their troop counts on
	-- the fronts. Each country falls to the one before it, so the red marches east across the screen
	if not at(r, Director.BEATS[5].at) then
		return
	end
	ov:cta(Director.BEATS[5].cta)
	frame(r, { "Myanmar", "Thailand", "Laos", "Vietnam", "Bangladesh" }, 0, 1.0, -4, -2)
	frame(r, { "Myanmar", "Thailand", "Laos", "Vietnam", "Bangladesh" }, B * 1.5, 1.07, 0, -2)
	set_speed(r, Director.BATTLE_SPEED)
	-- (each country taken fills fast: its sick are the army for the next one)
	r.spread = 0.45
	for i, name in Director.CONQUER do
		if not at(r, Director.BEATS[5].at + 0.05 + (i - 1) * B * 0.3) then
			return
		end
		click(r, name)
	end

	-- 6. RACE THE CURE: wide and quiet: no labels, no bursts; the red sweeps outward from India while
	-- the cure's bar and the bottom bar's counts (back on screen for the last beats) climb through the
	-- music's breakdown
	if not at(r, Director.BEATS[6].at) then
		return
	end
	ov:cta(Director.BEATS[6].cta)
	r.wide = true
	r.show_cure = true
	r.show_bar = true
	pcall(function()
		Main.world:set_labels_visible(false)
	end)
	frame(r, { Director.HOME, "Kenya", "China", "Türkiye" }, 0, 1.0)
	frame_world(r, B * 2, 1.0)
	set_speed(r, 12)
	r.spread = 0.07
	set_cure(r, 0.58)
	local t6 = Director.BEATS[6].at
	local steps = 10
	for i = 1, steps do
		if not at(r, t6 + (i - 1) * (B * 2 / steps)) then
			return
		end
		set_cure(r, 0.58 + 0.36 * (i / steps))
		seed_far(r, nil, 8, 0.03)
	end

	-- 7. INFECT THE WORLD TO WIN: the last hit, and the world dies under it
	if not at(r, Director.BEATS[7].at) then
		return
	end
	ov:cta(Director.BEATS[7].cta)
	frame_world(r, B, 1.06)
	set_speed(r, 14)
	r.spread = 0
	-- (2026-10-31, "the black death just pops up": it landed in five 35% steps, so whole countries went
	-- dark in a frame. Now the dying is continuous and eases in, so the dark creeps out of each country
	-- from where it first fell sick (the sim kills its oldest tiles first), and the rest of the world
	-- catches it a few countries a step, nearest first, instead of sixty at once)
	local t7 = Director.BEATS[7].at
	local span = math.max(Director.CARD_AT - t7, 0.1)
	local prev = r.clock()
	local seeded = 0
	while r.clock() < Director.CARD_AT do
		task.wait(0.05)
		if stopped(r) then
			return
		end
		local now = math.min(r.clock(), Director.CARD_AT)
		local dt = math.max(now - prev, 0)
		prev = now
		if seeded < Director.SEED_LAST then
			seed_far(r, nil, Director.SEED_STEP, 0.05)
			seeded += Director.SEED_STEP
		end
		local k = math.clamp((now - t7) / span, 0, 1)
		local rate = Director.DIE_RATE[1] + Director.DIE_RATE[2] * k * k
		kill_wave(r, 1 - math.exp(-rate * dt), 1 - math.exp(-Director.CATCH_RATE * dt))
	end

	-- the end card: the world stops where it is
	if not at(r, Director.CARD_AT) then
		return
	end
	set_speed(r, 0)
	ov:card()
	if not at(r, Director.END_AT) then
		return
	end
	ov:cover_to(0, 0.6)
	task.wait(0.8)
	finish(r, true)
end

--- Makes the match (behind the black cover), then counts down and plays.
local function prepare(r: any)
	local ov = r.overlay
	local session = r.session
	ov.note.Text = "PREPARING THE TRAILER…  (" .. Director.VERSION .. ")"
	hide_chrome(r)

	-- the music, loaded before anything moves
	local Soundtrack = require(game:GetService("ReplicatedStorage"):WaitForChild("Airfront"):WaitForChild("Assets"):WaitForChild("Soundtrack")) :: any
	local track = Soundtrack.tracks[Director.MUSIC_KEY]
	local music = make("Sound", {
		Name = "RoPlagueTrailerMusic",
		SoundId = track.id,
		Volume = Director.MUSIC_VOLUME,
		Looped = false,
	}, SoundService)
	r.music = music
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ music })
		end)
	end)

	-- the match: the player's plague and the rival's (a local shared world, Session.start_trailer)
	local name = "Plague"
	pcall(function()
		name = r.PlagueLink.plague_name(r.ui)
	end)
	local ready = false
	local conn = session.state_ready:Connect(function(s)
		if s ~= nil and s.plague ~= nil then
			ready = true
		end
	end)
	session:start_trailer({
		name = name,
		plagues = { { name = name }, { name = Director.RIVAL_NAME } },
	})
	local t0 = os.clock()
	while not ready and not stopped(r) and os.clock() - t0 < 45 do
		task.wait(0.05)
	end
	conn:Disconnect()
	if stopped(r) then
		return false
	end
	if not ready then
		warn("[Trailer] the match did not start")
		return false
	end
	set_speed(r, 0)
	local st = session.state
	local sim = session:local_sim()
	r.sim = sim
	r.cs = sim.cs
	r.W = sim.W
	r.H = sim.H
	r.by_name = {}
	r.boxes = {}
	for c = 1, sim.C do
		r.by_name[sim.cs.list[c].name] = c
	end
	r.rig = Main.world.rig
	r.dna = function(min_dna: number)
		session:trailer_apply(function(s2)
			s2:_use(1)
			if s2.dna < min_dna then
				s2.dna = min_dna
			end
			s2._pl_dirty = true
		end)
	end
	r.rival_click = function(nm: string)
		local c = country_by_name(r, nm)
		if c <= 0 then
			return
		end
		session:trailer_apply(function(s2)
			s2:_use(2)
			s2.dna = math.max(s2.dna, 400)
			s2:_infect_click(c)
		end)
	end
	--- the rival's own country fills up (`frac` of its healthy fall sick): big enough to hold a front
	r.rival_boost = function(frac: number)
		session:trailer_apply(function(s2)
			s2:_use(2)
			for c = 1, s2.C do
				if s2.holder[c] == 2 then
					local n = math.floor(s2.Hc[c] * frac)
					s2.Hc[c] -= n
					s2.Ic[c] += n
				end
			end
			s2._pl_dirty = true
		end)
	end
	-- the rival starts next door, and wears its own colour
	local rc = country_by_name(r, Director.RIVAL_HOME)
	session:trailer_apply(function(s2)
		s2:_use(2)
		s2:_start(label(r, rc))
	end)
	pcall(function()
		st:set_cosmetics({ [sim.C + 2] = { color = Director.RIVAL_COLOR } }, false)
	end)
	do
		local t = label(r, country_by_name(r, Director.HOME))
		r.home_uv = Vector2.new(t % sim.W, t // sim.W)
	end
	-- A clean screen (2026-10-31: "you can barely tell what's going on"): the map and the action only.
	-- Off for the whole run: the top-left buttons, the news feed, the +DNA lines and banners, the
	-- attacks panel, the leaderboard, the country card, the race panel, the bubbles and the hover card.
	-- The cure's bar shows for its two beats; the wide shots also lose the labels and the bursts. Each
	-- widget's own `visible` says what to put back (Widgets.Control).
	local ui, p0 = r.ui, r.ui.plague
	r.widgets = {}
	-- (v6: ui.spawn too, the "CHOOSE PATIENT ZERO" pill, which flashed until the first click landed)
	for _, w in { ui.feed, ui.attacks, ui.alert, ui.board, ui.top, ui.spawn, p0 and p0.notice, p0 and p0.card, p0 and p0.race, p0 and p0.world } do
		if type(w) == "table" and typeof(w.gui) == "Instance" then
			table.insert(r.widgets, w)
		end
	end
	r.cure_w = p0 and p0.cure
	r.bar_w = p0 and p0.bar
	r.topbar = player.PlayerGui:FindFirstChild("AirfrontTopbar")
	local layers = Main.world.layers or {}
	r.hold = RunService.Heartbeat:Connect(function()
		if stopped(r) then
			return
		end
		-- (the Evolve screen would hold the world still: the trailer keeps it going)
		if r.unpause then
			session.paused = false
		end
		for _, w in r.widgets do
			if w.gui.Visible then
				w.gui.Visible = false
			end
		end
		local cw = r.cure_w
		if cw ~= nil and typeof(cw.gui) == "Instance" then
			cw.gui.Visible = r.show_cure == true and cw.visible == true
		end
		local bw = r.bar_w
		if bw ~= nil and typeof(bw.gui) == "Instance" then
			bw.gui.Visible = r.show_bar == true and bw.visible == true
		end
		if r.topbar ~= nil and r.topbar:IsA("ScreenGui") then
			r.topbar.Enabled = false
		end
		if layers.bubbles ~= nil and layers.bubbles.root ~= nil then
			layers.bubbles.root.Visible = false
		end
		if layers.fx ~= nil and layers.fx.root ~= nil then
			layers.fx.root.Visible = not r.wide
		end
		if layers.labels ~= nil and layers.labels.root ~= nil and layers.labels.root.Visible then
			layers.labels.root.Visible = false
		end
	end)
	-- the camera rides the ship (shot 3): eased onto it, looking a little ahead to where it lands
	r.cam = RunService.RenderStepped:Connect(function(dt)
		local f = r.follow
		if f == nil or stopped(r) then
			return
		end
		local st2 = session.state
		if st2 == nil or st2.units == nil or st2.units[f.unit.uid] == nil then
			return -- (landed: the camera stays where it is)
		end
		local su, sv, eu, ev = ship_uv(r, f.unit)
		if su == nil then
			return
		end
		local au, av = su + (eu - su) * 0.18, sv + (ev - sv) * 0.18
		local k = 1 - math.exp(-dt * 5)
		f.u += (au - f.u) * k
		f.v += (av - f.v) * k
		local rig = r.rig
		rig.attract = false
		rig._focus_active = false
		rig._vel = Vector2.zero
		rig:look_at(f.u, f.v)
	end)
	-- the big centre banners ("THE OUTBREAK BEGINS", UIAdvisor) are built hidden: the pill says it
	local Banner = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Banner")) :: any
	r.banner_mod, r.banner_was = Banner, Banner.make
	Banner.make = function(...)
		local b = r.banner_was(...)
		pcall(function()
			b:set_visible(false)
		end)
		return b
	end
	-- the real mouse still moves under the hidden cursor: no hover cards
	r.hover_was = r.PlagueLink.on_hover
	r.PlagueLink.on_hover = function()
		return true
	end
	-- the trailer's match never ends (a won race, or a finished cure, would put the game-over screen over
	-- the end card): on this match's own sim only, the end is switched off and the cure stops short of it
	sim._check_over = function() end
	sim._over = function() end
	local cure_step = sim._cure
	sim._cure = function(s2: any, dt: number)
		if s2.cure > 0.985 then
			s2.cure = 0.985
		end
		cure_step(s2, dt)
		if s2.cure > 0.985 then
			s2.cure = 0.985
		end
	end
	-- the race panel and the country card stay down: the map is the shot (both restored after)
	local p = r.ui.plague
	r.patched = {}
	local function patch(obj: any, key: string, fn: any)
		if obj ~= nil then
			table.insert(r.patched, { obj, key })
			obj[key] = fn
		end
	end
	if p ~= nil then
		patch(p.race, "show_world", function(self2)
			self2:set_visible(false)
		end)
		pcall(function()
			p.race:set_visible(false)
		end)
		patch(p.card, "show_country", function() end)
		pcall(function()
			p.card:hide_card()
		end)
	end
	-- no country labels in the trailer: a label jumps from its small name to the big infected one the
	-- moment the country is hit, which reads as a glitch close up (restored by finish)
	pcall(function()
		Main.world:set_labels_visible(false)
	end)
	-- the map paints, the music loads
	frame(r, { Director.HOME }, 0, 1.25)
	local t1 = os.clock()
	while (not music.IsLoaded or os.clock() - t1 < 2.5) and not stopped(r) and os.clock() - t1 < 20 do
		task.wait(0.05)
	end
	if stopped(r) then
		return false
	end
	-- 3, 2, 1 on the black, then the first frame and the first note together
	for i = 3, 1, -1 do
		ov.note.Text = tostring(i)
		task.wait(1)
		if stopped(r) then
			return false
		end
	end
	ov.note.Text = ""
	return true
end

local function start()
	if run ~= nil then
		return
	end
	local ui = Main.ui
	if ui == nil or ui.ctx == nil or Main.session == nil or Main.world == nil or Main.world.rig == nil then
		warn("[Trailer] the game is not ready yet")
		return
	end
	local r = {
		session = Main.session,
		ui = ui,
		PlagueLink = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Plague"):WaitForChild("PlagueLink")) :: any,
		dead = false,
	}
	run = r
	r.overlay = Overlay.new()
	task.spawn(function()
		local ok, err = pcall(function()
			if not prepare(r) then
				finish(r, true)
				return
			end
			-- the clock: the music's own position once it plays (no drift over 28 s)
			local music = r.music
			music.TimePosition = Director.MUSIC_FROM
			music:Play()
			local wall0 = os.clock()
			r.clock = function(): number
				local t = os.clock() - wall0
				if music.IsPlaying then
					local mt = music.TimePosition - Director.MUSIC_FROM
					if math.abs(mt - t) > 0.12 then
						wall0 = os.clock() - mt
						t = mt
					end
				end
				return t
			end
			r.overlay:cover_to(1, 0)
			play(r)
		end)
		if not ok then
			warn("[Trailer] " .. tostring(err))
			finish(r, true)
		end
	end)
end

function Director.stop()
	local r = run
	if r ~= nil then
		finish(r, true)
	end
end

function Director.toggle()
	if run ~= nil then
		Director.stop()
	else
		start()
	end
end

function Director.running(): boolean
	return run ~= nil
end

local function allowed(): boolean
	if RunService:IsStudio() then
		return true
	end
	if Director.OWNER_IDS[player.UserId] then
		return true
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroup(Director.GROUP_ID)
	end)
	return ok and type(rank) == "number" and rank >= Director.GROUP_RANK
end

--- Main calls this once the UI is up. The key is bound only for those allowed.
function Director.bind(main: any)
	Main = main
	task.spawn(function()
		if not allowed() then
			return
		end
		ContextActionService:BindAction("RoPlagueTrailer", function(_name, state, _input)
			if state ~= Enum.UserInputState.Begin or GuiService.MenuIsOpen then
				return Enum.ContextActionResult.Pass
			end
			if UserInputService:GetFocusedTextBox() ~= nil then
				return Enum.ContextActionResult.Pass
			end
			Director.toggle()
			return Enum.ContextActionResult.Sink
		end, false, Director.HOTKEY)
		-- (Studio tests: workspace attribute RP_TRAILER = true starts it, as the key would)
		if RunService:IsStudio() then
			workspace:GetAttributeChangedSignal("RP_TRAILER"):Connect(function()
				if workspace:GetAttribute("RP_TRAILER") == true then
					workspace:SetAttribute("RP_TRAILER", nil)
					Director.toggle()
				end
			end)
		end
	end)
end

return Director
