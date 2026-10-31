--!nonstrict
-- RoPlague: the Evolve screen. Three tabs (Transmission, Symptoms, Abilities); each tree is a grid of
-- trait nodes joined by their links (Data/Traits: col / row / req), a detail panel for the selected
-- trait with EVOLVE / DEVOLVE, and the disease's infectivity / severity / lethality meters.
-- Built on the Arsenal window's recipe (PUI.Modal). Purchases apply at once (Session.send_now), so the
-- game can stay paused while it is open.
-- Signals: closed (from the modal).

local UITheme = require("../UITheme")
local W = require("../Widgets")
local UICtx = require("../UICtx")
local PUI = require("./PUI")
local Traits = UICtx.data("Traits")

local EvolveScreen = {}
EvolveScreen.__index = EvolveScreen

EvolveScreen.CELL = Vector2.new(84, 72)
EvolveScreen.NODE = Vector2.new(74, 52)
EvolveScreen.DETAIL_W = 250

local TREE_COLORS = {
	transmission = Color3.fromRGB(255, 96, 96),
	symptoms = Color3.fromRGB(255, 170, 70),
	abilities = Color3.fromRGB(110, 190, 255),
}

local FX_TEXT = {
	{ "beta", "Infectivity", 100, "%+.1f" },
	{ "hot", "Infectivity in hot countries", 100, "%+.1f" },
	{ "urban", "Infectivity in crowded countries", 100, "%+.1f" },
	{ "rural", "Infectivity in rural countries", 100, "%+.1f" },
	{ "air", "Spread by air", 100, "%+.0f%%" },
	{ "water", "Spread by sea", 100, "%+.0f%%" },
	{ "land", "Spread across borders", 100, "%+.0f%%" },
	{ "stow", "Slips past closed ports", 100, "%+.0f%%" },
	{ "sev", "Severity", 1, "%+.1f" },
	{ "leth", "Lethality", 1000, "%+.1f" },
	{ "cold", "Cold resistance", 1, "+%d" },
	{ "heat", "Heat resistance", 1, "+%d" },
	{ "drug", "Drug resistance", 1, "+%d" },
	{ "resist", "Cure needs more work", 100, "%+.0f%%" },
	{ "lock", "No random mutations", 0, "" },
}

function EvolveScreen.new(c: any)
	local self = setmetatable({}, EvolveScreen)
	self.ctx = c
	-- DNA in the title row
	self._dna = UITheme.label("DNA 0", 15, 800, PUI.DNA)
	self._dna.size_flags_vertical = W.SHRINK_CENTER
	local m = PUI.Modal.new(c, "EVOLVE", { sep = 12, head_extra = self._dna })
	self.modal = m
	self.closed = m.closed
	-- tabs
	local tabs = UITheme.hbox(6)
	self._tabs = {}
	self.tree = "transmission"
	for _, tree in Traits.TREES do
		local chip = PUI.chip(string.upper(Traits.TREE_NAMES[tree]), 34.0)
		chip:set_min_size(Vector2.new(140, 34))
		chip.pressed:Connect(function()
			self:set_tree(tree)
		end)
		self._tabs[tree] = chip
		tabs:add_child(chip)
	end
	m.body:add_child(tabs)
	-- graph + detail
	local row = UITheme.hbox(16)
	m.body:add_child(row)
	local host = W.Control.new()
	host:set_mouse_filter(W.MOUSE_PASS)
	self._host = host
	row:add_child(host)
	self._canvas = UICtx.canvas(host.gui, "Tree")
	self._canvas.ZIndex = 40
	local detail = UITheme.vbox(8)
	detail:set_min_size(Vector2.new(EvolveScreen.DETAIL_W, 0))
	row:add_child(detail)
	self._d_name = UITheme.label("", 18, 800, UITheme.TEXT)
	detail:add_child(self._d_name)
	self._d_tree = UITheme.label("", 10, 800, UITheme.TEXT_3, 1.6)
	detail:add_child(self._d_tree)
	self._d_desc = UITheme.label("", 12, 500, UITheme.TEXT_2)
	self._d_desc:set_autowrap(true)
	self._d_desc:set_min_size(Vector2.new(EvolveScreen.DETAIL_W, 0))
	detail:add_child(self._d_desc)
	self._d_fx = UITheme.label("", 12, 700, UITheme.TEXT)
	self._d_fx:set_autowrap(true)
	self._d_fx:set_min_size(Vector2.new(EvolveScreen.DETAIL_W, 0))
	detail:add_child(self._d_fx)
	local spacer = W.Control.new()
	spacer.size_flags_vertical = W.EXPAND_FILL
	detail:add_child(spacer)
	self._d_price = UITheme.label("", 13, 700, PUI.DNA)
	detail:add_child(self._d_price)
	local btns = UITheme.hbox(8)
	self._buy = UITheme.button("EVOLVE", "PrimaryButton", "", 44.0)
	self._buy.size_flags_horizontal = W.EXPAND_FILL
	self._buy.pressed:Connect(function()
		self:_act("evolve")
	end)
	btns:add_child(self._buy)
	self._sell = UITheme.button("DEVOLVE", "DangerButton", "", 44.0)
	self._sell.pressed:Connect(function()
		self:_act("devolve")
	end)
	btns:add_child(self._sell)
	detail:add_child(btns)
	-- meters
	local meters = UITheme.hbox(18)
	self._m_inf = PUI.meter("Infectivity", PUI.INFECTED, 170)
	self._m_sev = PUI.meter("Severity", UITheme.AMBER, 170)
	self._m_leth = PUI.meter("Lethality", Color3.fromRGB(200, 200, 215), 170)
	meters:add_child(self._m_inf.node)
	meters:add_child(self._m_sev.node)
	meters:add_child(self._m_leth.node)
	m.body:add_child(meters)
	self._nodes = {} :: { [string]: any }
	self._lines = {} :: { Frame }
	self.selected = nil :: string?
	self:set_tree("transmission")
	return self
end

function EvolveScreen.node(self)
	return self.modal
end

function EvolveScreen.open(self)
	self:refresh()
	self.modal:open()
end

function EvolveScreen.close(self)
	self.modal:close()
end

function EvolveScreen.apply_layout(self)
	local compact = self.ctx.compact == true
	if compact ~= self._compact then
		self._compact = compact
		EvolveScreen.CELL = if compact then Vector2.new(66, 58) else Vector2.new(84, 72)
		EvolveScreen.NODE = if compact then Vector2.new(60, 46) else Vector2.new(74, 52)
		self:_build_tree()
		self:refresh()
	end
	self.modal:apply_layout()
end

function EvolveScreen.set_tree(self, tree: string)
	self.tree = tree
	for t, chip in self._tabs do
		chip:set_pressed_no_signal(t == tree)
	end
	self.selected = nil
	self:_build_tree()
	self:refresh()
	if self.modal.is_open then
		self.modal:center()
	end
end

function EvolveScreen._build_tree(self)
	for _, n in self._nodes do
		n.button:Destroy()
	end
	for _, l in self._lines do
		l:Destroy()
	end
	table.clear(self._nodes)
	table.clear(self._lines)
	local cell, node = EvolveScreen.CELL, EvolveScreen.NODE
	local cols, rows = 1, 1
	local list = {}
	for _, t in Traits.list do
		if t.tree == self.tree then
			table.insert(list, t)
			cols = math.max(cols, t.col)
			rows = math.max(rows, t.row)
		end
	end
	self._host:set_min_size(Vector2.new(cols * cell.X, rows * cell.Y))
	local function centre(t: any): Vector2
		return Vector2.new((t.col - 0.5) * cell.X, (t.row - 0.5) * cell.Y)
	end
	-- links first (under the nodes)
	for _, t in list do
		for _, r in t.req or {} do
			local rt = Traits.by_id[r]
			if rt ~= nil and rt.tree == t.tree then
				local a, b = centre(rt), centre(t)
				local d = b - a
				local len = d.Magnitude
				local f = Instance.new("Frame")
				f.Name = "Link_" .. r .. "_" .. t.id
				f.BorderSizePixel = 0
				f.BackgroundColor3 = Color3.new(1, 1, 1)
				f.BackgroundTransparency = 0.82
				f.AnchorPoint = Vector2.new(0.5, 0.5)
				f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
				f.Size = UDim2.fromOffset(len, 3)
				f.Rotation = math.deg(math.atan2(d.Y, d.X))
				f.ZIndex = 41
				f:SetAttribute("from", r)
				f:SetAttribute("to", t.id)
				f.Parent = self._canvas
				table.insert(self._lines, f)
			end
		end
	end
	for _, t in list do
		local p = centre(t)
		local b = Instance.new("TextButton")
		b.Name = t.id
		b.AutoButtonColor = false
		b.Text = ""
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.fromOffset(p.X, p.Y)
		b.Size = UDim2.fromOffset(node.X, node.Y)
		b.BackgroundColor3 = Color3.fromRGB(30, 38, 66)
		b.BackgroundTransparency = 0.1
		b.ZIndex = 42
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = b
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Thickness = 1.5
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Transparency = 0.8
		stroke.Parent = b
		local name = Instance.new("TextLabel")
		name.Name = "Name"
		name.BackgroundTransparency = 1
		name.FontFace = UITheme.font(700)
		name.TextSize = 12
		name.TextWrapped = true
		name.TextColor3 = UITheme.TEXT
		name.Text = t.name
		name.Size = UDim2.new(1, -8, 1, -18)
		name.Position = UDim2.fromOffset(4, 3)
		name.ZIndex = 43
		name.Parent = b
		local price = Instance.new("TextLabel")
		price.Name = "Price"
		price.BackgroundTransparency = 1
		price.FontFace = UITheme.font(800)
		price.TextSize = 11
		price.TextColor3 = PUI.DNA
		price.Text = ""
		price.AnchorPoint = Vector2.new(0.5, 1)
		price.Position = UDim2.new(0.5, 0, 1, -3)
		price.Size = UDim2.new(1, -6, 0, 13)
		price.ZIndex = 43
		price.Parent = b
		b.MouseButton1Click:Connect(function()
			self:select(t.id)
			self.ctx:sfx("click", -1.0, 0.03)
		end)
		b.Parent = self._canvas
		self._nodes[t.id] = { button = b, stroke = stroke, name = name, price = price, trait = t }
	end
end

function EvolveScreen.select(self, id: string?)
	self.selected = id
	self:refresh()
end

local function fx_lines(t: any): string
	local out = {}
	for _, e in FX_TEXT do
		local v = t.fx[e[1]]
		if v ~= nil and v ~= 0 then
			if e[1] == "lock" then
				table.insert(out, e[2])
			else
				table.insert(out, e[2] .. "  " .. string.format(e[4], v * e[3]))
			end
		end
	end
	return table.concat(out, "\n")
end

function EvolveScreen.refresh(self)
	local s = self.ctx.state
	local p = if s ~= nil then s.plague else nil
	if p == nil then
		return
	end
	local owned = p.owned or {}
	local dna = math.floor(p.dna or 0)
	self._dna:set_text("DNA " .. dna)
	local col = TREE_COLORS[self.tree] or UITheme.AMBER
	for id, n in self._nodes do
		local t = n.trait
		local have = owned[id] == true
		local reach = Traits.reachable(id, owned)
		local price = Traits.price(id, owned)
		local b = n.button
		if have then
			b.BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.25)
			n.stroke.Color = col
			n.stroke.Transparency = 0.1
			n.name.TextColor3 = Color3.new(1, 1, 1)
			n.price.Text = "OWNED"
			n.price.TextColor3 = Color3.new(1, 1, 1)
		elseif reach then
			b.BackgroundColor3 = Color3.fromRGB(30, 38, 66)
			n.stroke.Color = if dna >= price then PUI.DNA else Color3.new(1, 1, 1)
			n.stroke.Transparency = if dna >= price then 0.15 else 0.65
			n.name.TextColor3 = UITheme.TEXT
			n.price.Text = tostring(price) .. " DNA"
			n.price.TextColor3 = if dna >= price then PUI.DNA else UITheme.TEXT_3
		else
			b.BackgroundColor3 = Color3.fromRGB(18, 22, 40)
			n.stroke.Color = Color3.new(1, 1, 1)
			n.stroke.Transparency = 0.9
			n.name.TextColor3 = UITheme.TEXT_3
			n.price.Text = "LOCKED"
			n.price.TextColor3 = UITheme.TEXT_3
		end
		b.BackgroundTransparency = if self.selected == id then 0.0 else 0.1
		if self.selected == id then
			n.stroke.Thickness = 3
		else
			n.stroke.Thickness = 1.5
		end
		local _ = t
	end
	for _, l in self._lines do
		local lit = owned[l:GetAttribute("from")] == true and owned[l:GetAttribute("to")] == true
		l.BackgroundColor3 = if lit then col else Color3.new(1, 1, 1)
		l.BackgroundTransparency = if lit then 0.2 else 0.82
	end
	-- detail
	local id = self.selected
	local t = if id ~= nil then Traits.by_id[id] else nil
	if t == nil then
		self._d_name:set_text(string.upper(Traits.TREE_NAMES[self.tree]))
		self._d_tree:set_text("")
		self._d_desc:set_text(if self.tree == "transmission"
			then "How the disease travels: through the air, water, animals and across borders. Spread first, so you reach every country before the world wakes up."
			elseif self.tree == "symptoms"
			then "What the disease does to its hosts. Symptoms spread it faster, but make the world notice. Deadly ones win the game, and also speed up the cure."
			else "How the disease survives: harsh climates, medicine and the cure itself.")
		self._d_fx:set_text("Select a trait to see what it does.")
		self._d_price:set_text("")
		self._buy:set_visible(false)
		self._sell:set_visible(false)
	else
		local have = owned[id] == true
		local price = Traits.price(id, owned)
		self._d_name:set_text(t.name)
		self._d_tree:set_text(string.upper(Traits.TREE_NAMES[t.tree]))
		self._d_desc:set_text(t.desc)
		self._d_fx:set_text(fx_lines(t))
		self._buy:set_visible(not have)
		self._sell:set_visible(have)
		if have then
			self._d_price:set_text(("Devolve for +%d DNA"):format(math.floor(t.cost * Traits.REFUND)))
			self._sell:set_disabled(not Traits.can_devolve(id, owned))
		elseif not Traits.reachable(id, owned) then
			local names = {}
			for _, r in t.req or {} do
				local rt = Traits.by_id[r]
				table.insert(names, if rt then rt.name else r)
			end
			self._d_price:set_text((if (t.req_n or 1) > 1 then "Needs " .. t.req_n .. " of: " else "Needs: ") .. table.concat(names, ", "))
			self._buy:set_disabled(true)
		else
			self._d_price:set_text(("%d DNA  (you have %d)"):format(price, dna))
			self._buy:set_disabled(dna < price)
		end
	end
	self._m_inf.set(p.inf or 0)
	self._m_sev.set(p.sev or 0)
	self._m_leth.set(p.leth or 0)
end

function EvolveScreen._act(self, kind: string)
	local id = self.selected
	if id == nil then
		return
	end
	local ctx = self.ctx
	local intent = { type = kind, id = id }
	local ok = ctx:session_call("send_now", { intent })
	if ok == nil then
		ctx:send(intent)
	end
	ctx:sfx(if kind == "evolve" then "unlock" else "confirm")
	self:refresh()
end

return EvolveScreen
