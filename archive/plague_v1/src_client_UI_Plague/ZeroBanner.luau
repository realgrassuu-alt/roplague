--!nonstrict
-- RoPlague: the spawn-phase banner (RoFront's "Choose your starting location" pill, reworded): pick the
-- country where the disease starts.

local UITheme = require("../UITheme")
local W = require("../Widgets")
local GlassPanel = require("../GlassPanel")
local UICtx = require("../UICtx")
local PUI = require("./PUI")

local ZeroBanner = W.class(W.Control)

function ZeroBanner.new(c: any)
	local self = setmetatable({}, ZeroBanner.__mt)
	W.Control._init(self)
	self.ctx = c
	self:set_mouse_filter(W.MOUSE_IGNORE)
	self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	local panel = GlassPanel.new(22.0, 12.0, UITheme.R_LG, true, 24)
	panel:set_mouse_filter(W.MOUSE_IGNORE)
	self.panel = panel
	self:add_child(panel)
	local v = UITheme.vbox(2)
	panel:add_child(v)
	self._title = UITheme.label("CHOOSE PATIENT ZERO", 15, 800, PUI.INFECTED, 1.5)
	v:add_child(self._title)
	self._sub = UITheme.label("Click any country to start your plague there.", 12, 500, UITheme.TEXT_2)
	v:add_child(self._sub)
	self._tip = UITheme.label("Poor, crowded countries spread it fast. Rich ones notice sooner.", 11, 500, UITheme.TEXT_3)
	v:add_child(self._tip)
	return self
end

function ZeroBanner.apply_layout(self)
	local ctx = self.ctx
	self._tip:set_visible(not ctx.compact)
	PUI.place_top(ctx, self.panel, (if ctx.compact then 8.0 else 12.0) + ctx.insets.y)
end

function ZeroBanner.on_show(self)
	UICtx.pop_in(self.panel, 0.05, 0.94, 0.45)
end

return ZeroBanner
