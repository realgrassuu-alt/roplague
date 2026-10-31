--!nonstrict
-- RoPlague: big short lines at the top of the screen, just under the cure pill (CureBar): "+3 DNA"
-- whenever the plague gets DNA, and the cure's milestones ("CURE RESEARCH 25%"). White text with a
-- thick black outline, popped in on a Back ease, rising a little and fading after LIFE_S.
--   n = TopNotice.new(ctx, anchor)   anchor() -> (centre x, top y) in screen pixels, or nil (hidden)
--   n:dna(amount)          a DNA line; more DNA within MERGE_S adds to the same line ("+5 DNA")
--   n:say(text, color?)    any other line (a cure milestone)
--   n:clear()
-- At most MAX_LINES at once, the newest on top. Never takes a click.

local UITheme = require("../UITheme")
local W = require("../Widgets")

local TopNotice = W.class(W.Control)

TopNotice.LIFE_S = 2.4
TopNotice.FADE_S = 0.45
--- DNA within MERGE_S of a line's FIRST gain adds to it (so a steady trickle reads "+3 DNA" every few
--- seconds, not a counter that never stops); each addition restarts its life.
TopNotice.MERGE_S = 2.0
TopNotice.POP_S = 0.32
TopNotice.RISE_PX = 10
TopNotice.MAX_LINES = 3
TopNotice.TEXT_PX = 32
TopNotice.SMALL_PX = 24
TopNotice.GAP_PX = 6
TopNotice.STROKE_PX = 3.5
TopNotice.Z = 60

local function back_out(t: number): number
	local c1, c3 = 1.70158, 2.70158
	local u = t - 1
	return 1 + c3 * u * u * u + c1 * u * u
end

function TopNotice.new(c: any, anchor: () -> (number?, number?))
	local self = setmetatable({}, TopNotice.__mt)
	W.Control._init(self)
	self.ctx = c
	self.anchor = anchor
	self:set_mouse_filter(W.MOUSE_IGNORE)
	self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	self._lines = {}
	self:set_process(true)
	return self
end

function TopNotice._make(self, text: string, color: Color3?, size: number): any
	local u = UITheme.scale
	local l = Instance.new("TextLabel")
	l.Name = "TopNotice"
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Size = UDim2.fromOffset(math.floor(520 * u), math.floor((size + 8) * u))
	l.FontFace = UITheme.font(800)
	l.TextSize = math.floor(size * u + 0.5)
	l.TextColor3 = color or Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Text = text
	l.Active = false
	l.ZIndex = TopNotice.Z
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(0, 0, 0)
	st.Thickness = TopNotice.STROKE_PX * u
	st.LineJoinMode = Enum.LineJoinMode.Round
	st.Parent = l
	local sc = Instance.new("UIScale")
	sc.Parent = l
	l.Parent = self.gui
	return { label = l, stroke = st, scale = sc, born = os.clock(), h = (size + 8) * u }
end

function TopNotice._push(self, line: any)
	table.insert(self._lines, 1, line)
	while #self._lines > TopNotice.MAX_LINES do
		local old = table.remove(self._lines)
		old.label:Destroy()
	end
	self:_place()
end

--- The plague got `amount` DNA.
function TopNotice.dna(self, amount: number)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return
	end
	local now = os.clock()
	local top = self._lines[1]
	if top ~= nil and top.kind == "dna" and now - (top.first or top.born) < TopNotice.MERGE_S then
		top.amount += amount
		top.label.Text = ("+%d DNA"):format(top.amount)
		top.born = now
		top.punch = now
		self:_place()
		return
	end
	local line = self:_make(("+%d DNA"):format(amount), nil, TopNotice.TEXT_PX)
	line.kind = "dna"
	line.amount = amount
	line.first = os.clock()
	self:_push(line)
end

--- Any other line.
function TopNotice.say(self, text: string, color: Color3?)
	local line = self:_make(text, color, TopNotice.SMALL_PX)
	line.kind = "say"
	self:_push(line)
end

function TopNotice.clear(self)
	for _, line in self._lines do
		line.label:Destroy()
	end
	table.clear(self._lines)
end

--- Where the lines go (every frame: the pill above can move or grow).
function TopNotice._place(self)
	local cx, y = nil, nil
	if self.anchor ~= nil then
		cx, y = self.anchor()
	end
	local shown = cx ~= nil and self.visible
	local origin = self.gui.AbsolutePosition
	local now = os.clock()
	local yy = (y or 0) + TopNotice.GAP_PX * UITheme.scale
	for _, line in self._lines do
		local l = line.label
		l.Visible = shown
		if shown then
			local age = now - line.born
			local rise = math.min(1, age / TopNotice.LIFE_S) * TopNotice.RISE_PX * UITheme.scale
			l.Position = UDim2.fromOffset(math.floor(cx - origin.X + 0.5), math.floor(yy - origin.Y - rise + 0.5))
		end
		yy += line.h
	end
end

function TopNotice._process(self, _dt: number)
	if #self._lines == 0 then
		return
	end
	local now = os.clock()
	for i = #self._lines, 1, -1 do
		local line = self._lines[i]
		local age = now - line.born
		if age >= TopNotice.LIFE_S then
			line.label:Destroy()
			table.remove(self._lines, i)
		else
			local fade = math.clamp((age - (TopNotice.LIFE_S - TopNotice.FADE_S)) / TopNotice.FADE_S, 0, 1)
			line.label.TextTransparency = fade
			line.stroke.Transparency = fade
			local s = 1.0
			local p = line.punch or line.born
			local pu = (now - p) / TopNotice.POP_S
			if pu < 1 then
				s = if line.punch ~= nil then 1 + 0.25 * math.sin(pu * math.pi) else math.max(0.05, back_out(pu))
			else
				line.punch = nil
			end
			line.scale.Scale = s
		end
	end
	self:_place()
end

return TopNotice
