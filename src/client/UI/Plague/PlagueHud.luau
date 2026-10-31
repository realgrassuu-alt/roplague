--!nonstrict
-- RoPlague HUD: the bottom bar (where RoFront's command bar sat). Left to right: the disease's name and
-- the day; DNA; the world's healthy / infected / dead; the infectivity / severity / lethality meters;
-- the game speed; EVOLVE (and the pathogen's power when it has one). Phones drop the meters and the
-- dead counter.
-- Signals: evolve_pressed(), ability_pressed(), speed_changed(speed), rename_pressed(),
-- countries_pressed() (the list of the countries not infected yet, WorldList).

local UITheme = require("../UITheme")
local W = require("../Widgets")
local GlassPanel = require("../GlassPanel")
local UICtx = require("../UICtx")
local PUI = require("./PUI")
local Signal = UITheme.core("Signal")
local Defs = UICtx.core("Defs")
local Traits = UICtx.data("Traits")

local BuildButton = require("../BuildButton")
local ShopSlot = require("../ShopSlot")

local PlagueHud = W.class(W.Control)

PlagueHud.SPEEDS = { { 0, "II" }, { 1, "1×" }, { 2, "2×" }, { 4, "4×" } }

--- A number with its caption; `rate`: a "+12.3K/s" beside the caption, as RoWorld's TROOPS / GOLD.
local function counter(title: string, col: Color3, rate: boolean?)
	local v = UITheme.vbox(0)
	v.size_flags_vertical = W.SHRINK_CENTER
	local tr = UITheme.hbox(8)
	local t = UITheme.label(title, 9, 800, UITheme.TEXT_3, 1.4)
	tr:add_child(t)
	local r = nil
	if rate then
		r = UITheme.label("", 9, 800, UITheme.GREEN)
		tr:add_child(r)
	end
	v:add_child(tr)
	local n = UITheme.label("0", 17, 800, col)
	v:add_child(n)
	return v, n, t, r
end

--- "+12.3K/s" (a rate per second; small ones keep a decimal).
local function per_s(x: number): string
	local a = math.abs(x)
	local sgn = if x < 0 then "-" else "+"
	if a < 10 then
		return ("%s%.1f/s"):format(sgn, a)
	end
	return sgn .. UITheme.fmt_troops(a) .. "/s"
end

function PlagueHud.new(c: any)
	local self = setmetatable({}, PlagueHud.__mt)
	W.Control._init(self)
	self.ctx = c
	self.evolve_pressed = Signal.new()
	self.ability_pressed = Signal.new()
	self.speed_changed = Signal.new()
	self.rename_pressed = Signal.new()
	self.countries_pressed = Signal.new()
	--- a 1v1's cure side, once research has started: a building picked in the build row (its key)
	self.build_picked = Signal.new()
	self.speed = 1
	--- how many countries the world has (set by PlagueLink)
	self.country_total = 0
	--- RoPlague multiplayer (PlagueLink.set_role): a server-run match has no speed buttons; "cure" is a
	--- 1v1's cure side (its funds where the DNA is, RAISE ALARM where EVOLVE is)
	self.online = false
	self.role = "plague"
	self:set_mouse_filter(W.MOUSE_IGNORE)
	self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	local panel = GlassPanel.new(18.0, 10.0, UITheme.R_LG, true, 24)
	panel:set_mouse_filter(W.MOUSE_STOP)
	self.panel = panel
	self:add_child(panel)
	local row = UITheme.hbox(14)
	self._row = row
	panel:add_child(row)
	-- the disease: its badge, its name (with the rename pencil) and the day
	local badge = UITheme.icon_rect("virus", 34, PUI.INFECTED)
	badge.size_flags_vertical = W.SHRINK_CENTER
	row:add_child(badge)
	local who = UITheme.vbox(0)
	who.size_flags_vertical = W.SHRINK_CENTER
	local name_row = UITheme.hbox(4)
	self._name = UITheme.label("", 15, 800, PUI.INFECTED)
	self._name.size_flags_vertical = W.SHRINK_CENTER
	name_row:add_child(self._name)
	local pen = W.Button.new("", "GhostButton")
	pen:set_icon("pencil")
	pen.expand_icon = true
	pen:set_min_size(Vector2.new(26, 26))
	pen:add_theme_constant_override("icon_max_width", 13)
	pen:add_theme_stylebox_override("normal", UITheme.empty_box(6, 6))
	pen:add_theme_stylebox_override("hover", UITheme.flat(UITheme.FILL, 6, UITheme.CLEAR, 0, 6, 6))
	pen.size_flags_vertical = W.SHRINK_CENTER
	pen.pressed:Connect(function()
		self.rename_pressed:Fire()
	end)
	self._pen = pen
	name_row:add_child(pen)
	who:add_child(name_row)
	self._day = UITheme.label("Day 0", 11, 600, UITheme.TEXT_2)
	who:add_child(self._day)
	row:add_child(who)
	row:add_child(UITheme.vdivider(34.0))
	-- DNA
	local dna_icon = UITheme.icon_rect("dna", 26, PUI.DNA)
	dna_icon.size_flags_vertical = W.SHRINK_CENTER
	row:add_child(dna_icon)
	local dna, dna_n, dna_t, dna_r = counter("DNA", PUI.DNA, true)
	self._dna = dna_n
	self._dna_title = dna_t
	self._dna_rate = dna_r
	self._dna_icon = dna_icon
	dna_n:set_font_size(20)
	row:add_child(dna)
	row:add_child(UITheme.vdivider(34.0))
	-- the world
	local h, hn = counter("HEALTHY", PUI.HEALTHY)
	self._h = hn
	row:add_child(h)
	local i, iname, _, i_rate = counter("INFECTED", PUI.INFECTED, true)
	self._i = iname
	self._i_rate = i_rate
	row:add_child(i)
	local d, dn, _, d_rate = counter("DEAD", PUI.DEAD, true)
	self._d_rate = d_rate
	self._dead_box = d
	self._d = dn
	row:add_child(d)
	local cn, cnn = counter("COUNTRIES", UITheme.TEXT)
	self._c = cnn
	row:add_child(cn)
	-- the ones it has not reached yet: a press lists them (WorldList)
	local left = UITheme.button("", "GlassButton", "world", 34.0)
	left:set_font_size(12)
	left:add_theme_constant_override("icon_max_width", 16)
	left.size_flags_vertical = W.SHRINK_CENTER
	left.pressed:Connect(function()
		self.countries_pressed:Fire()
	end)
	self._left = left
	row:add_child(left)
	self._div2 = UITheme.vdivider(34.0)
	row:add_child(self._div2)
	-- meters
	local meters = UITheme.vbox(4)
	meters.size_flags_vertical = W.SHRINK_CENTER
	self._m_inf = PUI.meter("Infectivity", PUI.INFECTED, 96)
	self._m_sev = PUI.meter("Severity", UITheme.AMBER, 96)
	self._m_leth = PUI.meter("Lethality", Color3.fromRGB(200, 200, 215), 96)
	meters:add_child(self._m_inf.node)
	meters:add_child(self._m_sev.node)
	meters:add_child(self._m_leth.node)
	self._meters = meters
	row:add_child(meters)
	self._div3 = UITheme.vdivider(34.0)
	row:add_child(self._div3)
	-- speed
	local speeds = UITheme.hbox(4)
	speeds.size_flags_vertical = W.SHRINK_CENTER
	self._speeds = {}
	for _, sp in PlagueHud.SPEEDS do
		local b = PUI.chip(sp[2], 30.0)
		b:set_min_size(Vector2.new(36, 30))
		b.pressed:Connect(function()
			self:set_speed(sp[1], true)
		end)
		self._speeds[sp[1]] = b
		speeds:add_child(b)
	end
	row:add_child(speeds)
	-- the pathogen's power (Fungus)
	self._ability = UITheme.button("SPORES", "GlassButton", "", 44.0)
	self._ability:set_font_size(13)
	self._ability.pressed:Connect(function()
		self.ability_pressed:Fire()
	end)
	self._ability:set_visible(false)
	row:add_child(self._ability)
	-- evolve
	self._evolve = UITheme.button("EVOLVE", "PrimaryButton", "", 50.0)
	self._evolve:set_icon("evolve")
	self._evolve:set_font_size(16)
	self._evolve:set_min_size(Vector2.new(150, 50))
	self._evolve.pressed:Connect(function()
		self.evolve_pressed:Fire()
	end)
	row:add_child(self._evolve)
	-- a 1v1's cure side, once research has started: a slot per building in the bar itself, RoWorld's
	-- build row (pick one, then click where it goes)
	self._slots = UITheme.hbox(6)
	self._slots.size_flags_vertical = W.SHRINK_CENTER
	self._slots:set_visible(false)
	row:add_child(self._slots)
	-- RoWorld's gold SHOP slot (opens the Arsenal), closing the bar as it closes RoWorld's build row
	self.shop_wanted = Signal.new()
	local shop = ShopSlot.new(c)
	shop.size_flags_vertical = W.SHRINK_CENTER
	shop:set_block(70.0, 56.0)
	shop.wanted:Connect(function(key: string?, from: string?)
		self.shop_wanted:Fire(key, from)
	end)
	self._shop = shop
	row:add_child(shop)
	-- a red badge with a white rim in EVOLVE's top right corner: how many evolutions the DNA buys
	local u = UITheme.scale
	local badge = Instance.new("Frame")
	badge.Name = "Ready"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -3 * u, 0, 3 * u)
	badge.Size = UDim2.fromOffset(32 * u, 32 * u)
	badge.BackgroundColor3 = Color3.fromRGB(228, 36, 44)
	badge.BorderSizePixel = 0
	badge.ZIndex = 80
	badge.Visible = false
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = badge
	local bs = Instance.new("UIStroke")
	bs.Color = Color3.new(1, 1, 1)
	bs.Thickness = 2.5 * u
	bs.Parent = badge
	local bt = Instance.new("TextLabel")
	bt.BackgroundTransparency = 1
	bt.Size = UDim2.fromScale(1, 1)
	bt.FontFace = UITheme.font(800)
	bt.TextSize = math.floor(19 * u)
	bt.TextXAlignment = Enum.TextXAlignment.Center
	bt.TextYAlignment = Enum.TextYAlignment.Center
	bt.AnchorPoint = Vector2.new(0.5, 0.5)
	bt.Position = UDim2.fromScale(0.5, 0.5)
	bt.TextColor3 = Color3.new(1, 1, 1)
	bt.Text = ""
	bt.ZIndex = 81
	bt.Parent = badge
	self._badge_scale = Instance.new("UIScale")
	self._badge_scale.Parent = badge
	badge.Parent = self._evolve.gui
	self._badge, self._badge_text = badge, bt
	self._n_dna = PUI.counter(self._dna, function(v)
		return tostring(math.floor(v + 0.5))
	end)
	self._n_h = PUI.counter(self._h, PUI.people)
	self._n_i = PUI.counter(self._i, PUI.people)
	self._n_d = PUI.counter(self._d, PUI.people)
	self._n_c = PUI.counter(self._c, function(v)
		local n = math.floor(v + 0.5)
		return if self.country_total > 0 then ("%d / %d"):format(n, self.country_total) else tostring(n)
	end)
	self:set_process(true)
	self:set_speed(1, false)
	self._build_btns = {}
	self.research = false
	--- the building being placed (its key), shown pressed in its slot
	self.placing = nil
	return self
end

--- The cure's buildings, in the build row's order: { {key, name, cost, icon, desc} }.
function PlagueHud.set_build_list(self, list: { any })
	for _, b in self._build_btns do
		b.btn:queue_free()
	end
	self._build_btns = {}
	for n, it in list do
		-- (RoWorld's own build slot, drawn as the RoWorld structure the building is shown as: its glyph,
		-- hotkey and cost, red while unaffordable, its card on hover; only its numbers are the cure's)
		local key, name, cost, desc, range = it[1], it[6] or it[2], it[3], it[5], it[7]
		local b = BuildButton.new(self.ctx, it[4], tostring(n))
		b._funds = 0
		b.refresh = function(bb: any)
			local ok = (bb._funds or 0) >= cost
			local reason = if ok then "" else ("Need %d more funds"):format(cost - (bb._funds or 0))
			local av = bb._av
			if av.ok ~= ok or av.cost ~= cost or av.reason ~= reason then
				bb._av = { ok = ok, locked = false, reason = reason, cost = cost }
				bb:_redraw()
			end
		end
		b.hint_spec = function(bb: any): { [string]: any }
			local rows = { { "Cost", tostring(cost) .. " funds", UITheme.CYAN } }
			if range ~= nil then
				table.insert(rows, { "Range", tostring(range) .. " tiles", UITheme.TEXT })
			end
			return {
				title = name,
				badge = if not bb.ctx.touch then bb.hotkey else "",
				badge_color = UITheme.TEXT_2,
				body = desc,
				rows = rows,
				hint = if bb._av.ok
					then ((if bb.ctx.touch then "Tap" else "Click") .. ", then choose a spot on the map")
					else bb._av.reason,
				hint_color = if bb._av.ok then UITheme.CYAN else UITheme.RED,
				hint_icon = if bb._av.ok then "target" else "info",
			}
		end
		b.chosen:Connect(function()
			if not b._av.ok then
				b:deny()
				return
			end
			self.build_picked:Fire(key)
		end)
		b:set_compact(self.ctx.compact, self.ctx.touch)
		self._slots:add_child(b)
		table.insert(self._build_btns, { btn = b, cost = cost, key = key })
	end
end

--- The building being placed (nil: none): its slot reads pressed.
function PlagueHud.set_placing(self, key: string?)
	self.placing = key
	for _, b in self._build_btns do
		b.btn:set_active(b.key == key)
	end
end

--- The cure side: research has started (EVOLVE's place reads BUILD) or not yet (RAISE ALARM).
function PlagueHud.set_research(self, on: boolean)
	if self.research == on then
		return
	end
	self.research = on
	if not on then
		self:set_placing(nil)
	end
end

--- Every frame: the numbers count to their values.
function PlagueHud._process(self, delta: number)
	if not self.visible then
		return
	end
	for _, c in { self._n_dna, self._n_h, self._n_i, self._n_d, self._n_c } do
		c.step(delta)
	end
end

--- Multiplayer: `online` (server-run: no speed buttons), `role` "plague" | "cure".
function PlagueHud.set_role(self, online: boolean, role: string)
	self.online = online
	self.role = role
	local cure = role == "cure"
	for _, b in self._speeds do
		b:set_visible(not online)
	end
	self._pen:set_visible(not online)
	self._dna_title:set_text(if cure then "FUNDS" else "DNA")
	self._dna_icon:set_icon(if cure then "cure" else "dna")
	UITheme.set_font_color(self._dna, if cure then UITheme.CYAN else PUI.DNA)
	self._evolve:set_text(if cure then "RAISE ALARM" else "EVOLVE")
	self._evolve:set_icon(if cure then "cure" else "evolve")
	self._slots:set_visible(cure and self.research)
	if not cure then
		self._evolve:set_disabled(false)
	end
end

function PlagueHud.set_speed(self, speed: number, by_player: boolean)
	self.speed = speed
	for s, b in self._speeds do
		b:set_pressed_no_signal(s == speed)
	end
	if by_player then
		self.speed_changed:Fire(speed)
	end
end

function PlagueHud.apply_layout(self)
	local ctx = self.ctx
	local compact = ctx.compact
	-- (the infectivity / severity / lethality meters live in the Evolve window: a simpler bar)
	self._meters:set_visible(false)
	self._div3:set_visible(false)
	self._dead_box:set_visible(not compact)
	for _, b in self._build_btns do
		b.btn:set_compact(compact, ctx.touch)
	end
	self._shop:set_block(if compact then 58.0 else 70.0, if compact then 46.0 else 56.0)
	self._row:set_separation(if compact then 9 else 14)
	self.panel:set_padding(if compact then 12.0 else 18.0, 8.0, if compact then 10.0 else 14.0, 8.0)
	local panel = self.panel
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = W.GROW_BOTH
	panel.grow_vertical = W.GROW_BEGIN
	local y = -(12.0 + ctx.insets.w)
	-- (wider than the screen: drawn smaller, kept on the bottom edge)
	local vp = ctx.vp
	local _, _, dy = PUI.fit(panel, vp.X - ctx.insets.x - ctx.insets.z - 16.0, vp.Y * 0.3, 0.5, 1.0)
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = y + dy
	panel.offset_bottom = y + dy
	panel:reset_size()
end

function PlagueHud.top_edge(self): number
	return self.panel:get_global_rect().Min.Y
end

--- Twice a second / on every plague update.
function PlagueHud.refresh(self)
	local s = self.ctx.state
	local p = if s ~= nil then s.plague else nil
	if p == nil then
		return
	end
	self._name:set_text(string.upper(tostring(p.name or "")))
	local since = if s.playing_since >= 0 then s.tick - s.playing_since else 0
	self._day:set_text("Day " .. UICtx.commas(math.floor(since / 10)))
		self._n_dna.set(math.floor(if self.role == "cure" then (p.funds or 0) else (p.dna or 0)))
	if self.role == "cure" then
		self:set_research(p.research == true)
		local funds = math.floor(p.funds or 0)
		for _, b in self._build_btns do
			b.btn._funds = funds
			b.btn:refresh()
		end
	end
	self._shop:refresh()
	-- the rates beside the numbers (RoWorld's "+366/s"), over the last second or so of real time
	local now = os.clock()
	local smp = self._smp
	local money = if self.role == "cure" then (p.funds or 0) else (p.dna or 0)
	if smp == nil or now - smp.t >= 1.0 then
		if smp ~= nil then
			local dt = now - smp.t
			local ri = ((p.I or 0) - smp.i) / dt
			local rd = ((p.D or 0) - smp.d) / dt
			local rm = math.max(0, money - smp.m) / dt
			-- (eased, so one spend or a pause does not make them jump)
			local e = self._ease or { i = ri, d = rd, m = rm }
			e.i, e.d, e.m = e.i * 0.4 + ri * 0.6, e.d * 0.4 + rd * 0.6, e.m * 0.6 + rm * 0.4
			self._ease = e
			self._i_rate:set_text(if math.abs(e.i) >= 0.5 then per_s(e.i) else "")
			UITheme.set_font_color(self._i_rate, if e.i >= 0 then UITheme.GREEN else UITheme.RED)
			self._d_rate:set_text(if e.d >= 0.5 then per_s(e.d) else "")
			UITheme.set_font_color(self._d_rate, UITheme.TEXT_2)
			self._dna_rate:set_text(if e.m >= 0.05 then per_s(e.m) else "")
		end
		self._smp = { t = now, i = p.I or 0, d = p.D or 0, m = money }
	end
	self._n_h.set(p.H or 0)
	self._n_i.set(p.I or 0)
	self._n_d.set(p.D or 0)
	self._m_inf.set(p.inf or 0)
	self._m_sev.set(p.sev or 0)
	self._m_leth.set(p.leth or 0)
	local reached = 0
	for _, r in p.countries or {} do
		if (r.I or 0) >= 1 or (r.D or 0) >= 1 then
			reached += 1
		end
	end
	self._n_c.set(reached)
	local left = math.max(0, self.country_total - reached)
	self._left:set_text(if self.ctx.compact then tostring(left) elseif left > 0 then ("%d LEFT"):format(left) else "ALL")
	if self.role == "cure" then
		-- (the cure's side: RAISE ALARM until research starts, then BUILD; no evolutions, no pathogen power)
		self._badge.Visible = false
		self._ability:set_visible(false)
		-- (research started: the building slots take RAISE ALARM's place)
		self._evolve:set_visible(p.research ~= true)
		self._slots:set_visible(p.research == true)
		if p.research ~= true then
			local cost = self.alarm_cost or 5
			self._evolve:set_disabled((p.funds or 0) < cost or s.phase ~= Defs.PHASE_PLAYING)
			self._evolve:set_text(("RAISE ALARM  %d"):format(cost))
		end
		return
	end
	self._evolve:set_visible(true)
	-- EVOLVE says how many evolutions the DNA buys right now
	local owned = p.owned or {}
	local dna = math.floor(p.dna or 0)
	local ready = 0
	for _, t in Traits.list do
		if not owned[t.id] and Traits.reachable(t.id, owned) and Traits.price(t.id, owned, p.price_mult) <= dna then
			ready += 1
		end
	end
	self._badge.Visible = ready > 0
	self._badge_text.Text = if ready > 9 then "9+" else tostring(ready)
	if ready > (self._ready or 0) and game ~= nil then
		-- a new one to buy: the badge pops
		self._badge_scale.Scale = 1.45
		game:GetService("TweenService")
			:Create(self._badge_scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end
	self._ready = ready
	local path = Traits.pathogen_by_id[p.pathogen or ""]
	local ab = if path ~= nil and path.ability ~= nil then Traits.ABILITIES[path.ability] else nil
	self._ability:set_visible(ab ~= nil)
	if ab ~= nil then
		local left = math.max(0, math.ceil(((p.ability_ready or 0) - s.tick) / 10))
		if left > 0 then
			self._ability:set_text(string.upper(ab.name) .. "  " .. left .. "d")
			self._ability:set_disabled(true)
		else
			self._ability:set_text(string.upper(ab.name) .. "  " .. ab.cost)
			self._ability:set_disabled((p.dna or 0) < ab.cost or s.phase ~= Defs.PHASE_PLAYING)
		end
	end
end

return PlagueHud
