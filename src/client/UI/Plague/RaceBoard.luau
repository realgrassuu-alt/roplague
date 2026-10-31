--!nonstrict
-- RoPlague's Plague Race (Data/PlagueModes "race"; Session.race): the racers' standings, top left, while
-- a race runs: place, name, how much of their world is dead, and whether they are out (cured, burned
-- out, left). When the race is decided it names the winner and offers the way back to the lobby.
-- Signals: leave_pressed().
local UITheme = require("../UITheme")
local W = require("../Widgets")
local GlassPanel = require("../GlassPanel")
local PUI = require("./PUI")
local Signal = UITheme.core("Signal")

local RaceBoard = W.class(W.Control)

RaceBoard.WIDTH = 240
local WHY = { cured = "CURED", burnout = "DIED OUT", left = "LEFT", out = "OUT", extinct = "WINNER" }

function RaceBoard.new(c: any)
	local self = setmetatable({}, RaceBoard.__mt)
	W.Control._init(self)
	self.ctx = c
	self.leave_pressed = Signal.new()
	self:set_mouse_filter(W.MOUSE_IGNORE)
	self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	local panel = GlassPanel.new(14.0, 12.0, UITheme.R_LG, true, 24)
	panel:set_mouse_filter(W.MOUSE_STOP)
	self.panel = panel
	self:add_child(panel)
	local v = UITheme.vbox(6)
	v:set_min_size(Vector2.new(RaceBoard.WIDTH - 28, 0))
	panel:add_child(v)
	local head = UITheme.hbox(8)
	local icon = UITheme.icon_rect("virus", 18, PUI.INFECTED)
	icon.size_flags_vertical = W.SHRINK_CENTER
	head:add_child(icon)
	self._title = UITheme.label("PLAGUE RACE", 14, 800, UITheme.TEXT)
	self._title.size_flags_vertical = W.SHRINK_CENTER
	head:add_child(self._title)
	v:add_child(head)
	self._sub = UITheme.label("First to wipe out humanity wins", 11, 600, UITheme.TEXT_3)
	self._sub:set_autowrap(true)
	self._sub:set_min_size(Vector2.new(RaceBoard.WIDTH - 28, 0))
	v:add_child(self._sub)
	self._rows = UITheme.vbox(4)
	v:add_child(self._rows)
	self._leave = UITheme.button("BACK TO LOBBY", "PrimaryButton", "exit", 42.0)
	self._leave:set_font_size(13)
	self._leave.pressed:Connect(function()
		self.leave_pressed:Fire()
	end)
	self._leave:set_visible(false)
	v:add_child(self._leave)
	self:set_visible(false)
	return self
end

--- Shows `race` (Session.race; nil hides the board).
function RaceBoard.show_race(self, race: any)
	if race == nil then
		self:set_visible(false)
		return
	end
	self:set_visible(true)
	local me = if typeof(game) == "Instance" then tostring((game :: any):GetService("Players").LocalPlayer.UserId) else ""
	local over = race.over
	for _, ch in ipairs(self._rows:get_children()) do
		ch:queue_free()
	end
	local list = race.standings
	if list == nil or #list == 0 then
		-- (before the first standings: the racers as they were sent)
		list = {}
		for i, r in race.racers or {} do
			table.insert(list, { uid = r.uid, name = r.name, dead = 0, place = i, out = false })
		end
	end
	local winner_name = nil
	for _, r in list do
		local mine = tostring(r.uid) == me
		local row = UITheme.hbox(6)
		local place = UITheme.label(tostring(r.place or "?") .. ".", 12, 800, if mine then UITheme.AMBER else UITheme.TEXT_2)
		place:set_min_size(Vector2.new(20, 0))
		row:add_child(place)
		local name = UITheme.label(tostring(r.name or "?") .. (if mine then " (you)" else ""), 12, 700, if mine then UITheme.AMBER else UITheme.TEXT)
		name.size_flags_horizontal = W.EXPAND_FILL
		name.clip_text = true
		row:add_child(name)
		local won = over ~= nil and tostring(over.winner) == tostring(r.uid)
		if won then
			winner_name = tostring(r.name or "?")
		end
		local tag = if won
			then "WINNER"
			elseif r.out then (WHY[r.why or "out"] or "OUT")
			else ("%d%% dead"):format(math.floor((tonumber(r.dead) or 0) * 100 + 0.5))
		local tl = UITheme.label(tag, 11, 800, if won then UITheme.GOLD elseif r.out then UITheme.TEXT_3 else PUI.INFECTED)
		tl.size_flags_vertical = W.SHRINK_CENTER
		row:add_child(tl)
		self._rows:add_child(row)
	end
	if over ~= nil then
		local i_won = tostring(over.winner) == me
		self._title:set_text(if i_won then "YOU WON THE RACE" else "RACE OVER")
		UITheme.set_font_color(self._title, if i_won then UITheme.GOLD else UITheme.TEXT)
		self._sub:set_text(
			if i_won
				then "Your plague wiped out humanity first."
				else ("%s won the race."):format(winner_name or "Another racer")
		)
		self._leave:set_visible(true)
	else
		self._title:set_text("PLAGUE RACE")
		UITheme.set_font_color(self._title, UITheme.TEXT)
		self._sub:set_text("First to wipe out humanity wins")
		self._leave:set_visible(false)
	end
	self:apply_layout()
end

--- A shared world (a server-run Plague Race or team game, GameState.plague.plagues): every plague, its
--- map colour, how many countries it holds and how many it has killed; out ones last. `s` is the
--- GameState (nil hides the board). Rebuilt at most once a second.
function RaceBoard.show_world(self, s: any)
	local p = if s ~= nil then s.plague else nil
	if p == nil or type(p.plagues) ~= "table" or #p.plagues < 2 then
		self:set_visible(false)
		return
	end
	local now = os.clock()
	if self.visible and now - (self._world_at or 0) < 1.0 then
		return
	end
	self._world_at = now
	self:set_visible(true)
	for _, ch in ipairs(self._rows:get_children()) do
		ch:queue_free()
	end
	local Strains = require("../UICtx").data("Strains")
	local keys = {}
	for i, r in p.plagues do
		keys[i] = Strains.worn_by(s, r.pid)
	end
	local cols = Strains.distinct(keys)
	local order = {}
	for i, r in p.plagues do
		table.insert(order, { r = r, col = cols[i] })
	end
	table.sort(order, function(a, b)
		if (a.r.out == true) ~= (b.r.out == true) then
			return not a.r.out
		end
		if (a.r.held or 0) ~= (b.r.held or 0) then
			return (a.r.held or 0) > (b.r.held or 0)
		end
		return (a.r.kills or 0) > (b.r.kills or 0)
	end)
	local me = p.pid
	for i, o in order do
		local r = o.r
		local mine = r.pid == me
		local row = UITheme.hbox(6)
		local place = UITheme.label(tostring(i) .. ".", 12, 800, if mine then UITheme.AMBER else UITheme.TEXT_2)
		place:set_min_size(Vector2.new(20, 0))
		row:add_child(place)
		local sw = W.Panel.new()
		sw:set_min_size(Vector2.new(10, 10))
		sw.size_flags_vertical = W.SHRINK_CENTER
		sw:set_mouse_filter(W.MOUSE_IGNORE)
		local c = o.col
		local color = if c ~= nil and c.a ~= nil and not c.rainbow
			then Color3.fromRGB(c.a[1], c.a[2], c.a[3])
			else Color3.fromHSV((now * 0.12) % 1, 0.8, 1)
		sw:add_theme_stylebox_override("panel", UITheme.flat(color, 3))
		row:add_child(sw)
		local name = UITheme.label(tostring(r.name or "?") .. (if mine then " (you)" else ""), 12, 700, if mine then UITheme.AMBER else UITheme.TEXT)
		name.size_flags_horizontal = W.EXPAND_FILL
		name.clip_text = true
		row:add_child(name)
		local tag = if r.out then "OUT" else ("%d countries"):format(r.held or 0)
		local tl = UITheme.label(tag, 11, 800, if r.out then UITheme.TEXT_3 else color)
		tl.size_flags_vertical = W.SHRINK_CENTER
		row:add_child(tl)
		self._rows:add_child(row)
	end
	self._title:set_text(if p.mode == "teams" then "TEAM PLAGUE" else "PLAGUE RACE")
	UITheme.set_font_color(self._title, UITheme.TEXT)
	self._sub:set_text("Spread, attack their countries. Last plague standing wins")
	self._leave:set_visible(false)
	self:apply_layout()
end

--- Top left, under the top-bar buttons (`top_limit`: their bottom, set by PlagueLink).
function RaceBoard.apply_layout(self)
	local ctx = self.ctx
	local panel = self.panel
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.grow_horizontal = W.GROW_END
	panel.grow_vertical = W.GROW_END
	local x = 12.0 + ctx.insets.x
	local y = (if self.top_limit then self.top_limit() else 80.0) + 10.0
	-- (a phone: drawn smaller, kept in the top-left corner)
	local vp = ctx.vp
	local _, fdx, fdy = PUI.fit(panel, vp.X * (if ctx.compact then 0.3 else 0.25), vp.Y * 0.45, 0.0, 0.0)
	x += fdx
	y += fdy
	panel.offset_left = x
	panel.offset_right = x
	panel.offset_top = y
	panel.offset_bottom = y
	panel:reset_size()
end


return RaceBoard
