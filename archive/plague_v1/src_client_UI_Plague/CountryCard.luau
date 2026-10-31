--!nonstrict
-- RoPlague: the card for the country under the player's click (where RoFront's target card sat):
-- its people (healthy / infected / dead), what it is like (climate, wealth, crowding) and what its
-- government has shut. Signal: closed().

local UITheme = require("../UITheme")
local W = require("../Widgets")
local GlassPanel = require("../GlassPanel")
local UICtx = require("../UICtx")
local FillBar = require("../FillBar")
local PUI = require("./PUI")
local Signal = UITheme.core("Signal")

local CountryCard = W.class(W.Control)

CountryCard.WIDTH = 250
local WEALTH = { "Very poor", "Poor", "Middle income", "Wealthy", "Very wealthy" }
local CLIMATE = { hot = "Hot", temperate = "Temperate", cold = "Cold" }
local DENSITY = { urban = "Crowded", normal = "Average density", rural = "Rural" }
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
	self._traits = UITheme.label("", 11, 600, UITheme.TEXT_2)
	self._traits:set_autowrap(true)
	self._traits:set_min_size(Vector2.new(CountryCard.WIDTH - 32, 0))
	v:add_child(self._traits)
	self._closures = UITheme.label("", 11, 700, UITheme.AMBER)
	self._closures:set_autowrap(true)
	self._closures:set_min_size(Vector2.new(CountryCard.WIDTH - 32, 0))
	v:add_child(self._closures)
	self:set_visible(false)
	return self
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
	panel.offset_left = x
	panel.offset_right = x
	panel.offset_top = y
	panel.offset_bottom = y
	panel:reset_size()
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
		local bits = {}
		table.insert(bits, CLIMATE[meta.climate] or "")
		table.insert(bits, WEALTH[meta.wealth] or "")
		table.insert(bits, DENSITY[meta.density] or "")
		local links = {}
		if #meta.airports > 0 then
			table.insert(links, #meta.airports .. (if #meta.airports == 1 then " airport" else " airports"))
		end
		if #meta.ports > 0 then
			table.insert(links, #meta.ports .. (if #meta.ports == 1 then " port" else " ports"))
		end
		if #meta.neighbors == 0 then
			table.insert(links, "an island")
		end
		self._traits:set_text(table.concat(bits, " · ") .. (if #links > 0 then "\n" .. table.concat(links, ", ") else ""))
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
end

return CountryCard
