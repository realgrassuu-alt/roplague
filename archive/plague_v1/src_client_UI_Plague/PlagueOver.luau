--!nonstrict
-- RoPlague: the end of a match (RoFront's victory / defeat screen, reworded): a headline, what happened,
-- the match's numbers and PLAY AGAIN / MAIN MENU. Signals: again(), menu().

local UITheme = require("../UITheme")
local W = require("../Widgets")
local UICtx = require("../UICtx")
local PUI = require("./PUI")
local Signal = UITheme.core("Signal")
local Defs = UICtx.core("Defs")

local PlagueOver = {}
PlagueOver.__index = PlagueOver

local COPY = {
	[Defs.OVER_EXTINCT] = { "HUMANITY IS GONE", "%s wiped out every last person on Earth. You win.", true },
	[Defs.OVER_CURED] = { "THE WORLD IS CURED", "Researchers finished the cure before %s could finish them.", false },
	[Defs.OVER_BURNOUT] = { "YOUR PLAGUE DIED OUT", "%s killed its hosts faster than it could spread.", false },
}

local function stat(title: string)
	local v = UITheme.vbox(2)
	v:set_min_size(Vector2.new(150, 0))
	v:add_child(UITheme.label(title, 10, 800, UITheme.TEXT_3, 1.4))
	local n = UITheme.label("", 20, 800, UITheme.TEXT)
	v:add_child(n)
	return v, n
end

function PlagueOver.new(c: any)
	local self = setmetatable({}, PlagueOver)
	self.ctx = c
	self.again = Signal.new()
	self.menu = Signal.new()
	local m = PUI.Modal.new(c, "", { sep = 14, close = false, dismiss = false, dim = 0.45, title_px = 30 })
	self.modal = m
	self._sub = UITheme.label("", 14, 500, UITheme.TEXT_2)
	self._sub:set_autowrap(true)
	self._sub:set_min_size(Vector2.new(560, 0))
	m.body:add_child(self._sub)
	local grid = UITheme.hbox(12)
	local a, an = stat("DAYS")
	local b, bn = stat("DEAD")
	local d, dn = stat("COUNTRIES REACHED")
	local e, en = stat("CURE")
	self._days, self._dead, self._countries, self._cure = an, bn, dn, en
	grid:add_child(a)
	grid:add_child(b)
	grid:add_child(d)
	grid:add_child(e)
	m.body:add_child(grid)
	local btns = UITheme.hbox(10)
	local again = UITheme.button("PLAY AGAIN", "PrimaryButton", "", 50.0)
	again:set_font_size(16)
	again.size_flags_horizontal = W.EXPAND_FILL
	again.pressed:Connect(function()
		self.modal:close(true)
		self.again:Fire()
	end)
	btns:add_child(again)
	local menu = UITheme.button("MAIN MENU", "GlassButton", "", 50.0)
	menu:set_font_size(14)
	menu.pressed:Connect(function()
		self.modal:close(true)
		self.menu:Fire()
	end)
	btns:add_child(menu)
	m.body:add_child(btns)
	return self
end

function PlagueOver.show(self, countries_reached: number, countries_total: number)
	local s = self.ctx.state
	local p = if s ~= nil then s.plague else nil
	if p == nil then
		return
	end
	local copy = COPY[s.over_reason] or COPY[Defs.OVER_CURED]
	self.modal.title:set_text(copy[1])
	PUI.color(self.modal.title, if copy[3] then PUI.INFECTED else PUI.CURE)
	self._sub:set_text(copy[2]:format(tostring(p.name or "Your plague")))
	local days = if s.playing_since >= 0 then math.floor((s.tick - s.playing_since) / 10) else 0
	self._days:set_text(UICtx.commas(days))
	self._dead:set_text(PUI.people(p.D or 0))
	self._countries:set_text(("%d / %d"):format(countries_reached, countries_total))
	self._cure:set_text(PUI.pct(p.cure or 0))
	self.ctx:sfx(if copy[3] then "victory" else "defeat")
	self.modal:open()
end

function PlagueOver.apply_layout(self)
	self.modal:apply_layout()
end

return PlagueOver
