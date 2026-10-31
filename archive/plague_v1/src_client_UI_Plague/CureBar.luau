--!nonstrict
-- RoPlague: the top-centre pill (where RoFront's world-control status sat). Before the world notices
-- the disease it shows how close it is to being noticed (amber); after, the cure's progress (blue)
-- and how many days it needs at today's pace.

local UITheme = require("../UITheme")
local W = require("../Widgets")
local GlassPanel = require("../GlassPanel")
local UICtx = require("../UICtx")
local FillBar = require("../FillBar")
local PUI = require("./PUI")

local CureBar = W.class(W.Control)

CureBar.BAR_W = 260

function CureBar.new(c: any)
	local self = setmetatable({}, CureBar.__mt)
	W.Control._init(self)
	self.ctx = c
	self:set_mouse_filter(W.MOUSE_IGNORE)
	self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	local panel = GlassPanel.new(16.0, 8.0, UITheme.R_LG, true, 24)
	panel:set_mouse_filter(W.MOUSE_IGNORE)
	self.panel = panel
	self:add_child(panel)
	local v = UITheme.vbox(5)
	panel:add_child(v)
	local row = UITheme.hbox(10)
	self._cap = UITheme.label("UNNOTICED", 11, 800, PUI.AWARE, 1.6)
	self._cap.size_flags_horizontal = W.EXPAND_FILL
	row:add_child(self._cap)
	self._pct = UITheme.label("0%", 13, 800, UITheme.TEXT)
	row:add_child(self._pct)
	v:add_child(row)
	self._bar = FillBar.new(8.0, PUI.AWARE)
	self._bar:set_min_size(Vector2.new(CureBar.BAR_W, 8))
	v:add_child(self._bar)
	self._sub = UITheme.label("The world hasn't noticed yet", 10, 600, UITheme.TEXT_3)
	v:add_child(self._sub)
	self._research = nil
	return self
end

function CureBar.apply_layout(self)
	local ctx = self.ctx
	self._bar:set_min_size(Vector2.new(if ctx.compact then 190 else CureBar.BAR_W, 8))
	PUI.place_top(ctx, self.panel, (if ctx.compact then 8.0 else 12.0) + ctx.insets.y)
end

function CureBar.bottom_edge(self): number
	return self.panel:get_global_rect().Max.Y
end

function CureBar.refresh(self, instant: boolean?)
	local s = self.ctx.state
	local p = if s ~= nil then s.plague else nil
	if p == nil then
		return
	end
	local research = p.research == true
	if research ~= self._research then
		self._research = research
		self._bar:set_color(if research then PUI.CURE else PUI.AWARE)
		PUI.color(self._cap, if research then PUI.CURE else PUI.AWARE)
		self._cap:set_text(if research then "CURE RESEARCH" else "UNNOTICED")
		instant = true
	end
	if research then
		local cure = math.clamp(p.cure or 0, 0, 1)
		self:_set(cure, instant)
		self._pct:set_text(PUI.pct(cure))
		local rate = tonumber(p.cure_rate) or 0
		if rate > 1e-6 and cure < 1 then
			local days = math.ceil((1 - cure) / rate)
			self._sub:set_text(("Done in about %s days at this pace"):format(UICtx.commas(days)))
		else
			self._sub:set_text("Research has stalled")
		end
	else
		local a = math.clamp(p.aware or 0, 0, 1)
		self:_set(a, instant)
		self._pct:set_text(PUI.pct(a))
		self._sub:set_text(if a < 0.5 then "The world hasn't noticed yet" else "Doctors are starting to ask questions")
	end
end

function CureBar._set(self, v: number, instant: boolean?)
	if instant then
		self._bar:set_instant(v)
	else
		self._bar:set_target(v)
	end
end

return CureBar
