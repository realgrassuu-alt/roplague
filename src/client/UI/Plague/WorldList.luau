--!nonstrict
-- RoPlague: the countries the plague has not reached yet, in one list (opened from the HUD's countries
-- counter). The ones it can reach now come first (across a border, then by ship), the biggest first; a
-- press flies the camera there and opens the country's card.
-- Signals: picked(country), closed().
-- Hooks set by PlagueLink: top_limit(), rows() -> { {c, name, pop, kind} } (kind "land" | "sea" | nil).

local UITheme = require("../UITheme")
local W = require("../Widgets")
local GlassPanel = require("../GlassPanel")
local UICtx = require("../UICtx")
local PUI = require("./PUI")
local Signal = UITheme.core("Signal")
local Scroll = (require("../HelpOverlay") :: any).Scroll

local WorldList = W.class(W.Control)

WorldList.WIDTH = 260
WorldList.ROW_H = 30
--- How often an open list re-reads the world (s).
WorldList.REFRESH_S = 1.0
--- How a route reads, and the order the list keeps (reachable first).
local KIND = {
	land = { "BORDER", UITheme.AMBER, 1 },
	sea = { "SHIP", UITheme.CYAN, 2 },
}
local FAR = { "FAR", UITheme.TEXT_3, 3 }

function WorldList.new(c: any)
	local self = setmetatable({}, WorldList.__mt)
	W.Control._init(self)
	self.ctx = c
	self.picked = Signal.new()
	self.closed = Signal.new()
	self.is_open = false
	self._t = 0
	self._sig = ""
	self:set_mouse_filter(W.MOUSE_IGNORE)
	self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	local panel = GlassPanel.new(14.0, 12.0, UITheme.R_LG, true, 24)
	panel:set_mouse_filter(W.MOUSE_STOP)
	self.panel = panel
	self:add_child(panel)
	local v = UITheme.vbox(8)
	panel:add_child(v)
	local head = UITheme.hbox(8)
	local icon = UITheme.icon_rect("world", 20, UITheme.CYAN)
	icon.size_flags_vertical = W.SHRINK_CENTER
	head:add_child(icon)
	self._title = UITheme.label("NOT INFECTED YET", 14, 800, UITheme.TEXT)
	self._title.size_flags_horizontal = W.EXPAND_FILL
	self._title.size_flags_vertical = W.SHRINK_CENTER
	head:add_child(self._title)
	head:add_child(PUI.close_button(function()
		self:close()
	end))
	v:add_child(head)
	self._sub = UITheme.label("", 11, 600, UITheme.TEXT_3)
	self._sub:set_autowrap(true)
	self._sub:set_min_size(Vector2.new(WorldList.WIDTH - 28, 0))
	v:add_child(self._sub)
	self._scroll = Scroll.new()
	self._inner = UITheme.vbox(2)
	self._scroll:add_child(self._inner)
	v:add_child(self._scroll)
	self:set_visible(false)
	self:set_process(true)
	return self
end

function WorldList.open(self)
	self.is_open = true
	self._sig = ""
	self:set_visible(true)
	self:refresh()
	self:apply_layout()
	UICtx.pop_in(self.panel, 0.0, 0.95, 0.22)
end

function WorldList.close(self)
	if not self.is_open then
		return
	end
	self.is_open = false
	self:set_visible(false)
	self.closed:Fire()
end

function WorldList.toggle(self)
	if self.is_open then
		self:close()
	else
		self:open()
	end
end

function WorldList._process(self, delta: number)
	if not self.is_open then
		return
	end
	self._t += delta
	if self._t >= WorldList.REFRESH_S then
		self._t = 0
		-- (not under the pointer: a row must not move away from the one about to be pressed)
		if not self:_hovered() then
			self:refresh()
		end
	end
end

function WorldList._hovered(self): boolean
	local g = self.panel.gui
	if game == nil or g == nil then
		return false
	end
	local m = game:GetService("UserInputService"):GetMouseLocation()
	-- (GetMouseLocation counts the top bar; AbsolutePosition does not unless the layer ignores it)
	local sg = g:FindFirstAncestorOfClass("ScreenGui")
	if sg == nil or not sg.IgnoreGuiInset then
		m -= game:GetService("GuiService"):GetGuiInset()
	end
	local a, sz = g.AbsolutePosition, g.AbsoluteSize
	return m.X >= a.X and m.X <= a.X + sz.X and m.Y >= a.Y and m.Y <= a.Y + sz.Y
end

--- Rebuilds the rows when the list changed (a country caught it, or a route opened).
function WorldList.refresh(self)
	local rows = if self.rows then self.rows() else {}
	table.sort(rows, function(a, b)
		local ka, kb = (KIND[a.kind] or FAR)[3], (KIND[b.kind] or FAR)[3]
		if ka ~= kb then
			return ka < kb
		end
		if a.pop ~= b.pop then
			return a.pop > b.pop
		end
		return a.c < b.c
	end)
	local parts = table.create(#rows)
	for i, r in rows do
		parts[i] = r.c .. (r.kind or "-")
	end
	local sig = table.concat(parts, ",")
	if sig == self._sig then
		return
	end
	self._sig = sig
	self._n = #rows
	local near = 0
	for _, r in rows do
		if r.kind ~= nil then
			near += 1
		end
	end
	self._title:set_text(("NOT INFECTED YET  %d"):format(#rows))
	self._sub:set_text(
		if #rows == 0
			then "Every country has caught it."
			else ("%d you can reach now. Press one to fly there."):format(near)
	)
	for _, ch in ipairs(self._inner:get_children()) do
		ch:queue_free()
	end
	for _, r in rows do
		local k = KIND[r.kind] or FAR
		local row = UITheme.hbox(6)
		local b = UITheme.button(r.name, "GhostButton", "", WorldList.ROW_H)
		b.alignment = W.ALIGN_LEFT
		b:set_font_size(12)
		b:set_clip_text(true)
		b.size_flags_horizontal = W.EXPAND_FILL
		b.pressed:Connect(function()
			self.picked:Fire(r.c)
		end)
		row:add_child(b)
		local tag = UITheme.label(k[1], 10, 800, k[2], 1.2)
		tag.size_flags_vertical = W.SHRINK_CENTER
		tag:set_min_size(Vector2.new(60, 0))
		row:add_child(tag)
		self._inner:add_child(row)
	end
	self:apply_layout()
end

function WorldList.apply_layout(self)
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
	-- (the list scrolls once it is taller than the room above the bottom bar)
	local room = (if self.bottom_limit then self.bottom_limit() else 600.0) - y - 110.0
	local n = self._n or 0
	local want = n * (WorldList.ROW_H + 2)
	self._scroll:set_min_size(Vector2.new(WorldList.WIDTH - 28, math.clamp(want, 0, math.max(WorldList.ROW_H * 3, room))))
	self._scroll:set_visible(n > 0)
	panel:reset_size()
end

return WorldList
