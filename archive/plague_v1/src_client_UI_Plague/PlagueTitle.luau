--!nonstrict
-- RoPlague title screen: the wordmark over the backdrop (a plague spreading by itself, Session.start_title),
-- PLAY, HOW TO PLAY and the credits line. RoFront's title layout and look, without its lobbies and shops.
-- Signals: play(), show_help().

local UITheme = require("../UITheme")
local W = require("../Widgets")
local GlassPanel = require("../GlassPanel")
local UICtx = require("../UICtx")
local PUI = require("./PUI")
local Signal = UITheme.core("Signal")

local PlagueTitle = W.class(W.Control)

PlagueTitle.NAME = "ROPLAGUE"
PlagueTitle.TAGLINE = "INFECT THE REAL WORLD"
PlagueTitle.CREDITS = "Based on RoWorld (© 2026 Snick Co.) and OpenFront (© OpenFront and Contributors) · GNU AGPL v3 · See Help & Credits"

function PlagueTitle.new(c: any)
	local self = setmetatable({}, PlagueTitle.__mt)
	W.Control._init(self)
	self.ctx = c
	self.play = Signal.new()
	self.show_help = Signal.new()
	self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	self:set_mouse_filter(W.MOUSE_IGNORE)
	-- a soft dark band behind the column so the wordmark reads over the moving map
	self._shade = W.ColorRect.new(UITheme.rgba(0.01, 0.015, 0.05, 0.35))
	self._shade:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	self._shade:set_mouse_filter(W.MOUSE_IGNORE)
	self:add_child(self._shade)
	local col = UITheme.vbox(14)
	col:set_mouse_filter(W.MOUSE_IGNORE)
	self._col = col
	self:add_child(col)
	self._mark = UITheme.label(PlagueTitle.NAME, 76, 800, PUI.INFECTED, 10)
	self._mark.size_flags_horizontal = W.SHRINK_CENTER
	col:add_child(self._mark)
	self._tag = UITheme.label(PlagueTitle.TAGLINE, 15, 700, UITheme.TEXT_2, 6)
	self._tag.size_flags_horizontal = W.SHRINK_CENTER
	col:add_child(self._tag)
	local gap = W.Control.new()
	gap:set_min_size(Vector2.new(0, 18))
	col:add_child(gap)
	local panel = GlassPanel.new(22.0, 18.0, UITheme.R_LG, true, 28)
	panel.size_flags_horizontal = W.SHRINK_CENTER
	self._panel = panel
	col:add_child(panel)
	local v = UITheme.vbox(10)
	panel:add_child(v)
	self._play = UITheme.button("PLAY", "PrimaryButton", "", 56.0)
	self._play:set_font_size(20)
	self._play:set_min_size(Vector2.new(300, 56))
	self._play.pressed:Connect(function()
		self.play:Fire()
	end)
	v:add_child(self._play)
	local help = UITheme.button("HOW TO PLAY", "GlassButton", "help", 44.0)
	help:set_font_size(14)
	help.pressed:Connect(function()
		self.show_help:Fire()
	end)
	v:add_child(help)
	self._credits = UITheme.label(PlagueTitle.CREDITS, 11, 500, UITheme.TEXT_3)
	self._credits:set_mouse_filter(W.MOUSE_IGNORE)
	self:add_child(self._credits)
	return self
end

function PlagueTitle.apply_layout(self)
	local ctx = self.ctx
	local compact = ctx.compact
	self._mark:set_font_size(if compact then 48 else 76)
	self._tag:set_font_size(if compact then 12 else 15)
	self._play:set_min_size(Vector2.new(if compact then 240 else 300, if compact then 48 else 56))
	local col = self._col
	col.anchor_left = 0.5
	col.anchor_right = 0.5
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.grow_horizontal = W.GROW_BOTH
	col.grow_vertical = W.GROW_BOTH
	col.offset_left = 0
	col.offset_right = 0
	col.offset_top = -10
	col.offset_bottom = -10
	col:reset_size()
	local cr = self._credits
	cr.anchor_left = 0.5
	cr.anchor_right = 0.5
	cr.anchor_top = 1.0
	cr.anchor_bottom = 1.0
	cr.grow_horizontal = W.GROW_BOTH
	cr.grow_vertical = W.GROW_BEGIN
	local y = -(10.0 + ctx.insets.w)
	cr.offset_top = y
	cr.offset_bottom = y
	cr.offset_left = 0
	cr.offset_right = 0
	cr:reset_size()
	cr:set_visible(not compact)
end

function PlagueTitle.on_show(self)
	UICtx.pop_in(self._panel, 0.05, 0.94, 0.45)
end

return PlagueTitle
