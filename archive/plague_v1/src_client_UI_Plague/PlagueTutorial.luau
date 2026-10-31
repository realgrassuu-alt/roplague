--!nonstrict
-- RoPlague first-game tips: one small glass card (RoFront's coach look) under the cure bar that walks a
-- new player through patient zero, bubbles, Evolve, speed and closures. Each step moves on by itself
-- when the player does the thing (PlagueRoot forwards game events to on_event). Skippable; once done
-- or skipped it stays off (setting "plague_tutorial").

local UITheme = require("../UITheme")
local W = require("../Widgets")
local GlassPanel = require("../GlassPanel")
local UICtx = require("../UICtx")
local PUI = require("./PUI")

local PlagueTutorial = W.class(W.Control)

--- {id, text, done_on (event that completes it), auto (seconds before it moves on by itself)}
PlagueTutorial.STEPS = {
	{ id = "zero", text = "Click any country to place patient zero. Crowded, poor countries spread it fastest.", done_on = "started" },
	{ id = "bubbles", text = "Bubbles pop up on the map. Click them to collect DNA, before they fade away.", done_on = "popped" },
	{ id = "evolve", text = "Open EVOLVE and buy your first trait. Coughing or Droplets are good starts.", done_on = "evolved" },
	{ id = "spread", text = "Spread to every country before the world notices. Use 2× and 4× to speed time up.", auto = 9 },
	{ id = "lethal", text = "Deadly symptoms win the game, but they make the world race for a cure. Turn deadly late!", auto = 9 },
}
--- Shown once, whenever it first happens.
PlagueTutorial.CLOSED_TIP = "Countries shut airports and ports once they notice. Islands are the hardest to reach: Droplets, Ballast Water and Stowaway help."

function PlagueTutorial.new(c: any)
	local self = setmetatable({}, PlagueTutorial.__mt)
	W.Control._init(self)
	self.ctx = c
	self._i = 0
	self._shown_at = 0
	self._extra = nil :: string?
	self._closed_tip_done = false
	self:set_mouse_filter(W.MOUSE_IGNORE)
	self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	local panel = GlassPanel.new(14.0, 10.0, UITheme.R_LG, true, 20)
	panel:set_mouse_filter(W.MOUSE_STOP)
	self.panel = panel
	self:add_child(panel)
	local v = UITheme.vbox(6)
	panel:add_child(v)
	local head = UITheme.hbox(8)
	self._step = UITheme.label("TIP", 10, 800, PUI.DNA, 1.6)
	self._step.size_flags_horizontal = W.EXPAND_FILL
	self._step.size_flags_vertical = W.SHRINK_CENTER
	head:add_child(self._step)
	local skip = UITheme.button("SKIP TIPS", "GhostButton", "", 26.0)
	skip:set_font_size(10)
	skip.pressed:Connect(function()
		self:finish("skipped")
	end)
	self._skip = skip
	head:add_child(skip)
	v:add_child(head)
	self._text = UITheme.label("", 13, 600, UITheme.TEXT)
	self._text:set_autowrap(true)
	self._text:set_min_size(Vector2.new(300, 0))
	v:add_child(self._text)
	self:set_visible(false)
	self:reload()
	return self
end

function PlagueTutorial.reload(self)
	local st = self.ctx:setting("plague_tutorial", nil)
	self._off = st == "done" or st == "skipped"
	if self._off then
		self:set_visible(false)
	end
end

function PlagueTutorial.reset(self)
	self._off = false
	self._i = 0
	self._closed_tip_done = false
end

function PlagueTutorial.finish(self, how: string)
	self._off = true
	self.ctx:set_setting("plague_tutorial", how)
	self:hide()
end

function PlagueTutorial.hide(self)
	self._extra = nil
	self:set_visible(false)
end

function PlagueTutorial._show(self, text: string, label: string)
	self._text:set_text(text)
	self._step:set_text(label)
	self:set_visible(true)
	self._shown_at = os.clock()
	self:apply_layout()
	UICtx.pop_in(self.panel, 0.0, 0.95, 0.3)
end

function PlagueTutorial._goto(self, i: number)
	self._i = i
	local step = PlagueTutorial.STEPS[i]
	if step == nil then
		self:finish("done")
		return
	end
	self:_show(step.text, ("TIP %d / %d"):format(i, #PlagueTutorial.STEPS))
end

--- Game events from PlagueRoot: spawn, started, bubble, popped, evolve_opened, evolved, evolve_closed,
--- closed, mutated.
function PlagueTutorial.on_event(self, ev: string)
	if self._off then
		return
	end
	if ev == "spawn" then
		self:_goto(1)
		return
	end
	if ev == "closed" and not self._closed_tip_done and self._i > #PlagueTutorial.STEPS - 2 then
		self._closed_tip_done = true
		self._extra = PlagueTutorial.CLOSED_TIP
		self:_show(PlagueTutorial.CLOSED_TIP, "TIP")
		return
	end
	local step = PlagueTutorial.STEPS[self._i]
	if step ~= nil and step.done_on == ev then
		self:_goto(self._i + 1)
	end
end

--- Twice a second: timed steps move on.
function PlagueTutorial.poll(self)
	if self._off or not self.visible then
		return
	end
	if self._extra ~= nil then
		if os.clock() - self._shown_at > 12 then
			self._extra = nil
			self:set_visible(false)
		end
		return
	end
	local step = PlagueTutorial.STEPS[self._i]
	if step ~= nil and step.auto ~= nil and os.clock() - self._shown_at > step.auto then
		self:_goto(self._i + 1)
	end
end

function PlagueTutorial.apply_layout(self)
	local ctx = self.ctx
	local panel = self.panel
	self._text:set_min_size(Vector2.new(if ctx.compact then 240 else 300, 0))
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.grow_horizontal = W.GROW_END
	panel.grow_vertical = W.GROW_END
	local x = 12.0 + ctx.insets.x
	local y = math.max((if self.top_limit then self.top_limit() else 60.0) + 10.0, ctx.reserved_top_left.Max.Y + 8.0)
	if ctx.compact then
		y = (if self.top_limit then self.top_limit() else 60.0) + 8.0
	end
	panel.offset_left = x
	panel.offset_right = x
	panel.offset_top = y
	panel.offset_bottom = y
	panel:reset_size()
end

return PlagueTutorial
