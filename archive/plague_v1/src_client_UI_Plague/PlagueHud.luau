--!nonstrict
-- RoPlague HUD: the bottom bar (where RoFront's command bar sat). Left to right: the disease's name and
-- the day; DNA; the world's healthy / infected / dead; the infectivity / severity / lethality meters;
-- the game speed; EVOLVE (and the pathogen's power when it has one). Phones drop the meters and the
-- dead counter.
-- Signals: evolve_pressed(), ability_pressed(), speed_changed(speed).

local UITheme = require("../UITheme")
local W = require("../Widgets")
local GlassPanel = require("../GlassPanel")
local UICtx = require("../UICtx")
local PUI = require("./PUI")
local Signal = UITheme.core("Signal")
local Defs = UICtx.core("Defs")
local Traits = UICtx.data("Traits")

local PlagueHud = W.class(W.Control)

PlagueHud.SPEEDS = { { 0, "II" }, { 1, "1×" }, { 2, "2×" }, { 4, "4×" } }

local function counter(title: string, col: Color3)
	local v = UITheme.vbox(0)
	v.size_flags_vertical = W.SHRINK_CENTER
	local t = UITheme.label(title, 9, 800, UITheme.TEXT_3, 1.4)
	v:add_child(t)
	local n = UITheme.label("0", 17, 800, col)
	v:add_child(n)
	return v, n
end

function PlagueHud.new(c: any)
	local self = setmetatable({}, PlagueHud.__mt)
	W.Control._init(self)
	self.ctx = c
	self.evolve_pressed = Signal.new()
	self.ability_pressed = Signal.new()
	self.speed_changed = Signal.new()
	self.speed = 1
	self:set_mouse_filter(W.MOUSE_IGNORE)
	self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	local panel = GlassPanel.new(18.0, 10.0, UITheme.R_LG, true, 24)
	panel:set_mouse_filter(W.MOUSE_STOP)
	self.panel = panel
	self:add_child(panel)
	local row = UITheme.hbox(14)
	self._row = row
	panel:add_child(row)
	-- the disease
	local who = UITheme.vbox(0)
	who.size_flags_vertical = W.SHRINK_CENTER
	self._name = UITheme.label("", 15, 800, PUI.INFECTED)
	who:add_child(self._name)
	self._day = UITheme.label("Day 0", 11, 600, UITheme.TEXT_2)
	who:add_child(self._day)
	row:add_child(who)
	row:add_child(UITheme.vdivider(34.0))
	-- DNA
	local dna, dna_n = counter("DNA", PUI.DNA)
	self._dna = dna_n
	dna_n:set_font_size(20)
	row:add_child(dna)
	row:add_child(UITheme.vdivider(34.0))
	-- the world
	local h, hn = counter("HEALTHY", PUI.HEALTHY)
	self._h = hn
	row:add_child(h)
	local i, iname = counter("INFECTED", PUI.INFECTED)
	self._i = iname
	row:add_child(i)
	local d, dn = counter("DEAD", PUI.DEAD)
	self._dead_box = d
	self._d = dn
	row:add_child(d)
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
	self._evolve = UITheme.button("EVOLVE", "PrimaryButton", "", 46.0)
	self._evolve:set_font_size(15)
	self._evolve:set_min_size(Vector2.new(120, 46))
	self._evolve.pressed:Connect(function()
		self.evolve_pressed:Fire()
	end)
	row:add_child(self._evolve)
	self:set_speed(1, false)
	return self
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
	self._meters:set_visible(not compact)
	self._div3:set_visible(not compact)
	self._dead_box:set_visible(not compact)
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
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = y
	panel.offset_bottom = y
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
	self._dna:set_text(tostring(math.floor(p.dna or 0)))
	self._h:set_text(PUI.people(p.H or 0))
	self._i:set_text(PUI.people(p.I or 0))
	self._d:set_text(PUI.people(p.D or 0))
	self._m_inf.set(p.inf or 0)
	self._m_sev.set(p.sev or 0)
	self._m_leth.set(p.leth or 0)
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
