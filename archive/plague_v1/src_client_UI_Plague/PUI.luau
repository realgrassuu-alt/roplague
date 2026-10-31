--!nonstrict
-- RoPlague UI helpers shared by the plague screens: number formatting, the modal window shell (the
-- MapPicker / Arsenal recipe: dim + glass panel + title row + close), chips and small meters. Built on
-- the RoFront kit (UITheme, Widgets, GlassPanel) so every screen keeps its look.

local UITheme = require("../UITheme")
local W = require("../Widgets")
local GlassPanel = require("../GlassPanel")
local UICtx = require("../UICtx")
local FillBar = require("../FillBar")
local Signal = UITheme.core("Signal")

local PUI = {}

--- Colours of the plague's three populations and the cure.
PUI.HEALTHY = Color3.fromRGB(120, 214, 160)
PUI.INFECTED = Color3.fromRGB(255, 74, 74)
PUI.DEAD = Color3.fromRGB(150, 150, 165)
PUI.CURE = Color3.fromRGB(80, 190, 255)
PUI.DNA = Color3.fromRGB(255, 150, 60)
PUI.AWARE = UITheme.AMBER

PUI.DIFFICULTIES = { "Casual", "Normal", "Brutal" }

--- 1234 -> "1,234"; 12345678 -> "12.3M"; 7.66e9 -> "7.66B".
function PUI.people(n: number): string
	n = math.max(0, math.floor((tonumber(n) or 0) + 0.5))
	if n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e7 then
		return string.format("%.0fM", n / 1e6)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.0fK", n / 1e3)
	end
	return UICtx.commas(n)
end

function PUI.pct(x: number): string
	x = math.clamp(tonumber(x) or 0, 0, 1) * 100
	if x > 0 and x < 1 then
		return string.format("%.1f%%", x)
	end
	return string.format("%d%%", math.floor(x + 0.5))
end

function PUI.color(l: any, col: any)
	UITheme.set_font_color(l, col)
end

--- A ghost close button (the MapPicker's).
function PUI.close_button(cb: () -> ())
	local close = W.Button.new("", "GhostButton")
	close:set_icon("close")
	close.expand_icon = true
	close:set_min_size(Vector2.new(34, 34))
	close:add_theme_constant_override("icon_max_width", 13)
	close:add_theme_stylebox_override("normal", UITheme.empty_box(8, 8))
	close:add_theme_stylebox_override("hover", UITheme.flat(UITheme.FILL, 8, UITheme.CLEAR, 0, 8, 8))
	close.size_flags_vertical = W.SHRINK_CENTER
	close.pressed:Connect(cb)
	return close
end

function PUI.chip(text: string, h: number?)
	local chip = UITheme.button(text, "ChipButton", "", h or 32.0)
	chip.toggle_mode = true
	chip:set_font_size(12)
	return chip
end

--- A labelled meter: {node, set(v 0..1)}.
function PUI.meter(label: string, col: Color3, w: number?)
	local v = UITheme.vbox(3)
	local row = UITheme.hbox(6)
	local l = UITheme.label(string.upper(label), 9, 800, UITheme.TEXT_3, 1.2)
	l.size_flags_horizontal = W.EXPAND_FILL
	row:add_child(l)
	local pct = UITheme.label("0%", 9, 800, col)
	row:add_child(pct)
	v:add_child(row)
	local bar = FillBar.new(5.0, col)
	bar:set_min_size(Vector2.new(w or 92, 5))
	v:add_child(bar)
	return {
		node = v,
		set = function(x: number, instant: boolean?)
			x = math.clamp(x, 0, 1)
			if instant then
				bar:set_instant(x)
			else
				bar:set_target(x)
			end
			pct:set_text(PUI.pct(x))
		end,
	}
end

-- =============================================================================================
-- Modal: a full-screen Control with a dim and a centred glass panel.
--   m = PUI.Modal.new(ctx, "TITLE", {width?, dismiss = true})
--   m.body (vbox to fill), m.head (title row), m:open(), m:close(), m.closed (Signal), m.is_open
-- =============================================================================================

local Modal = W.class(W.Control)
PUI.Modal = Modal

function Modal.new(c: any, title: string, opts: any?)
	opts = opts or {}
	local self = setmetatable({}, Modal.__mt)
	W.Control._init(self)
	self.ctx = c
	self.closed = Signal.new()
	self.is_open = false
	self.dismiss = opts.dismiss ~= false
	self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	self:set_mouse_filter(W.MOUSE_STOP)
	self:set_visible(false)
	self._dim = W.ColorRect.new(UITheme.rgba(0.01, 0.015, 0.05, opts.dim or 0.6))
	self._dim:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	self._dim.gui_input:Connect(function(e)
		if self.dismiss and e.pressed and not self.panel:has_global_point(e.global_position) then
			self:close()
		end
	end)
	self:add_child(self._dim)
	self.panel = GlassPanel.new(opts.pad_h or 22.0, opts.pad_v or 20.0, 18, true, 34)
	self.panel:set_tint(UITheme.rgba(0.045, 0.065, 0.13, 0.95))
	self:add_child(self.panel)
	local v = UITheme.vbox(opts.sep or 12)
	self.panel:add_child(v)
	self.body = v
	local head = UITheme.hbox(10)
	self.head = head
	self.title = UITheme.label(title, opts.title_px or 20, 800, UITheme.TEXT, 3)
	self.title.size_flags_horizontal = W.EXPAND_FILL
	self.title.size_flags_vertical = W.SHRINK_CENTER
	head:add_child(self.title)
	if opts.head_extra ~= nil then
		head:add_child(opts.head_extra)
	end
	if opts.close ~= false then
		head:add_child(PUI.close_button(function()
			self:close()
		end))
	end
	v:add_child(head)
	return self
end

function Modal.open(self)
	if self.is_open then
		return
	end
	self.is_open = true
	self:set_visible(true)
	self.panel:set_modulate_a(1.0)
	self:center()
	self._dim:set_modulate_a(0.0)
	W.fade(self._dim, 1.0, 0.2)
	UICtx.pop_in(self.panel, 0.0, 0.94, 0.3)
	self.ctx:sfx("open")
end

function Modal.close(self, quiet: boolean?)
	if not self.is_open then
		return
	end
	self.is_open = false
	if not quiet then
		self.ctx:sfx("close")
	end
	local t = self:create_tween():set_parallel(true)
	t:tween_property(self._dim, "modulate:a", 0.0, 0.15)
	t:tween_property(self.panel, "modulate:a", 0.0, 0.15)
	t:chain():tween_callback(function()
		if not self.is_open then
			self:set_visible(false)
		end
	end)
	self.closed:Fire()
end

function Modal.center(self)
	local ctx = self.ctx
	local sz = self.panel:get_combined_minimum_size()
	local area = ctx:clear_rect()
	local p = area.Min + (Vector2.new(area.Width, area.Height) - sz) * 0.5
	local y = math.max(p.Y, area.Min.Y + 4.0)
	local rp = Vector2.new(math.floor(p.X + 0.5), math.floor(y + 0.5))
	self.panel:set_offsets(rp.X, rp.Y, rp.X, rp.Y)
	self.panel:reset_size()
end

function Modal.apply_layout(self)
	if self.is_open then
		self:center()
	end
end

--- A top-centre glass pill placed like SpawnOverlay's (below the Roblox top bar's buttons).
function PUI.place_top(ctx: any, panel: any, y: number)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.grow_horizontal = W.GROW_BOTH
	panel.grow_vertical = W.GROW_END
	local dx, yy = ctx:place_top(panel:get_combined_minimum_size().X, y)
	panel.offset_left = dx
	panel.offset_right = dx
	panel.offset_top = yy
	panel.offset_bottom = yy
	panel:reset_size()
end

return PUI
