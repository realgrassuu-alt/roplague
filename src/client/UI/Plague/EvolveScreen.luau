--!nonstrict
-- RoPlague: the Evolve window, built like RoWorld's Arsenal (UI/Arsenal) so it looks and moves like the
-- rest of the game. One evolution at a time:
--   tree    on the left, a honeycomb skill tree per tab (TRANSMISSION / SYMPTOMS / ABILITIES, with how
--           many are owned): each evolution a hex with its icon, its name and what it takes under it,
--           joined to what it needs by lines that light up once both ends are owned. Owned hexes wear
--           their tree's colour, the ones the DNA buys glow orange, locked ones are dark. A press shows
--           it on the right.
--   item    on the right: its icon playing big on its tree's colour, its name, chips (its tree and
--           what it does), what it does in plain words, what it needs first, and one big EVOLVE
--           button with its price (grey with how much DNA is missing, or what to evolve first).
--   head    the title, one line of what this is, the DNA balance, close.
-- Motion: the window pops in over a dim; a picked evolution slides in; rows brighten under the
-- pointer and the ones the DNA buys pulse; evolving flashes the picture, kicks the icon, throws
-- sparks, counts the DNA down, flashes its row green and pulses the ones it opened up; a press on a
-- locked or too-dear one shakes the button. Purchases apply at once (Session.send_now) and the game is
-- paused while it is open (UIRoot._update_pause).
--   EvolveScreen.new(ctx); :open() / :close() / :refresh() / :apply_layout(); .is_open; .modal (self);
--   .closed (Signal); .close_button; :buy_rect() (logical Rect of the EVOLVE button, for the tutorial)
local UITheme = require("../UITheme")
local W = require("../Widgets")
local GlassPanel = require("../GlassPanel")
local UICtx = require("../UICtx")
local PUI = require("./PUI")
local Signal = UITheme.core("Signal")
local Traits = UICtx.data("Traits")

local IS_ROBLOX = typeof(game) == "Instance"
local TweenService = if IS_ROBLOX then game:GetService("TweenService") else nil

local EvolveScreen = W.class(W.Control)

EvolveScreen.SUBTITLE = "Spend DNA to make your plague stronger."
--- A hex is HEX px across (flat-top: about 0.87 of that tall), with LABEL px under it for its name
--- and price; columns step 0.78 of a hex and every other column sits half a step down.
EvolveScreen.HEX = 70
EvolveScreen.HEX_PHONE = 50
EvolveScreen.LABEL = 28
EvolveScreen.LABEL_PHONE = 22
EvolveScreen.DETAIL_W = 360
EvolveScreen.PREVIEW_H = 104
--- The tree's window onto its board (logical px): the board scrolls inside it, so the window stays
--- short however big a tree grows. The detail panel is as tall as the tree area and its tabs.
EvolveScreen.VIEW_W = 480
EvolveScreen.VIEW_H = 330
--- The footer under the board ("4 MORE TO DISCOVER")
EvolveScreen.HINT_H = 18
EvolveScreen.SPARKS = 14

local FONT_H = Font.fromId(12187365977, Enum.FontWeight.Heavy)
local FONT_B = Font.fromId(12187365977, Enum.FontWeight.Bold)
local FONT_M = Font.fromId(12187365977, Enum.FontWeight.Medium)
local DNA = PUI.DNA
local WHITE = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(170, 182, 211)
local ROW = Color3.fromRGB(24, 33, 58)
local ROW_ON = Color3.fromRGB(38, 53, 90)
local CHIP = Color3.fromRGB(38, 53, 90)
local NIGHT = Color3.fromRGB(8, 12, 26)
local OWNED_GREEN = Color3.fromRGB(110, 230, 155)
local GREEN_TOP = Color3.fromRGB(86, 216, 130)
local GREEN_BOTTOM = Color3.fromRGB(34, 166, 90)
local GREEN_TOP_HI = Color3.fromRGB(108, 234, 150)
local GREEN_BOTTOM_HI = Color3.fromRGB(46, 186, 106)
local GREEN_LIP = Color3.fromRGB(18, 108, 56)
local GREEN_INK = Color3.fromRGB(12, 82, 42)
local BAR_OFF = Color3.fromRGB(44, 58, 94)
local BAR_LIP = Color3.fromRGB(28, 38, 64)

--- The world picture behind each tree's evolutions (Assets/PlagueIcons).
local SCENES = { transmission = "scene_europe", symptoms = "scene_africa", abilities = "scene_asia" }

local TREE_COLORS = {
	transmission = Color3.fromRGB(255, 96, 96),
	symptoms = Color3.fromRGB(255, 170, 70),
	abilities = Color3.fromRGB(110, 190, 255),
}

--- Each evolution's own colour, by what it is (the carrier, the body system it attacks, the resistance),
--- so a tree reads as families instead of one colour. Missing ids fall back to their tree's colour.
local rgb = Color3.fromRGB
local NODE_COLORS = {
	-- transmission: one colour per carrier
	air1 = rgb(120, 200, 255), air2 = rgb(80, 170, 255),
	water1 = rgb(70, 220, 210), water2 = rgb(40, 190, 200),
	insect1 = rgb(190, 230, 70), insect2 = rgb(150, 210, 50),
	rodent1 = rgb(214, 160, 110), rodent2 = rgb(190, 130, 84),
	farm1 = rgb(110, 220, 120), farm2 = rgb(76, 196, 96),
	stowaway = rgb(255, 196, 70), hardy = rgb(200, 120, 255),
	-- symptoms: one colour per body system
	nausea = rgb(150, 220, 90), vomit = rgb(120, 200, 70),
	cough = rgb(110, 190, 255), sneeze = rgb(90, 170, 255), pneumonia = rgb(70, 140, 255),
	rash = rgb(255, 130, 190), cysts = rgb(240, 100, 170),
	insomnia = rgb(170, 140, 255), paranoia = rgb(150, 110, 255), seizures = rgb(130, 90, 245),
	paralysis = rgb(112, 80, 230), coma = rgb(96, 70, 210),
	fever = rgb(255, 140, 60), anaemia = rgb(255, 96, 110), bleeding = rgb(230, 50, 70),
	immune = rgb(255, 80, 150), organs = rgb(200, 40, 60),
	-- abilities: one colour per resistance
	cold1 = rgb(150, 220, 255), cold2 = rgb(110, 200, 255),
	heat1 = rgb(255, 170, 80), heat2 = rgb(255, 130, 50),
	drug1 = rgb(120, 230, 150), drug2 = rgb(80, 210, 120),
	shield1 = rgb(190, 140, 255), shield2 = rgb(170, 110, 255), shield3 = rgb(150, 80, 255),
	lock = rgb(255, 214, 90),
}
local function color_of(t: any): Color3
	return NODE_COLORS[t.id] or TREE_COLORS[t.tree]
end
--- Two presses on one hex within this many seconds evolve it (a single press only picks it).
local DOUBLE_TAP_S = 0.4

--- What each effect means, in plain words (lines), and as a chip.
local FX_TEXT = {
	{ "beta", "Spreads faster inside countries", "FASTER" },
	{ "hot", "Spreads faster in hot countries", "HOT LANDS" },
	{ "urban", "Spreads faster in crowded countries", "CITIES" },
	{ "rural", "Spreads faster in the countryside", "COUNTRYSIDE" },
	{ "air", "Sometimes jumps to a far country by itself", "FAR JUMPS" },
	{ "water", "Ships sail further and cost less", "SHIPS" },
	{ "land", "Crosses borders by itself more often", "BORDERS" },
	{ "stow", "Ships land even where ports are closed", "CLOSED PORTS" },
	{ "sev", "Makes people sicker (the world notices sooner)", "SICKER" },
	{ "leth", "Kills hosts", "DEADLY" },
	{ "cold", "Survives in cold countries", "COLD" },
	{ "heat", "Survives in hot countries", "HEAT" },
	{ "drug", "Shrugs off medicine in rich countries", "MEDICINE" },
	{ "resist", "Slows the cure down", "SLOWS CURE" },
	{ "lock", "Stops symptoms appearing by themselves", "NO MUTATIONS" },
}

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

local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	if TweenService ~= nil then
		local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
		tw:Play()
		return tw
	end
	return nil
end

local function icon_of(t: any): string
	local key = "tr_" .. t.id
	return if UITheme.icon(key) ~= nil then key else t.tree
end

local function fx_lines(t: any): string
	local out = {}
	for _, e in FX_TEXT do
		local v = t.fx[e[1]]
		if v ~= nil and v ~= 0 then
			table.insert(out, (if v < 0 then "- " else "+ ") .. e[2])
		end
	end
	return table.concat(out, "\n")
end

local function fx_chips(t: any): { string }
	local out = {}
	for _, e in FX_TEXT do
		local v = t.fx[e[1]]
		if v ~= nil and v ~= 0 and #out < 2 then
			table.insert(out, e[3])
		end
	end
	return out
end

function EvolveScreen.new(c: any)
	local self = setmetatable({}, EvolveScreen.__mt)
	W.Control._init(self)
	self.ctx = c
	self.modal = self
	self.closed = Signal.new()
	self.is_open = false
	self._rows = {} :: { [string]: any }
	self._groups = {} :: { [string]: any }
	self._sel = nil :: string?
	self._detail = nil :: any
	self._shown_dna = 0
	self._t = 0.0
	self.selected = nil
	self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	self:set_mouse_filter(W.MOUSE_STOP)
	self:set_visible(false)
	self._dim = W.ColorRect.new(UITheme.rgba(0.01, 0.015, 0.05, 0.75))
	self._dim:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	self._dim.gui_input:Connect(function(e)
		if e.pressed and not self._panel:has_global_point(e.global_position) then
			self:close()
		end
	end)
	self:add_child(self._dim)
	self._panel = GlassPanel.new(20.0, 16.0, 18, true, 34)
	self._panel:set_tint(UITheme.rgba(0.045, 0.065, 0.13, 0.97))
	self:add_child(self._panel)
	local v = UITheme.vbox(12)
	self._v = v
	self._panel:add_child(v)
	-- head
	local head = UITheme.hbox(12)
	local icon = UITheme.icon_rect("evolve", 26.0, DNA)
	icon.size_flags_vertical = W.SHRINK_CENTER
	head:add_child(icon)
	local tv = UITheme.vbox(0)
	tv.size_flags_horizontal = W.EXPAND_FILL
	tv.size_flags_vertical = W.SHRINK_CENTER
	tv:add_child(UITheme.label("EVOLVE", 20, 800, UITheme.TEXT, 3))
	self._sub = UITheme.label(EvolveScreen.SUBTITLE, 12, 500, UITheme.TEXT_2)
	tv:add_child(self._sub)
	head:add_child(tv)
	-- the plague's three meters, small, in the header (they were under every evolution's text)
	local meters = W.Control.new()
	meters:set_mouse_filter(W.MOUSE_IGNORE)
	meters.size_flags_vertical = W.SHRINK_CENTER
	self._meters_host = meters
	self._meter_bars = {}
	self._meter_frame = new("Frame", {
		Name = "Meters",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 41,
	}, meters.gui)
	head:add_child(meters)
	local bal = GlassPanel.new(12.0, 6.0, 999, false, 0)
	bal:set_tint(UITheme.rgba(1.0, 0.59, 0.24, 0.14))
	bal.size_flags_vertical = W.SHRINK_CENTER
	local bh = UITheme.hbox(6)
	local di = UITheme.icon_rect("dna", 18.0, DNA)
	di.size_flags_vertical = W.SHRINK_CENTER
	bh:add_child(di)
	self._balance = UITheme.label("0", 16, 800, DNA)
	self._balance.size_flags_vertical = W.SHRINK_CENTER
	bh:add_child(self._balance)
	bh:add_child(UITheme.label("DNA", 11, 800, DNA))
	bal:add_child(bh)
	self._balance_pill = bal
	head:add_child(bal)
	local close = PUI.close_button(function()
		self:close()
	end)
	self.close_button = close
	head:add_child(close)
	v:add_child(head)
	-- body: list | item
	local body = UITheme.hbox(14)
	v:add_child(body)
	local left = UITheme.vbox(8)
	body:add_child(left)
	-- the tabs: one tree at a time
	local tabs = UITheme.hbox(6)
	self._tabs = {}
	self.tree = "transmission"
	for _, tree in Traits.TREES do
		local chip = PUI.chip(string.upper(Traits.TREE_NAMES[tree]), 34.0)
		chip:set_icon(tree)
		chip.pressed:Connect(function()
			self:_set_tree(tree, true)
		end)
		self._tabs[tree] = chip
		tabs:add_child(chip)
	end
	left:add_child(tabs)
	local list_host = W.Control.new()
	list_host:set_mouse_filter(W.MOUSE_PASS)
	self._list_host = list_host
	left:add_child(list_host)
	self._board = new("Frame", {
		Name = "EvolveBoard",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -EvolveScreen.HINT_H),
		ZIndex = 40,
	}, list_host.gui)
	new("UICorner", { CornerRadius = UDim.new(0, 12) }, self._board)
	self._board_grad = new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(26, 30, 56), NIGHT),
		Transparency = NumberSequence.new(0.35, 0.1),
		Rotation = 90,
	}, self._board)
	self._board_stroke = new("UIStroke", { Color = WHITE, Transparency = 0.9, Thickness = 1 }, self._board)
	self._list = new("ScrollingFrame", {
		Name = "EvolveTree",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = MUTED,
		ScrollBarImageTransparency = 0.45,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		VerticalScrollBarInset = Enum.ScrollBarInset.None,
		HorizontalScrollBarInset = Enum.ScrollBarInset.None,
		CanvasSize = UDim2.fromOffset(0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 41,
	}, self._board)
	self._hint = new("TextLabel", {
		Name = "Hidden",
		BackgroundTransparency = 1,
		Text = "",
		FontFace = FONT_B,
		TextSize = 12,
		TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 4, 1, 0),
		Size = UDim2.new(1, -8, 0, EvolveScreen.HINT_H - 2),
		ZIndex = 42,
	}, list_host.gui)
	local detail_host = W.Control.new()
	detail_host:set_mouse_filter(W.MOUSE_PASS)
	self._detail_host = detail_host
	body:add_child(detail_host)
	self:set_process(true)
	return self
end

-- ---------------------------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------------------------

function EvolveScreen._pl(self): any
	local s = self.ctx.state
	return if s ~= nil then s.plague else nil
end

--- (owned, dna, price multiplier) of the plague now.
function EvolveScreen._money(self): ({ [string]: boolean }, number, number)
	local p = self:_pl()
	if p == nil then
		return {}, 0, 1
	end
	return p.owned or {}, math.floor(p.dna or 0), p.price_mult or 1
end

--- "owned" | "buy" (the DNA buys it) | "poor" (reachable, not enough DNA) | "locked"
function EvolveScreen._status(self, id: string): (string, number)
	local owned, dna, mult = self:_money()
	if owned[id] then
		return "owned", 0
	end
	local price = Traits.price(id, owned, mult)
	if not Traits.reachable(id, owned) then
		return "locked", price
	end
	return (if dna >= price then "buy" else "poor"), price
end

--- The evolution the window opens on: the cheapest the DNA buys, else the cheapest reachable (in `tree`
--- when given; an owned one of it when the whole tree is bought).
function EvolveScreen._suggest(self, tree: string?): string?
	local owned, dna, mult = self:_money()
	local best, best_price, best_ok = nil, math.huge, false
	for _, t in Traits.list do
		if (tree == nil or t.tree == tree) and not owned[t.id] and Traits.reachable(t.id, owned) then
			local price = Traits.price(t.id, owned, mult)
			local ok = price <= dna
			if (ok and not best_ok) or (ok == best_ok and price < best_price) then
				best, best_price, best_ok = t.id, price, ok
			end
		end
	end
	if best == nil and tree ~= nil then
		for _, t in Traits.list do
			if t.tree == tree then
				return t.id
			end
		end
	end
	return best or (Traits.list[1] and Traits.list[1].id)
end

-- ---------------------------------------------------------------------------------------------
-- The list
-- ---------------------------------------------------------------------------------------------

--- The tree area's inner margin (px): the hexes' glow stays inside its clip.
local PAD = 14

--- Where a trait's hex sits in its tree (logical px of its centre) for hex width `w`, label `lh`.
local function hex_pos(t: any, w: number, lh: number): Vector2
	local h = w * 0.866
	local step_y = h + lh + 12
	local x = (t.col - 1) * w * 1.25 + w * 0.6 + PAD
	local y = (t.row - 1) * step_y + (if t.col % 2 == 0 then step_y * 0.5 else 0) + h * 0.5 + PAD
	return Vector2.new(x, y)
end

--- The tree area's size (logical px): the board's window and its footer (apply_layout may shrink it
--- on a phone).
function EvolveScreen._tree_size(self): Vector2
	if self._view ~= nil then
		return self._view
	end
	return Vector2.new(EvolveScreen.VIEW_W, EvolveScreen.VIEW_H)
end

function EvolveScreen._set_tree(self, tree: string, by_player: boolean?)
	if self.tree == tree and next(self._rows) ~= nil then
		return
	end
	self.tree = tree
	for t, chip in self._tabs do
		chip:set_pressed_no_signal(t == tree)
	end
	if self.is_open then
		self:_build_list(true)
		if by_player then
			self.ctx:sfx("tab", -4.0)
			-- (the cheapest one in this tree)
			local best, best_p = nil, math.huge
			local owned, _, mult = self:_money()
			for _, t in Traits.list do
				if t.tree == tree and not owned[t.id] and Traits.reachable(t.id, owned) then
					local pr = Traits.price(t.id, owned, mult)
					if pr < best_p then
						best, best_p = t.id, pr
					end
				end
			end
			if best ~= nil then
				self:_select(best, false)
			end
		end
		self:_refresh_list()
	end
end

--- A hex shows once it could be next: it is owned, it needs nothing, or something it needs is owned.
--- The rest of the tree stays hidden, so it opens up as the plague evolves.
function EvolveScreen._visible(_self, t: any, owned: { [string]: boolean }): boolean
	if owned[t.id] or t.req == nil then
		return true
	end
	for _, r in t.req do
		if owned[r] then
			return true
		end
	end
	return false
end

--- `pop`: true, every hex pops in; "new", only the ones that just appeared.
--- The board holds the hexes that show (EvolveScreen._visible) and, one step past them, the ones still
--- hidden as dark "?" hexes, so the tree reads as going somewhere; the board is sized to them, centred
--- in its window while it is smaller, and scrolls once it is bigger.
function EvolveScreen._build_list(self, pop: any)
	for _, ch in self._list:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
	table.clear(self._rows)
	self._links = {}
	local owned = self:_money()
	local before = self._shown_ids or {}
	local tree = self.tree
	local shown, mystery = {}, {}
	for _, t in Traits.list do
		if t.tree == tree and self:_visible(t, owned) then
			shown[t.id] = true
		end
	end
	local hidden = 0
	for _, t in Traits.list do
		if t.tree == tree and not shown[t.id] then
			hidden += 1
			for _, r in t.req or {} do
				if shown[r] then
					mystery[t.id] = true
					break
				end
			end
		end
	end
	self._shown_ids = shown
	local u = UITheme.scale
	local w = if self.ctx.compact then EvolveScreen.HEX_PHONE else EvolveScreen.HEX
	local lh = if self.ctx.compact then EvolveScreen.LABEL_PHONE else EvolveScreen.LABEL
	local h = w * 0.866
	local col = TREE_COLORS[tree]
	self._board_grad.Color = ColorSequence.new(col:Lerp(NIGHT, 0.78), NIGHT)
	self._board_stroke.Color = col
	-- the board: what is on it, framed, centred in the window while it is smaller
	local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
	for _, t in Traits.list do
		if t.tree == tree and (shown[t.id] or mystery[t.id]) then
			local p = hex_pos(t, w, lh)
			minx = math.min(minx, p.X - w * 0.6)
			maxx = math.max(maxx, p.X + w * 0.6)
			miny = math.min(miny, p.Y - h * 0.5 - 8)
			maxy = math.max(maxy, p.Y + w * 0.4 + lh + 8)
		end
	end
	local view = self:_tree_size()
	local vw, vh = view.X, view.Y - EvolveScreen.HINT_H
	-- (the window as it really is on screen, when laid out: a canvas a pixel bigger shows scrollbars)
	local abs = self._list.AbsoluteSize
	if abs.X > 1 and abs.Y > 1 then
		vw, vh = abs.X / u, abs.Y / u
	end
	local cw, ch = maxx - minx + 2 * PAD, maxy - miny + 2 * PAD
	vw, vh = math.floor(vw), math.floor(vh)
	local ox, oy = PAD - minx, PAD - miny
	-- (scrollbars only when the board really is bigger than its window)
	local over = cw > vw + 4 or ch > vh + 4
	if cw < vw then
		ox += (vw - cw) * 0.5
		cw = vw
	end
	if ch < vh then
		oy += (vh - ch) * 0.5
		ch = vh
	end
	local off = Vector2.new(ox, oy)
	local function at(t: any): Vector2
		return (hex_pos(t, w, lh) + off) * u
	end
	self._list.ScrollBarThickness = if over then 6 else 0
	self._list.ScrollingEnabled = over
	self._list.CanvasSize = if over then UDim2.fromOffset(math.ceil(cw * u), math.ceil(ch * u)) else UDim2.fromOffset(0, 0)
	if not over then
		self._list.CanvasPosition = Vector2.zero
	end
	-- links first, under the hexes (to a "?" hex: faint)
	for _, t in Traits.list do
		if t.tree == tree and (shown[t.id] or mystery[t.id]) then
			for _, r in t.req or {} do
				local rt = Traits.by_id[r]
				if rt ~= nil and rt.tree == tree and shown[r] then
					local a, b = at(rt), at(t)
					local d = b - a
					local f = new("Frame", {
						Name = "Link_" .. r .. "_" .. t.id,
						BorderSizePixel = 0,
						BackgroundColor3 = WHITE,
						BackgroundTransparency = if mystery[t.id] then 0.93 else 0.85,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2),
						Size = UDim2.fromOffset(d.Magnitude, math.max(3, 4 * u)),
						Rotation = math.deg(math.atan2(d.Y, d.X)),
						ZIndex = 42,
					}, self._list)
					if not mystery[t.id] then
						table.insert(self._links, { frame = f, from = r, to = t.id, color = color_of(t) })
					end
				end
			end
		end
	end
	local k = 0
	for _, t in Traits.list do
		if t.tree == tree and shown[t.id] then
			k += 1
			local p = if pop == true or (pop == "new" and not before[t.id]) then k else nil
			self._rows[t.id] = self:_row(t, at(t), w * u, lh * u, u, p)
		elseif t.tree == tree and mystery[t.id] then
			k += 1
			self:_mystery(t, at(t), w * u, lh * u, u, if pop ~= nil then k else nil)
		end
	end
	-- the footer: how much of this tree is still hidden
	self._hint.TextSize = math.floor(12 * u)
	self._hint.Text = if hidden > 0
		then ("%d MORE TO DISCOVER  ·  evolve the ones you see to reveal them"):format(hidden)
		else "THE WHOLE TREE IS OPEN"
	-- keep the picked one in sight
	local sel = self._sel and self._rows[self._sel]
	if sel ~= nil then
		local sp = sel.button.Position
		local vx, vy = vw * u, vh * u
		local cx = math.clamp(sp.X.Offset - vx * 0.5, 0, math.max(0, cw * u - vx))
		local cy = math.clamp(sp.Y.Offset - vy * 0.5, 0, math.max(0, ch * u - vy))
		self._list.CanvasPosition = Vector2.new(cx, cy)
	end
	self._shown_tree = tree
end

--- A hex not revealed yet, one step past the ones you see: dark, a "?", no name or price.
function EvolveScreen._mystery(self, _t: any, p: Vector2, w: number, lh: number, u: number, pop: number?)
	local b = new("ImageLabel", {
		Name = "Mystery",
		BackgroundTransparency = 1,
		Image = UITheme.icon("hex_fill") or "",
		ImageColor3 = Color3.fromRGB(14, 18, 32),
		ImageTransparency = 0.15,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(p.X, p.Y),
		Size = UDim2.fromOffset(w, w),
		ZIndex = 43,
	}, self._list)
	new("ImageLabel", {
		Name = "Ring",
		BackgroundTransparency = 1,
		Image = UITheme.icon("hex_ring") or "",
		ImageColor3 = WHITE,
		ImageTransparency = 0.88,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 44,
	}, b)
	new("TextLabel", {
		Name = "Q",
		BackgroundTransparency = 1,
		Text = "?",
		FontFace = FONT_H,
		TextSize = math.floor(w * 0.42),
		TextColor3 = Color3.fromRGB(96, 106, 140),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 45,
	}, b)
	local tab = new("Frame", {
		Name = "MysteryLabel",
		BackgroundColor3 = Color3.fromRGB(12, 16, 32),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(p.X, p.Y + w * 0.4),
		Size = UDim2.fromOffset(w * 0.8, lh * 0.62),
		ZIndex = 46,
	}, self._list)
	new("UICorner", { CornerRadius = UDim.new(0, 6 * u) }, tab)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Text = "LOCKED",
		FontFace = FONT_B,
		TextSize = math.floor(9 * u),
		TextColor3 = Color3.fromRGB(96, 106, 140),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 47,
	}, tab)
	if pop ~= nil then
		local sc = new("UIScale", { Scale = 0.01 }, b)
		task.delay(0.02 * pop, function()
			tween(sc, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end
end

function EvolveScreen._row(self, t: any, at: Vector2, w: number, lh: number, u: number, pop: number?): any
	local col = color_of(t)
	local glow = new("ImageLabel", {
		Name = "Glow_" .. t.id,
		BackgroundTransparency = 1,
		Image = UITheme.icon("hex_glow") or "",
		ImageColor3 = DNA,
		ImageTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(w * 1.45, w * 1.45),
		ZIndex = 42,
	}, self._list)
	local b = new("ImageButton", {
		Name = "Hex_" .. t.id,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Image = UITheme.icon("hex_fill") or "",
		ImageColor3 = ROW,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(at.X, at.Y),
		Size = UDim2.fromOffset(w, w),
		ZIndex = 43,
	}, self._list)
	local ring = new("ImageLabel", {
		Name = "Ring",
		BackgroundTransparency = 1,
		Image = UITheme.icon("hex_ring") or "",
		ImageColor3 = WHITE,
		ImageTransparency = 0.8,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 44,
	}, b)
	local icon = new("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Image = UITheme.icon(icon_of(t)) or "",
		ImageColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.5, 0.5),
		ZIndex = 45,
	}, b)
	local sc = new("UIScale", { Scale = if pop ~= nil then 0.01 else 1 }, b)
	-- the name and the price under the hex, on a dark tab
	local tab = new("Frame", {
		Name = "Label_" .. t.id,
		BackgroundColor3 = Color3.fromRGB(12, 16, 32),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(at.X, at.Y + w * 0.4),
		Size = UDim2.fromOffset(w * 1.18, lh),
		ZIndex = 46,
	}, self._list)
	new("UICorner", { CornerRadius = UDim.new(0, 6 * u) }, tab)
	local tab_stroke = new("UIStroke", { Color = col, Thickness = 1, Transparency = 0.6 }, tab)
	local name = new("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		Text = t.name,
		FontFace = FONT_B,
		TextScaled = true,
		TextColor3 = WHITE,
		Size = UDim2.new(1, -4 * u, 0.56, 0),
		Position = UDim2.fromOffset(2 * u, 1 * u),
		ZIndex = 47,
	}, tab)
	new("UITextSizeConstraint", { MaxTextSize = math.floor(12 * u), MinTextSize = 7 }, name)
	local tx = new("TextLabel", {
		Name = "Price",
		BackgroundTransparency = 1,
		Text = "",
		FontFace = FONT_H,
		TextScaled = true,
		TextColor3 = DNA,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 2 * u, 1, -1 * u),
		Size = UDim2.new(1, -4 * u, 0.42, 0),
		ZIndex = 47,
	}, tab)
	new("UITextSizeConstraint", { MaxTextSize = math.floor(11 * u), MinTextSize = 7 }, tx)
	b.MouseEnter:Connect(function()
		tween(sc, 0.12, { Scale = 1.1 }, Enum.EasingStyle.Back)
	end)
	b.MouseLeave:Connect(function()
		tween(sc, 0.15, { Scale = 1 })
	end)
	b.MouseButton1Down:Connect(function()
		tween(sc, 0.05, { Scale = 0.94 })
	end)
	b.Activated:Connect(function()
		tween(sc, 0.2, { Scale = 1.06 }, Enum.EasingStyle.Back)
		-- a second press on the same hex soon after evolves it (the first only picks it)
		local now = os.clock()
		local tap = self._last_tap
		self._last_tap = { id = t.id, at = now }
		if tap ~= nil and tap.id == t.id and now - tap.at <= DOUBLE_TAP_S and self._sel == t.id then
			self._last_tap = nil
			self:_press(t.id)
			return
		end
		self:_select(t.id, true)
	end)
	if pop ~= nil then
		-- the tree builds itself: hexes pop in one after another
		task.delay(0.02 * pop, function()
			tween(sc, 0.32, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end
	return {
		button = b,
		fill = b,
		ring = ring,
		glow = glow,
		icon = icon,
		tab = tab,
		tab_stroke = tab_stroke,
		name = name,
		text = tx,
		scale = sc,
		status = nil,
		color = col,
	}
end

function EvolveScreen._refresh_list(self)
	local owned = self:_money()
	for id, r in self._rows do
		local st, price = self:_status(id)
		local on = self._sel == id
		r.status = st
		local col = r.color
		if st == "owned" then
			r.fill.ImageColor3 = col:Lerp(NIGHT, 0.15)
			r.icon.ImageColor3 = WHITE
			r.icon.ImageTransparency = 0
			r.text.Text = "OWNED"
			r.text.TextColor3 = OWNED_GREEN
			r.name.TextColor3 = WHITE
			r.glow.ImageColor3 = col
			r.glow.ImageTransparency = 0.7
		elseif st == "buy" then
			-- (in its own colour, so a tree of buyable hexes is not one block of orange; the price
			-- stays DNA orange)
			r.fill.ImageColor3 = col:Lerp(NIGHT, 0.62)
			r.icon.ImageColor3 = col:Lerp(WHITE, 0.3)
			r.icon.ImageTransparency = 0
			r.text.Text = tostring(price) .. " DNA"
			r.text.TextColor3 = DNA
			r.name.TextColor3 = WHITE
			r.glow.ImageColor3 = col
		elseif st == "poor" then
			r.fill.ImageColor3 = col:Lerp(ROW_ON, 0.82)
			r.icon.ImageColor3 = col:Lerp(MUTED, 0.6)
			r.icon.ImageTransparency = 0
			r.text.Text = tostring(price) .. " DNA"
			r.text.TextColor3 = MUTED
			r.name.TextColor3 = WHITE
			r.glow.ImageTransparency = 1
		else
			r.fill.ImageColor3 = Color3.fromRGB(16, 20, 36)
			r.icon.ImageColor3 = MUTED
			r.icon.ImageTransparency = 0.6
			r.text.Text = "LOCKED"
			r.text.TextColor3 = Color3.fromRGB(110, 120, 150)
			r.name.TextColor3 = MUTED
			r.glow.ImageTransparency = 1
		end
		r.ring.ImageColor3 = if on then WHITE elseif st == "buy" then col:Lerp(WHITE, 0.2) elseif st == "owned" then col:Lerp(WHITE, 0.4) else WHITE
		r.ring.ImageTransparency = if on then 0 elseif st == "buy" then 0.1 elseif st == "owned" then 0.2 else 0.82
		r.tab_stroke.Color = if on then WHITE else col
		r.tab_stroke.Transparency = if on then 0 else 0.6
	end
	for _, l in self._links or {} do
		local lit = owned[l.from] == true and owned[l.to] == true
		local half = owned[l.from] == true
		l.frame.BackgroundColor3 = if lit then l.color elseif half then l.color:Lerp(WHITE, 0.5) else WHITE
		l.frame.BackgroundTransparency = if lit then 0.1 elseif half then 0.5 else 0.85
	end
	for _, tree in Traits.TREES do
		local n, total = 0, 0
		for _, t in Traits.list do
			if t.tree == tree then
				total += 1
				if owned[t.id] then
					n += 1
				end
			end
		end
		local chip = self._tabs[tree]
		if chip ~= nil then
			chip:set_text(string.format("%s  %d/%d", string.upper(Traits.TREE_NAMES[tree]), n, total))
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- The item
-- ---------------------------------------------------------------------------------------------

function EvolveScreen._build_detail(self, slide: boolean?)
	if self._detail ~= nil then
		self._detail.root:Destroy()
		self._detail = nil
	end
	local t = Traits.by_id[self._sel or ""]
	if t == nil then
		return
	end
	local u = UITheme.scale
	local size = self._detail_size or Vector2.new(EvolveScreen.DETAIL_W, EvolveScreen.PREVIEW_H + 260)
	local dw, dh = size.X, size.Y
	local compact = self.ctx.compact
	local col = color_of(t)
	local root = new("CanvasGroup", {
		Name = "EvolveItem",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(dw * u, dh * u),
		ZIndex = 40,
	}, self._detail_host.gui)
	-- the picture: the icon big on its tree's colour, a pulsing glow, orbiting specks
	local ph = (if compact then 120 else EvolveScreen.PREVIEW_H)
	local pw = dw
	local ground = new("Frame", {
		Name = "Preview",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(pw * u, ph * u),
		ZIndex = 41,
	}, root)
	new("UICorner", { CornerRadius = UDim.new(0, 12 * u) }, ground)
	ground.BackgroundColor3 = NIGHT
	-- the game's own world behind it, washed in the tree's colour (Assets/PlagueIcons scene_*)
	new("ImageLabel", {
		Name = "World",
		BackgroundTransparency = 1,
		Image = UITheme.icon(SCENES[t.tree] or "scene_europe") or "",
		ScaleType = Enum.ScaleType.Crop,
		Size = UDim2.fromScale(1.1, 1.1),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 41,
	}, ground)
	local wash = new("Frame", {
		Name = "Wash",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 42,
	}, ground)
	new("UIGradient", {
		Color = ColorSequence.new(col:Lerp(NIGHT, 0.3), NIGHT),
		Transparency = NumberSequence.new(0.72, 0.22),
		Rotation = 90,
	}, wash)
	local glow = new("Frame", {
		Name = "Glow",
		BackgroundColor3 = col,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(ph * 0.72 * u, ph * 0.72 * u),
		ZIndex = 42,
	}, ground)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, glow)
	local specks = {}
	for i = 1, 5 do
		local d = new("Frame", {
			Name = "Speck" .. i,
			BackgroundColor3 = col:Lerp(WHITE, 0.5),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset((4 + i % 3 * 2) * u, (4 + i % 3 * 2) * u),
			ZIndex = 43,
		}, ground)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, d)
		specks[i] = d
	end
	local isz = ph * 0.56
	local icon = new("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Image = UITheme.icon(icon_of(t)) or "",
		ImageColor3 = WHITE,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(isz * u, isz * u),
		ZIndex = 45,
	}, ground)
	local iscale = new("UIScale", { Scale = if slide then 0.6 else 1 }, icon)
	local flash = new("Frame", {
		Name = "Flash",
		BackgroundColor3 = col:Lerp(WHITE, 0.4),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 49,
	}, ground)
	new("UICorner", { CornerRadius = UDim.new(0, 12 * u) }, flash)
	-- the words
	local y = ph + 12
	local name_fs = if compact then 18 else 24
	new("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Text = string.upper(t.name),
		FontFace = FONT_H,
		TextSize = math.floor(name_fs * u),
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(0, y * u),
		Size = UDim2.new(1, 0, 0, (name_fs + 4) * u),
		ZIndex = 42,
	}, root)
	y += name_fs + 6
	local chips = new("Frame", {
		Name = "Chips",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, y * u),
		Size = UDim2.new(1, 0, 0, 20 * u),
		ZIndex = 42,
	}, root)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6 * u), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	local function chip(text: string, color: Color3, order: number): any
		local l = new("TextLabel", {
			BackgroundColor3 = CHIP,
			Text = text,
			FontFace = FONT_B,
			TextSize = math.floor(10 * u),
			TextColor3 = color,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 20 * u),
			LayoutOrder = order,
			ZIndex = 43,
		}, chips)
		new("UICorner", { CornerRadius = UDim.new(0, 6 * u) }, l)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8 * u), PaddingRight = UDim.new(0, 8 * u) }, l)
		return l
	end
	chip(string.upper(Traits.TREE_NAMES[t.tree]), col, 1)
	local status_chip = chip("", WHITE, 2)
	for i, f in fx_chips(t) do
		chip(f, DNA, 2 + i)
	end
	y += 28
	local plain_fs = if compact then 12 else 14
	local desc = new("TextLabel", {
		Name = "Desc",
		BackgroundTransparency = 1,
		Text = t.desc,
		FontFace = FONT_M,
		TextSize = math.floor(plain_fs * u),
		TextColor3 = Color3.fromRGB(214, 222, 240),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, y * u),
		Size = UDim2.new(1, 0, 0, (plain_fs + 4) * 2 * u),
		ZIndex = 42,
	}, root)
	local _ = desc
	y += (plain_fs + 4) * 2 + 4
	local fx = new("TextLabel", {
		Name = "Effects",
		BackgroundTransparency = 1,
		Text = fx_lines(t),
		FontFace = FONT_B,
		TextSize = math.floor((plain_fs - 1) * u),
		TextColor3 = OWNED_GREEN,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, y * u),
		Size = UDim2.new(1, 0, 0, (plain_fs + 2) * 3 * u),
		ZIndex = 42,
	}, root)
	local _2 = fx
	y += (plain_fs + 2) * 3 + 4
	-- what it opens up next (the hidden part of the tree)
	local next_names = {}
	for _, o in Traits.list do
		for _, r in o.req or {} do
			if r == t.id then
				table.insert(next_names, o.name)
			end
		end
	end
	if #next_names > 0 then
		new("TextLabel", {
			Name = "Unlocks",
			BackgroundTransparency = 1,
			Text = "UNLOCKS NEXT:  " .. table.concat(next_names, ", "),
			FontFace = FONT_B,
			TextSize = math.floor((plain_fs - 2) * u),
			TextColor3 = col:Lerp(WHITE, 0.4),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			Position = UDim2.fromOffset(0, y * u),
			Size = UDim2.new(1, 0, 0, (plain_fs + 2) * 2 * u),
			ZIndex = 42,
		}, root)
	end
	-- the button and the line under it sit at the bottom
	local bh = if compact then 40 else 50
	local by = dh - bh - 26
	local cta = new("Frame", {
		Name = "Get",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, by * u),
		Size = UDim2.new(1, 0, 0, (bh + 26) * u),
		ZIndex = 42,
	}, root)
	local bars = {}
	self._detail = {
		id = t.id,
		root = root,
		ground = ground,
		glow = glow,
		specks = specks,
		icon = icon,
		iscale = iscale,
		flash = flash,
		cta = cta,
		status_chip = status_chip,
		bars = bars,
		button_y = by,
		button_h = bh,
		width = dw,
		u = u,
		born = os.clock(),
	}
	if slide then
		root.GroupTransparency = 1
		root.Position = UDim2.fromOffset(16 * u, 0)
		tween(root, 0.22, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) })
		tween(iscale, 0.4, { Scale = 1 }, Enum.EasingStyle.Back)
	end
	self:_build_cta()
	self:_refresh_meters(true)
end

--- The big button: EVOLVE with its price; grey with what's missing; OWNED with DEVOLVE beside it.
function EvolveScreen._build_cta(self)
	local d = self._detail
	if d == nil then
		return
	end
	for _, ch in d.cta:GetChildren() do
		ch:Destroy()
	end
	local u = d.u
	local id = d.id
	local t = Traits.by_id[id]
	local st, price = self:_status(id)
	local owned, dna = self:_money()
	local hh = math.floor(d.button_h * u + 0.5)
	local lip = math.max(3, math.floor(4 * u + 0.5))
	local on = st == "buy"
	local fs = if self.ctx.compact then 15 else 18
	-- the status chip
	local sc = d.status_chip
	if st == "owned" then
		sc.Text, sc.TextColor3 = "OWNED", OWNED_GREEN
	elseif st == "buy" then
		sc.Text, sc.TextColor3 = "READY TO EVOLVE", DNA
	elseif st == "poor" then
		sc.Text, sc.TextColor3 = "NEED MORE DNA", MUTED
	else
		sc.Text, sc.TextColor3 = "LOCKED", MUTED
	end
	local b = new("TextButton", {
		Name = "Buy",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.new(if st == "owned" then 0.58 else 1, 0, 0, hh + lip),
		ZIndex = 43,
	}, d.cta)
	local under = new("Frame", {
		Name = "Lip",
		BackgroundColor3 = if on then GREEN_LIP else BAR_LIP,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, lip),
		Size = UDim2.new(1, 0, 0, hh),
		ZIndex = 43,
	}, b)
	new("UICorner", { CornerRadius = UDim.new(0, 12 * u) }, under)
	local face = new("Frame", {
		Name = "Face",
		BackgroundColor3 = if on then WHITE elseif st == "owned" then Color3.fromRGB(30, 70, 52) else BAR_OFF,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, hh),
		ZIndex = 44,
	}, b)
	new("UICorner", { CornerRadius = UDim.new(0, 12 * u) }, face)
	local grad = new("UIGradient", { Color = ColorSequence.new(GREEN_TOP, GREEN_BOTTOM), Rotation = 90, Enabled = on }, face)
	if on then
		local sheen = new("Frame", {
			Name = "Sheen",
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.85,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(4 * u, 3 * u),
			Size = UDim2.new(1, -8 * u, 0.4, 0),
			ZIndex = 45,
		}, face)
		new("UICorner", { CornerRadius = UDim.new(0, 9 * u) }, sheen)
	end
	local text
	if st == "owned" then
		text = "EVOLVED"
	elseif st == "buy" then
		text = "EVOLVE"
	elseif st == "poor" then
		text = string.format("NEED %d MORE DNA", price - dna)
	else
		text = "LOCKED"
	end
	local label = new("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		Text = text,
		FontFace = FONT_H,
		TextSize = math.floor(fs * u),
		TextColor3 = if on then WHITE elseif st == "owned" then OWNED_GREEN else MUTED,
		TextXAlignment = if on then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(18 * u, 0),
		Size = UDim2.new(1, -36 * u, 1, 0),
		ZIndex = 46,
	}, face)
	if on then
		new("UIStroke", { Color = GREEN_INK, Thickness = 1.5, Transparency = 0.55 }, label)
		local pill = new("Frame", {
			Name = "Price",
			BackgroundColor3 = GREEN_INK,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -7 * u, 0.5, 0),
			Size = UDim2.fromOffset(0, hh - 14 * u),
			AutomaticSize = Enum.AutomaticSize.X,
			ZIndex = 46,
		}, face)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, pill)
		new("UIPadding", { PaddingLeft = UDim.new(0, 10 * u), PaddingRight = UDim.new(0, 12 * u) }, pill)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 5 * u),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, pill)
		new("ImageLabel", {
			BackgroundTransparency = 1,
			Image = UITheme.icon("dna") or "",
			ImageColor3 = WHITE,
			Size = UDim2.fromOffset(math.floor((fs + 1) * u), math.floor((fs + 1) * u)),
			LayoutOrder = 1,
			ZIndex = 47,
		}, pill)
		new("TextLabel", {
			BackgroundTransparency = 1,
			Text = tostring(price),
			FontFace = FONT_H,
			TextSize = math.floor(fs * u),
			TextColor3 = WHITE,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, hh - 14 * u),
			LayoutOrder = 2,
			ZIndex = 47,
		}, pill)
	end
	local function lift(down: boolean)
		tween(face, if down then 0.05 else 0.1, { Position = UDim2.fromOffset(0, if down then lip - 1 else 0) })
	end
	b.MouseEnter:Connect(function()
		if on then
			grad.Color = ColorSequence.new(GREEN_TOP_HI, GREEN_BOTTOM_HI)
		end
	end)
	b.MouseLeave:Connect(function()
		grad.Color = ColorSequence.new(GREEN_TOP, GREEN_BOTTOM)
		lift(false)
	end)
	b.MouseButton1Down:Connect(function()
		lift(true)
	end)
	b.MouseButton1Up:Connect(function()
		lift(false)
	end)
	b.Activated:Connect(function()
		self:_press(id)
	end)
	d.buy = b
	d.buy_on = on
	-- OWNED: DEVOLVE beside it
	if st == "owned" then
		local can = Traits.can_devolve(id, owned)
		local dv = new("TextButton", {
			Name = "Devolve",
			Text = string.format("DEVOLVE  +%d", math.floor(t.cost * Traits.REFUND)),
			FontFace = FONT_B,
			TextSize = math.floor(13 * u),
			TextColor3 = if can then Color3.fromRGB(255, 130, 130) else MUTED,
			AutoButtonColor = false,
			BackgroundColor3 = Color3.fromRGB(60, 24, 32),
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.new(0.39, 0, 0, hh),
			ZIndex = 43,
		}, d.cta)
		new("UICorner", { CornerRadius = UDim.new(0, 12 * u) }, dv)
		dv.Activated:Connect(function()
			if can then
				self:_act("devolve", id)
			else
				self.ctx:sfx("deny", -4.0)
			end
		end)
	end
	-- the line under it: what it needs, or what to do
	local line
	if st == "locked" then
		local names = {}
		for _, r in t.req or {} do
			local rt = Traits.by_id[r]
			table.insert(names, if rt then rt.name else r)
		end
		line = (if (t.req_n or 1) > 1 then ("Evolve %d of these first: "):format(t.req_n) else "Evolve this first: ")
			.. table.concat(names, ", ")
	elseif st == "poor" then
		line = "Pop DNA bubbles and infect new countries to earn DNA"
	elseif st == "owned" then
		line = "Devolve to get some DNA back (only if nothing needs it)"
	else
		line = string.format("You have %d DNA", dna)
	end
	new("TextLabel", {
		Name = "Line",
		BackgroundTransparency = 1,
		Text = line,
		FontFace = FONT_M,
		TextSize = math.floor(11 * u),
		TextColor3 = if st == "locked" then UITheme.AMBER else MUTED,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(0, (hh + lip + 6) * 1),
		Size = UDim2.new(1, 0, 0, 16 * u),
		ZIndex = 43,
	}, d.cta)
end

function EvolveScreen._refresh_meters(self, instant: boolean?)
	local p = self:_pl()
	if p == nil then
		return
	end
	for i, v in { p.inf or 0, p.sev or 0, p.leth or 0 } do
		local bar = self._meter_bars[i]
		if bar ~= nil then
			local sz = UDim2.fromScale(math.clamp(v, 0, 1), 1)
			if instant then
				bar.Size = sz
			else
				tween(bar, 0.4, { Size = sz })
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------------
-- Picking, evolving
-- ---------------------------------------------------------------------------------------------

function EvolveScreen._select(self, id: string, by_player: boolean?)
	if Traits.by_id[id] == nil then
		return
	end
	local changed = id ~= self._sel
	self._sel = id
	self.selected = id
	local tr = Traits.by_id[id].tree
	if tr ~= self.tree then
		self:_set_tree(tr, false)
	end
	if changed then
		self:_build_detail(true)
		if by_player then
			self.ctx:sfx("tab", -4.0)
		end
	end
	self:_refresh_list()
end

--- The tutorial / old API: select by id.
function EvolveScreen.select(self, id: string?)
	if id ~= nil then
		self:_select(id, false)
	end
end

function EvolveScreen._press(self, id: string)
	local st = self:_status(id)
	local d = self._detail
	if st == "buy" then
		self:_act("evolve", id)
		return
	end
	if st == "owned" then
		return
	end
	-- not yet: the button shakes
	self.ctx:sfx("deny", -4.0)
	if d ~= nil and d.buy ~= nil then
		local b = d.buy
		local x0 = b.Position
		task.spawn(function()
			for _, dx in { 8, -7, 5, -3, 0 } do
				b.Position = x0 + UDim2.fromOffset(dx * d.u, 0)
				task.wait(0.035)
			end
		end)
	end
end

function EvolveScreen._act(self, kind: string, id: string)
	local ctx = self.ctx
	local before = {}
	for tid, r in self._rows do
		before[tid] = r.status
	end
	local intent = { type = kind, id = id }
	local ok = ctx:session_call("send_now", { intent })
	if ok == nil then
		ctx:send(intent)
	end
	if kind == "evolve" then
		ctx:sfx("plague_evolve", -1.0)
		self:_celebrate(id, before)
	else
		ctx:sfx("confirm")
		self:refresh()
	end
end

--- The evolution just bought: flash, kick, sparks, the DNA counts down, its row flashes green and the
--- rows it opened up pulse.
function EvolveScreen._celebrate(self, id: string, before: { [string]: string })
	self:refresh()
	local d = self._detail
	if d ~= nil and d.id == id then
		d.flash.BackgroundTransparency = 0.1
		tween(d.flash, 0.6, { BackgroundTransparency = 1 })
		d.kick_t = os.clock()
		d.iscale.Scale = 1.35
		tween(d.iscale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		local u = d.u
		local g = d.ground
		local col = color_of(Traits.by_id[id])
		for k = 1, EvolveScreen.SPARKS do
			local a = (k / EvolveScreen.SPARKS) * math.pi * 2 + math.random() * 0.4
			local r = (60 + math.random() * 60) * u
			local s = new("Frame", {
				Name = "Spark",
				BackgroundColor3 = col:Lerp(WHITE, math.random() * 0.6),
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(7 * u, 7 * u),
				ZIndex = 48,
			}, g)
			new("UICorner", { CornerRadius = UDim.new(1, 0) }, s)
			tween(s, 0.55, {
				Position = UDim2.new(0.5, math.cos(a) * r, 0.5, math.sin(a) * r),
				Size = UDim2.fromOffset(2 * u, 2 * u),
				BackgroundTransparency = 1,
			})
			task.delay(0.6, function()
				s:Destroy()
			end)
		end
	end
	local row = self._rows[id]
	if row ~= nil then
		row.scale.Scale = 1.35
		tween(row.scale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		row.glow.ImageColor3 = WHITE
		row.glow.ImageTransparency = 0
		tween(row.glow, 0.8, { ImageTransparency = 0.7, ImageColor3 = row.color })
	end
	-- the hexes this opened up
	for tid, r in self._rows do
		if before[tid] == "locked" and r.status ~= "locked" then
			r.ring.ImageColor3 = OWNED_GREEN
			r.ring.ImageTransparency = 0
			r.scale.Scale = 0.7
			tween(r.scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		end
	end
	local bp = self._balance_pill
	if bp ~= nil and bp.gui ~= nil then
		UICtx.pop_in(bp, 0.0, 1.2, 0.3)
	end
end

-- ---------------------------------------------------------------------------------------------
-- Per frame: the picture breathes, specks orbit, the rows the DNA buys pulse, the DNA counts
-- ---------------------------------------------------------------------------------------------

function EvolveScreen._process(self, delta: number)
	if not self.is_open then
		return
	end
	self._t += delta
	local t = self._t
	local d = self._detail
	if d ~= nil then
		d.icon.Position = UDim2.new(0.5, 0, 0.5, math.sin(t * 2.2) * 4 * d.u)
		local rot = math.sin(t * 1.3) * 3
		if d.kick_t ~= nil then
			local k = (os.clock() - d.kick_t) / 0.6
			if k >= 1 then
				d.kick_t = nil
			else
				rot += -16 * (1 - k) ^ 2 * math.cos(k * math.pi * 2.5)
			end
		end
		d.icon.Rotation = rot
		d.glow.BackgroundTransparency = 0.8 + 0.06 * math.sin(t * 2.6)
		local gs = 1 + 0.06 * math.sin(t * 2.6)
		local base = d.ground.AbsoluteSize.Y * 0.6
		d.glow.Size = UDim2.fromOffset(base * gs, base * gs)
		for i, sp in d.specks do
			local a = t * (0.6 + i * 0.13) + i * 1.25
			local rx = 0.18 + 0.05 * (i % 3)
			sp.Position = UDim2.new(0.5 + math.cos(a) * rx, 0, 0.5 + math.sin(a) * rx * 1.6, 0)
		end
	end
	local pulse = 0.45 + 0.3 * math.sin(t * 4)
	for _, r in self._rows do
		if r.status == "buy" then
			r.glow.ImageTransparency = pulse
		end
	end
	-- the DNA balance counts to its value
	local _, dna = self:_money()
	if self._shown_dna ~= dna then
		local diff = dna - self._shown_dna
		local step = math.max(1, math.ceil(math.abs(diff) * math.min(1, delta * 10)))
		self._shown_dna += if diff > 0 then math.min(step, diff) else math.max(-step, diff)
		self._balance:set_text(tostring(self._shown_dna))
	end
end

-- ---------------------------------------------------------------------------------------------
-- Open / close / layout
-- ---------------------------------------------------------------------------------------------

function EvolveScreen.refresh(self)
	if not self.is_open then
		return
	end
	local owned = self:_money()
	local changed = self._shown_tree ~= self.tree
	for _, t in Traits.list do
		if t.tree == self.tree and self:_visible(t, owned) ~= ((self._shown_ids or {})[t.id] == true) then
			changed = true
			break
		end
	end
	if changed then
		self:_build_list("new")
	end
	self:_refresh_list()
	self:_build_cta()
	self:_refresh_meters(false)
end

function EvolveScreen.open(self)
	if self.is_open then
		return
	end
	self.is_open = true
	self:set_visible(true)
	self._panel:set_modulate_a(1.0)
	self._dim:set_modulate_a(0.0)
	W.fade(self._dim, 1.0, 0.2)
	UICtx.pop_in(self._panel, 0.0, 0.94, 0.3)
	self.ctx:sfx("open")
	local _, dna = self:_money()
	self._shown_dna = dna
	self._balance:set_text(tostring(dna))
	-- open on the Transmission tab, on something worth doing there: the cheapest it buys (or the one
	-- picked before, if it is still buyable there)
	local sel = Traits.by_id[self._sel or ""]
	local keep = sel ~= nil and sel.tree == "transmission" and self:_status(self._sel) == "buy"
	if not keep then
		self._sel = self:_suggest("transmission")
	end
	self.selected = self._sel
	local t = Traits.by_id[self._sel or ""]
	if t ~= nil then
		self.tree = t.tree
	end
	self._pop_next = true
	self:apply_layout()
end

function EvolveScreen.close(self, quiet: boolean?)
	if not self.is_open then
		return
	end
	self.is_open = false
	if not quiet then
		self.ctx:sfx("close")
	end
	local tw = self:create_tween():set_parallel(true)
	tw:tween_property(self._dim, "modulate:a", 0.0, 0.15)
	tw:tween_property(self._panel, "modulate:a", 0.0, 0.15)
	tw:chain():tween_callback(function()
		if not self.is_open then
			self:set_visible(false)
		end
	end)
	self.closed:Fire()
end

function EvolveScreen.apply_layout(self)
	local ctx = self.ctx
	local area = ctx:clear_rect()
	local compact = ctx.compact
	self._panel:set_padding(if compact then 14 else 20, if compact then 10 else 16, if compact then 14 else 20, if compact then 10 else 16)
	self._v:set_separation(if compact then 8 else 12)
	self._sub:set_visible(not compact)
	local chrome_h = if compact then 34 + 8 + 20 else 40 + 12 + 32
	local body_h = math.floor(area.Height - chrome_h - 8)
	local dw, dh, vw, vh
	if compact then
		dw = math.clamp(math.floor(area.Width * 0.42), 230, 360)
		vw = math.clamp(area.Width - dw - 14 - 40, 220, EvolveScreen.VIEW_W)
		vh = math.clamp(body_h - 42, 200, EvolveScreen.VIEW_H)
	else
		dw = EvolveScreen.DETAIL_W
		vw = EvolveScreen.VIEW_W
		vh = math.clamp(body_h - 42, 260, EvolveScreen.VIEW_H)
	end
	dh = vh + 42
	self._view = Vector2.new(vw, vh)
	local tree = self._view
	self._detail_size = Vector2.new(dw, dh)
	self._list_host:set_min_size(tree)
	self._detail_host:set_min_size(Vector2.new(dw, dh))
	self:_layout_meters()
	for t, chip in self._tabs do
		chip:set_pressed_no_signal(t == self.tree)
	end
	if self.is_open then
		self:_build_list(self._pop_next == true)
		self._pop_next = false
		self:_build_detail(false)
		self:_refresh_list()
	end
	local sz = self._panel:get_combined_minimum_size()
	-- (too big for the screen, a phone's or a TV's safe area: drawn smaller, centred)
	local s = PUI.fit(self._panel, area.Width - 12.0, area.Height - 6.0)
	local p = area.Min + (Vector2.new(area.Width, area.Height) - sz) * 0.5
	local y = if s < 1 then p.Y else math.max(p.Y, area.Min.Y + 4.0)
	local rp = Vector2.new(math.floor(p.X + 0.5), math.floor(y + 0.5))
	self._panel:set_offsets(rp.X, rp.Y, rp.X, rp.Y)
	self._panel:reset_size()
end

--- The three meters in the header: INFECTIVITY / SEVERITY / LETHALITY, a label over a slim bar each.
function EvolveScreen._layout_meters(self)
	local u = UITheme.scale
	local compact = self.ctx.compact
	local each = if compact then 64 else 92
	local gap = if compact then 8 else 12
	self._meters_host:set_min_size(Vector2.new(each * 3 + gap * 2, 28))
	local fr = self._meter_frame
	for _, ch in fr:GetChildren() do
		ch:Destroy()
	end
	table.clear(self._meter_bars)
	for i, m in { { "INFECTIVITY", PUI.INFECTED }, { "SEVERITY", UITheme.AMBER }, { "LETHALITY", Color3.fromRGB(200, 200, 215) } } do
		local f = new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset((i - 1) * (each + gap) * u, 2 * u),
			Size = UDim2.fromOffset(each * u, 24 * u),
			ZIndex = 41,
		}, fr)
		new("TextLabel", {
			BackgroundTransparency = 1,
			Text = m[1],
			FontFace = FONT_B,
			TextSize = math.floor((if compact then 8 else 10) * u),
			TextColor3 = MUTED,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 12 * u),
			ZIndex = 42,
		}, f)
		local track = new("Frame", {
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 15 * u),
			Size = UDim2.new(1, 0, 0, 6 * u),
			ZIndex = 42,
		}, f)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
		local fill = new("Frame", {
			BackgroundColor3 = m[2],
			BorderSizePixel = 0,
			Size = UDim2.fromScale(0, 1),
			ZIndex = 43,
		}, track)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
		self._meter_bars[i] = fill
	end
	self:_refresh_meters(true)
end

--- The EVOLVE button's rect in logical px (the tutorial's mark), or nil when it isn't one to press.
function EvolveScreen.buy_rect(self): any
	local d = self._detail
	if not self.is_open or d == nil or not d.buy_on then
		return nil
	end
	local host = self._detail_host:get_global_rect()
	local min = host.Min + Vector2.new(0, d.button_y)
	return Rect.new(min, min + Vector2.new(d.width, d.button_h))
end

return EvolveScreen
