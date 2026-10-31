--!nonstrict
-- RoPlague: the card for the country under the player's click (where RoFront's target card sat):
-- its people (healthy / infected / dead), what it is like (climate, wealth, crowding), what its
-- government has shut, and the INFECT button (across a border, or by ship).
-- Signals: closed(), infect_pressed(country), cure_pressed(kind, country) (a 1v1's cure side: FUND,
-- CLOSE, QUARANTINE instead of INFECT; `cure_side` set by PlagueLink).
-- Hooks set by PlagueLink: top_limit(), meta_of(c), route_of(c) -> kind, src, cost, reason.

local UITheme = require("../UITheme")
local W = require("../Widgets")
local GlassPanel = require("../GlassPanel")
local UICtx = require("../UICtx")
local FillBar = require("../FillBar")
local PUI = require("./PUI")
local Signal = UITheme.core("Signal")

local CountryCard = W.class(W.Control)

CountryCard.WIDTH = 250
local WEALTH = { "Very poor", "Poor", "Average wealth", "Rich", "Very rich" }
--- climate: the word and its colour (normal keeps the card's text colour)
local CLIMATE = {
	hot = { "Hot", Color3.fromRGB(255, 92, 84) },
	temperate = { "Normal", nil },
	cold = { "Cold", Color3.fromRGB(140, 205, 255) },
}
local DENSITY = { urban = "Crowded", normal = "Average crowding", rural = "Rural" }
local CLOSED = {
	{ 1, "Airports closed" },
	{ 2, "Ports closed" },
	{ 4, "Borders closed" },
	{ 8, "Under quarantine" },
	{ 16, "Government collapsed" },
}

local function stat_row(title: string, col: Color3)
	local v = UITheme.vbox(3)
	local row = UITheme.hbox(6)
	local t = UITheme.label(title, 10, 700, UITheme.TEXT_2)
	t.size_flags_horizontal = W.EXPAND_FILL
	row:add_child(t)
	local n = UITheme.label("0", 12, 800, col)
	row:add_child(n)
	v:add_child(row)
	local bar = FillBar.new(4.0, col)
	bar:set_min_size(Vector2.new(CountryCard.WIDTH - 32, 4))
	v:add_child(bar)
	return v, n, bar
end

function CountryCard.new(c: any)
	local self = setmetatable({}, CountryCard.__mt)
	W.Control._init(self)
	self.ctx = c
	self.closed = Signal.new()
	self.infect_pressed = Signal.new()
	self.cure_pressed = Signal.new()
	--- a 1v1's cure side (PlagueLink.set_role): the card's buttons act for the cure
	self.cure_side = false
	self.country = 0
	self:set_mouse_filter(W.MOUSE_IGNORE)
	self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	local panel = GlassPanel.new(16.0, 14.0, UITheme.R_LG, true, 24)
	panel:set_mouse_filter(W.MOUSE_STOP)
	self.panel = panel
	self:add_child(panel)
	local v = UITheme.vbox(9)
	panel:add_child(v)
	local head = UITheme.hbox(8)
	self._name = UITheme.label("", 16, 800, UITheme.TEXT)
	self._name.size_flags_horizontal = W.EXPAND_FILL
	self._name.size_flags_vertical = W.SHRINK_CENTER
	head:add_child(self._name)
	head:add_child(PUI.close_button(function()
		self:hide_card()
	end))
	v:add_child(head)
	self._pop = UITheme.label("", 11, 600, UITheme.TEXT_3)
	v:add_child(self._pop)
	local h, hn, hb = stat_row("Healthy", PUI.HEALTHY)
	local i, iname, ib = stat_row("Infected", PUI.INFECTED)
	local d, dn, db = stat_row("Dead", PUI.DEAD)
	self._hn, self._hb, self._in, self._ib, self._dn, self._db = hn, hb, iname, ib, dn, db
	v:add_child(h)
	v:add_child(i)
	v:add_child(d)
	v:add_child(UITheme.hdivider())
	self._climate = UITheme.label("", 13, 800, UITheme.TEXT)
	v:add_child(self._climate)
	self._traits = UITheme.label("", 11, 600, UITheme.TEXT_2)
	self._traits:set_autowrap(true)
	self._traits:set_min_size(Vector2.new(CountryCard.WIDTH - 32, 0))
	v:add_child(self._traits)
	self._closures = UITheme.label("", 11, 700, UITheme.AMBER)
	self._closures:set_autowrap(true)
	self._closures:set_min_size(Vector2.new(CountryCard.WIDTH - 32, 0))
	v:add_child(self._closures)
	self._route = UITheme.label("", 11, 700, UITheme.TEXT_2)
	self._route:set_autowrap(true)
	self._route:set_min_size(Vector2.new(CountryCard.WIDTH - 32, 0))
	v:add_child(self._route)
	self._infect = UITheme.button("INFECT", "PrimaryButton", "", 44.0)
	self._infect:set_icon("infect")
	self._infect:set_font_size(14)
	self._infect.pressed:Connect(function()
		if self.country ~= 0 then
			self.infect_pressed:Fire(self.country)
		end
	end)
	v:add_child(self._infect)
	-- the cure's side: its actions on this country (Core/Plague/PlagueRules DUEL_COSTS)
	local cr = UITheme.vbox(6)
	self._cure_row = cr
	self._cure_btns = {}
	for _, a in CountryCard.CURE_ACTIONS do
		local b = UITheme.button("", if a[1] == "build_lab" then "PrimaryButton" else "GlassButton", a[4], 38.0)
		b:set_font_size(13)
		b.pressed:Connect(function()
			if self.country ~= 0 then
				self.cure_pressed:Fire(a[1], self.country)
			end
		end)
		self._cure_btns[a[1]] = b
		cr:add_child(b)
	end
	cr:set_visible(false)
	v:add_child(cr)
	self:set_visible(false)
	return self
end

--- The cure side's actions: kind, button text, cost, icon (Core/Plague/PlagueRules.DUEL_COSTS).
CountryCard.CURE_ACTIONS = {
	{ "fund", "FUND RESEARCH", 3, "cure" },
	{ "close", "CLOSE BORDERS", 3, "defense" },
	{ "quarantine", "QUARANTINE", 6, "sam" },
}

--- The card's buttons for the cure side (`row`: the country's plague row; `pl`: the plague mirror).
function CountryCard._refresh_cure(self, row: any, pl: any)
	self._infect:set_visible(false)
	-- (buildings are placed from the bar's slots, on the tile clicked: the card only reports)
	self._cure_row:set_visible(false)
	local funds = math.floor(tonumber(pl.funds) or 0)
	local closed = if row ~= nil then row.closed or 0 else 0
	local funding = if row ~= nil then tonumber(row.funding) or 0 else 0
	local collapsed = bit32.band(closed, 16) ~= 0
	-- (the buildings this country has: PlagueLink)
	local built = if self.built_of then self.built_of(self.country) else {}
	for _, a in CountryCard.CURE_ACTIONS do
		local b = self._cure_btns[a[1]]
		local done = built[a[1]] == true
		local blocked = collapsed or pl.research ~= true
		b:set_text(if done then (a[2] .. "  ✓") else ("%s  %d"):format(a[2], a[3]))
		b:set_disabled(done or blocked or funds < a[3])
	end
	self._route:set_text(
		if collapsed
			then "Its government has collapsed"
			elseif pl.research ~= true then "Research hasn't started: raise the alarm first"
			else ("Funds %d  ·  research here %d%%"):format(funds, math.floor(funding + 0.5))
	)
	PUI.color(self._route, UITheme.CYAN)
end

function CountryCard.show_country(self, c: number)
	if c <= 0 then
		self:hide_card()
		return
	end
	self.country = c
	self:set_visible(true)
	self:refresh(true)
	self:apply_layout()
	UICtx.pop_in(self.panel, 0.0, 0.95, 0.22)
end

function CountryCard.hide_card(self)
	if self.country == 0 and not self.visible then
		return
	end
	self.country = 0
	self:set_visible(false)
	self.closed:Fire()
end

function CountryCard.apply_layout(self)
	local ctx = self.ctx
	local panel = self.panel
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.grow_horizontal = W.GROW_BEGIN
	panel.grow_vertical = W.GROW_END
	local x = -(12.0 + ctx.insets.z)
	local y = (if self.top_limit then self.top_limit() else 80.0) + 10.0
	-- (a phone: drawn smaller to fit between the top bar and the bottom one, kept on the right edge)
	local vp = ctx.vp
	local room_h = (if self.bottom_limit then self.bottom_limit() else vp.Y - 90.0) - y - 8.0
	local _, fdx, fdy = PUI.fit(panel, vp.X * (if ctx.compact then 0.42 else 0.36), room_h, 1.0, 0.0)
	x += fdx
	y += fdy
	panel.offset_left = x
	panel.offset_right = x
	panel.offset_top = y
	panel.offset_bottom = y
	panel:reset_size()
end

--- True while a traveller (GameState.flights) is walking into country `c`.
function CountryCard._coming(self, c: number): boolean
	local s = self.ctx.state
	-- (a shared world: the local plague's travellers only)
	local me = if s.plague ~= nil and s:shared_world() then s.plague.pid else nil
	for _, f in s.flights or {} do
		if me ~= nil and f.owner ~= nil and f.owner ~= me then
			continue
		end
		if f.to_tile ~= nil and f.to_tile >= 0 and s:tile_owner(f.to_tile) == c then
			return true
		end
	end
	return false
end

function CountryCard.refresh(self, instant: boolean?)
	local c = self.country
	local s = self.ctx.state
	if c == 0 or s == nil then
		return
	end
	local info = s.owners[c]
	local meta = self.meta_of and self.meta_of(c) or nil
	local pop = if meta ~= nil then meta.pop else 0
	self._name:set_text(if info ~= nil then info.name else "")
	self._pop:set_text("Population " .. PUI.people(pop))
	local row = s:country_row(c)
	local H = if row ~= nil then row.H else pop
	local I = if row ~= nil then row.I else 0
	local D = if row ~= nil then row.D else 0
	local total = math.max(pop, 1)
	self._hn:set_text(PUI.people(H))
	self._in:set_text(PUI.people(I))
	self._dn:set_text(PUI.people(D))
	self._hb:set_target(H / total, instant)
	self._ib:set_target(I / total, instant)
	self._db:set_target(D / total, instant)
	if meta ~= nil then
		-- three details: the climate (coloured), then wealth and crowding under it
		local cl = CLIMATE[meta.climate] or CLIMATE.temperate
		self._climate:set_text(cl[1])
		PUI.color(self._climate, cl[2] or UITheme.TEXT)
		self._traits:set_text((WEALTH[meta.wealth] or "") .. "  ·  " .. (DENSITY[meta.density] or ""))
	end
	local closed = if row ~= nil then row.closed or 0 else 0
	local lines = {}
	for _, e in CLOSED do
		if bit32.band(closed, e[1]) ~= 0 then
			table.insert(lines, e[2])
		end
	end
	self._closures:set_text(if #lines > 0 then table.concat(lines, " · ") else "Open for business")
	PUI.color(self._closures, if #lines > 0 then UITheme.AMBER else UITheme.TEXT_3)
	-- what a click does (the cure's side: its own actions)
	if self.cure_side and s.plague ~= nil then
		self:_refresh_cure(row, s.plague)
		return
	end
	self._cure_row:set_visible(false)
	local foe = if self.enemy_of then self.enemy_of(c) else nil
	if foe ~= nil then
		-- a shared world: another plague holds it; take it by attacking
		local p = s.plague
		local dna = if p ~= nil then math.floor(p.dna or 0) else 0
		self._infect:set_visible(true)
		if self:_coming(c) then
			self._route:set_text(("Held by %s: your attack is on the way"):format(foe.name or "another plague"))
			PUI.color(self._route, PUI.INFECTED)
			self._infect:set_visible(false)
			return
		end
		local kind, src, cost, reason
		if self.route_of then
			kind, src, cost, reason = self.route_of(c)
		end
		if kind ~= nil then
			local troops = if self.troops_of then self.troops_of(src) else 0
			self._route:set_text(
				("Held by %s  ·  %s defending  ·  you attack with %s"):format(
					foe.name or "another plague",
					PUI.people(I),
					PUI.people(troops)
				)
			)
			PUI.color(self._route, Color3.fromRGB(255, 120, 100))
			self._infect:set_text(if kind == "sea" then ("SEND SHIP  %d DNA"):format(cost) else ("ATTACK  %d DNA"):format(cost))
			self._infect:set_icon(if kind == "sea" then "boat" else "infect")
			self._infect:set_disabled(dna < cost or troops < 1)
		else
			self._route:set_text(("Held by %s: %s"):format(foe.name or "another plague", reason or "out of reach"))
			PUI.color(self._route, UITheme.TEXT_3)
			self._infect:set_text("OUT OF REACH")
			self._infect:set_icon("infect")
			self._infect:set_disabled(true)
		end
		return
	end
	if I >= 1 or D >= 1 then
		self._route:set_text(if I >= 1 then "Your plague is spreading here" else "No one left to infect")
		PUI.color(self._route, PUI.INFECTED)
		self._infect:set_visible(false)
	elseif self:_coming(c) then
		self._route:set_text("An infected traveller is on the way")
		PUI.color(self._route, PUI.INFECTED)
		self._infect:set_visible(false)
	else
		local kind, _, cost, reason
		if self.route_of then
			kind, _, cost, reason = self.route_of(c)
		end
		local p = s.plague
		local dna = if p ~= nil then math.floor(p.dna or 0) else 0
		self._infect:set_visible(true)
		if kind == "land" then
			self._route:set_text("It borders a country you have infected")
			PUI.color(self._route, UITheme.TEXT_2)
			self._infect:set_text(("INFECT  %d DNA"):format(cost))
			self._infect:set_icon("infect")
			self._infect:set_disabled(dna < cost)
		elseif kind == "sea" then
			self._route:set_text("An infected ship can sail there")
			PUI.color(self._route, UITheme.CYAN)
			self._infect:set_text(("SEND SHIP  %d DNA"):format(cost))
			self._infect:set_icon("boat")
			self._infect:set_disabled(dna < cost)
		else
			self._route:set_text(reason or "Out of reach for now")
			PUI.color(self._route, UITheme.TEXT_3)
			self._infect:set_text("OUT OF REACH")
			self._infect:set_icon("infect")
			self._infect:set_disabled(true)
		end
	end
end

return CountryCard
