--!nonstrict
-- RoPlague: a new player's first match, step by step, in RoWorld's tutorial style (UI/Tutorial): a card
-- at the top ("3 / 10", one short line, Skip) and a tap mark on the thing to press (two rings closing
-- on a dot on the map, or around a button). A finished step turns the card green for a moment, then
-- the next comes. A step nobody finishes in its time is passed over, so nobody is ever stuck.
--
--   PlagueTutorial.new(ctx, ui)   (ui = UIRoot; it reads ui.plague: the HUD bar, Evolve, the cure pill)
--   :begin()  the first match was asked for     :stop(how)  "done" | "skipped" | "left"
--   .active
--
-- The steps (STEPS): patient zero (in a good country: crowded, poor, many neighbours), pop a DNA bubble,
-- infect a neighbour (a traveller walks there), open EVOLVE, buy Water Supply (it lets ships carry it),
-- close it, send an infected ship overseas, the cure bar.
local UITheme = require("../UITheme")
local W = require("../Widgets")
local GlassPanel = require("../GlassPanel")
local UICtx = require("../UICtx")
local PUI = require("./PUI")
local Defs = UICtx.core("Defs")

local PlagueTutorial = W.class(W.Control)

PlagueTutorial.DONE_S = 0.9
PlagueTutorial.END_S = 10.0
--- Seconds on a step before it is passed over (unless the step says otherwise).
PlagueTutorial.STEP_MAX_S = 60
--- Seconds before patient zero is picked for the player.
PlagueTutorial.AUTO_ZERO_S = 20
--- Countries the first mark suggests, first one on the map wins: good places to start a plague (crowded,
--- poor so health care is weak, many neighbours to spread into, a coast for ships).
PlagueTutorial.SUGGEST = { "India", "Nigeria", "Egypt", "Brazil", "China", "Germany" }
--- The evolution the "buy" step points at: the first that lets ships carry the plague.
PlagueTutorial.SHIP_TRAIT = "water1"

--- The steps: `text` (desktop) / `touch`; `%s` is a country's name. `max_s`: its time.
PlagueTutorial.STEPS = {
	{ id = "zero", text = "Start somewhere crowded and poor with lots of neighbours, like %s. Click it!",
		touch = "Start somewhere crowded and poor with lots of neighbours, like %s. Tap it!" },
	{ id = "bubble", text = "Click the DNA bubble. DNA buys upgrades", touch = "Tap the DNA bubble. DNA buys upgrades", max_s = 45 },
	{ id = "infect", text = "Click %s to spread across the border", touch = "Tap %s to spread across the border", max_s = 120 },
	{ id = "evolve", text = "Press EVOLVE to make your plague stronger" },
	{ id = "buy", text = "Pick Water Supply, then press the green EVOLVE button. It lets you send ships",
		touch = "Tap Water Supply, then the green EVOLVE button. It lets you send ships", max_s = 60 },
	{ id = "close", text = "Close this window to go back to the map", max_s = 20 },
	{ id = "ship", text = "Ships carry it overseas. Click %s to send an infected ship",
		touch = "Ships carry it overseas. Tap %s to send an infected ship", max_s = 150 },
	{ id = "cure", text = "The bar at the top is the cure. Infect every country before it fills!", max_s = 8 },
}

function PlagueTutorial.new(c: any, ui: any)
	local self = setmetatable({}, PlagueTutorial.__mt)
	W.Control._init(self)
	self.ctx = c
	self.ui = ui
	self.active = false
	self._i = 0
	self._t = 0.0
	self._step_t = 0.0
	self._flash = 0.0
	self._ending = 0.0
	self:set_mouse_filter(W.MOUSE_IGNORE)
	self:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	-- the tap mark (RoWorld's)
	self._mark = UICtx.canvas(self.gui, "PlagueTutorialMark")
	self._mark.ZIndex = 60
	self._ring_a = UICtx.ring(self._mark, Vector2.zero, 10, 3, UITheme.AMBER, 1)
	self._ring_b = UICtx.ring(self._mark, Vector2.zero, 10, 2, UITheme.AMBER, 1)
	self._dot = UICtx.circle(self._mark, Vector2.zero, 6, UITheme.AMBER, 0)
	self._tap = UICtx.make("TextLabel", {
		BackgroundColor3 = Color3.fromRGB(14, 20, 38),
		BackgroundTransparency = 0.15,
		Text = "Click here",
		FontFace = Font.fromId(12187365977, Enum.FontWeight.Bold),
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		AutomaticSize = Enum.AutomaticSize.XY,
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 61,
	}, self._mark)
	UICtx.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, self._tap)
	UICtx.make("UIPadding", {
		PaddingLeft = UDim.new(0, 9),
		PaddingRight = UDim.new(0, 9),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
	}, self._tap)
	self._mark.Visible = false
	-- the card (RoWorld's)
	local card = GlassPanel.new(12.0, 8.0, UITheme.R_MD, true, 18)
	card:set_accent(UITheme.AMBER)
	card:set_border(UITheme.c(UITheme.AMBER, 0.5))
	self._card = card
	local h = UITheme.hbox(10)
	card:add_child(h)
	self._count = UITheme.label("1 / 10", 12, 800, UITheme.AMBER)
	self._count.size_flags_vertical = W.SHRINK_CENTER
	h:add_child(self._count)
	self._text = UITheme.label("", 14, 700, UITheme.TEXT)
	self._text:set_autowrap(true)
	self._text:set_min_size(Vector2.new(260, 0))
	self._text.size_flags_horizontal = W.EXPAND_FILL
	self._text.size_flags_vertical = W.SHRINK_CENTER
	h:add_child(self._text)
	self._skip = UITheme.button("Skip", "GhostButton", "", 36.0)
	self._skip:set_font_size(12)
	self._skip:set_min_size(Vector2.new(52, 36))
	self._skip.size_flags_vertical = W.SHRINK_CENTER
	self._skip.pressed:Connect(function()
		if self._ending > 0.0 then
			self:_close()
		else
			self:stop("skipped")
		end
	end)
	h:add_child(self._skip)
	self:add_child(card)
	card:set_visible(false)
	self:set_process(true)
	return self
end

function PlagueTutorial.begin(self)
	self.active = true
	self._i = 1
	self._step_t = 0.0
	self._flash = 0.0
	self._ending = 0.0
	self._said = 0
	self._target = nil
	--- set once the tutorial's match is on screen (leaving it to the title then ends the tutorial)
	self.in_match = false
	self._card:set_visible(false)
end

function PlagueTutorial.stop(self, how: string)
	if not self.active then
		return
	end
	self.active = false
	self._mark.Visible = false
	if how == "done" then
		self._ending = PlagueTutorial.END_S
		self._count:set_text("★")
		self._text:set_text("You're ready! Pop bubbles, evolve, and use 2x / 4x to speed up time.")
		self._skip:set_text("OK")
		self:_tint(UITheme.GREEN)
		self._card:set_visible(true)
		self:_place()
		self.ctx:sfx("unlock", -4.0)
	else
		self._card:set_visible(false)
	end
end

function PlagueTutorial._close(self)
	self._ending = 0.0
	self._card:set_visible(false)
end

function PlagueTutorial._tint(self, col: any)
	self._card:set_accent(col)
	self._card:set_border(UITheme.c(col, 0.5))
	UITheme.set_font_color(self._count, col)
end

function PlagueTutorial.apply_layout(self)
	if self._card.visible then
		self:_place()
	end
end

--- Top centre, under the cure pill.
function PlagueTutorial._place(self)
	local ctx = self.ctx
	local vp, ins = ctx.vp, ctx.insets
	local c = ctx.compact
	self._text:set_font_size(if c then 13 else 15)
	self._text:set_min_size(Vector2.new(if c then 210 else 300, 0))
	self._card:reset_size()
	local sz = self._card:get_combined_minimum_size()
	-- (a phone: drawn smaller to fit across the screen)
	local s, _, fdy = PUI.fit(self._card, vp.X - ins.x - ins.z - 24.0, vp.Y * 0.3, 0.5, 0.0)
	local x = if s < 1
		then (vp.X - sz.X) * 0.5
		else math.clamp((vp.X - sz.X) * 0.5, ins.x + 8.0, math.max(ins.x + 8.0, vp.X - ins.z - sz.X - 8.0))
	local p = self.ui.plague
	local spawn = self.ui.spawn
	local top = if p ~= nil and p.cure.visible then p.cure:bottom_edge() + 8.0 else ins.y + (if c then 62.0 else 74.0)
	-- (picking patient zero: under RoWorld's spawn banner)
	if spawn ~= nil and spawn.visible and spawn.panel.visible then
		top = math.max(top, spawn:bottom_edge() + 8.0)
	end
	-- (the Evolve window is open: at the bottom, so it covers none of the window's header)
	if p ~= nil and p.evolve ~= nil and p.evolve.modal ~= nil and p.evolve.modal.is_open then
		top = vp.Y - ins.w - sz.Y * s - 10.0
	end
	top += fdy
	UICtx.move_node(self._card, Vector2.new(math.floor(x), math.floor(top)))
end

function PlagueTutorial._line(step: any, ctx: any): string
	return if ctx.touch and step.touch then step.touch else step.text
end

function PlagueTutorial._say(self, i: number, arg: string?)
	local step = PlagueTutorial.STEPS[i]
	local txt = if self.ctx.touch and step.touch then step.touch else step.text
	if string.find(txt, "%s", 1, true) then
		txt = string.format(txt, arg or "it")
	end
	self._count:set_text(string.format("%d / %d", i, #PlagueTutorial.STEPS))
	self._text:set_text(txt)
	self._skip:set_text("Skip")
	self:_tint(UITheme.AMBER)
	self._card:set_visible(true)
	self:_place()
	UICtx.pop_in(self._card, 0.0, 0.94, 0.3, true)
	self._said = i
end

function PlagueTutorial._advance(self, passed: boolean?)
	if not passed then
		self.ctx:sfx("confirm", -4.0)
		if self._card.visible then
			self:_tint(UITheme.GREEN)
			self._text:set_text("Nice!")
			self._flash = PlagueTutorial.DONE_S
		end
	end
	self._i += 1
	self._step_t = 0.0
	self._target = nil
	self._base = nil
	if self._i > #PlagueTutorial.STEPS then
		self:stop("done")
	end
end

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

local function infected_count(s: any): number
	local n = 0
	for _, r in s.plague.countries do
		if (r.I or 0) >= 1 then
			n += 1
		end
	end
	return n
end

local function owned_count(s: any): number
	local n = 0
	for _, on in s.plague.owned do
		if on then
			n += 1
		end
	end
	return n
end

local function rect_mark(node: any): (Vector2?, number?)
	if node == nil or not node:is_visible_in_tree() then
		return nil, nil
	end
	local r = node:get_global_rect()
	-- (a wide button: the rings close on a circle a little bigger than its height, not its width)
	return UICtx.rect_center(r), math.min(math.max(r.Width, r.Height) * 0.5, r.Height * 0.5 + 18)
end

--- A suggested start: the first SUGGEST country on the map.
function PlagueTutorial._suggest(self): number
	local s = self.ctx.state
	for _, name in PlagueTutorial.SUGGEST do
		for id, o in s.owners do
			if o.name == name and id ~= s.plague.pid then
				return id
			end
		end
	end
	return 0
end

--- The most populous uninfected neighbour of the countries the plague is in, or 0.
function PlagueTutorial._neighbour(self): number
	local ui = self.ui
	local s = self.ctx.state
	local best, best_pop = 0, -1
	for id in s.owners do
		local row = s:country_row(id)
		if id ~= s.plague.pid and row ~= nil and (row.I or 0) >= 1 then
			local meta = ui.plague.meta_of(id)
			for _, nb in (meta and meta.neighbors) or {} do
				local n = nb[1]
				local r2 = s:country_row(n)
				local m2 = ui.plague.meta_of(n)
				if (r2 == nil or (r2.I or 0) < 1) and m2 ~= nil and m2.pop > best_pop then
					best, best_pop = n, m2.pop
				end
			end
		end
	end
	return best
end

--- The most populous uninfected country a click reaches by `kind` ("land" / "sea"), or 0.
function PlagueTutorial._reachable(self, kind: string): number
	local ui = self.ui
	local s = self.ctx.state
	local PlagueLink = ui.plague and ui.plague.link
	if PlagueLink == nil then
		return 0
	end
	local best, best_pop = 0, -1
	for id, o in s.owners do
		if id ~= s.plague.pid then
			local row = s:country_row(id)
			if row == nil or (row.I or 0) < 1 then
				local k = PlagueLink.route(ui, id)
				if k == kind then
					local pop = (row and row.H) or o.troops or 0
					local meta = ui.plague.meta_of and ui.plague.meta_of(id)
					pop = if meta ~= nil then meta.pop else pop
					if pop > best_pop then
						best, best_pop = id, pop
					end
				end
			end
		end
	end
	return best
end

--- Pans the map to `tile` without zooming in (the player keeps their view).
function PlagueTutorial._look_at(self, tile: number)
	local ctx = self.ctx
	local d = ctx:world_call("camera_distance", {})
	ctx:world_call("focus_tile", { tile, if type(d) == "number" then d else nil })
end

-- ---------------------------------------------------------------------------------------------
-- Per frame
-- ---------------------------------------------------------------------------------------------

function PlagueTutorial._process(self, delta: number)
	self._t += delta
	if self._ending > 0.0 then
		self._ending -= delta
		if self._ending <= 0.0 then
			self:_close()
		end
		return
	end
	if not self.active then
		return
	end
	local ctx = self.ctx
	local ui = self.ui
	local s = ctx.state
	local p = ui.plague
	if s == nil or s.plague == nil or p == nil or ctx:mode() ~= UICtx.MODE_SOLO or ctx.state_mode ~= UICtx.MODE_SOLO then
		self._mark.Visible = false
		return
	end
	self.in_match = true
	if self._flash > 0.0 then
		self._flash -= delta
		self._mark.Visible = false
		return
	end
	local i = self._i
	local cur = PlagueTutorial.STEPS[i]
	-- (no step draws over the game menu, help or shop; a step about the map waits while a window is open)
	local menu = (ui.pause ~= nil and ui.pause.is_open)
		or (ui.help ~= nil and ui.help.is_open)
		or (ui.arsenal ~= nil and ui.arsenal.is_open)
	if menu or (cur ~= nil and cur.id ~= "evolve" and cur.id ~= "buy" and cur.id ~= "close" and p.link.modal_open(ui)) then
		self._mark.Visible = false
		return
	end
	self._step_t += delta
	local step = PlagueTutorial.STEPS[i]
	if step == nil then
		return
	end
	local id = step.id
	local point: Vector2? = nil
	local around: number? = nil
	local word: string? = nil
	-- the step's first frame: what it is about
	if self._said ~= i then
		local arg = nil
		if id == "watch" then
			local o = s.owners[s.plague.start_c or 0]
			arg = if o ~= nil then o.name else nil
		elseif id == "zero" then
			local c = self:_suggest()
			arg = if c > 0 then s.owners[c].name else "India"
			if c > 0 then
				self:_look_at(s:label_tile(c))
			end
		elseif id == "infect" then
			self._target = self:_neighbour()
			if self._target == 0 then
				self:_advance(true)
				return
			end
			arg = s.owners[self._target].name
			self._base = infected_count(s)
			self:_look_at(s:label_tile(self._target))
		elseif id == "ship" then
			self._target = self:_reachable("sea")
			if self._target == 0 then
				self:_advance(true)
				return
			end
			arg = s.owners[self._target].name
			self._base = infected_count(s)
			self:_look_at(s:label_tile(self._target))
		elseif id == "bubble" then
			self._base = p.popped or 0
		elseif id == "buy" then
			self._base = owned_count(s)
			-- (the evolution that lets ships carry it, picked for them: the ship step comes next)
			local Traits = UICtx.data("Traits")
			local want = PlagueTutorial.SHIP_TRAIT
			if not s.plague.owned[want] and Traits.reachable(want, s.plague.owned) and p.evolve.modal.is_open then
				p.evolve:select(want)
			end
		end
		-- (the country card sits top right, over the map: out of the way of what the step points at)
		if (id == "bubble" or id == "infect" or id == "ship") and p.card ~= nil then
			p.card:hide_card()
		end
		self:_say(i, arg)
	end
	if id == "zero" then
		if s.phase ~= Defs.PHASE_SPAWN then
			self:_advance()
			return
		end
		local c = self:_suggest()
		if c > 0 then
			local t = s:label_tile(c)
			point = ctx:tile_screen_pos(t)
			word = s.owners[c] and ("Start in " .. s.owners[c].name) or (if ctx.touch then "Tap a country" else "Click a country")
			if self._step_t > PlagueTutorial.AUTO_ZERO_S then
				ctx:session_call("send_now", { { type = "zero", tile = t } })
			end
		end
		self:_draw_mark(point, word, around)
		return
	elseif id == "watch" then
		local c = s.plague.start_c or 0
		if c > 0 then
			point = ctx:tile_screen_pos(s:label_tile(c))
			word = "Infected here"
		end
	elseif id == "bubble" then
		if (p.popped or 0) > (self._base or 0) then
			self:_advance()
			return
		end
		local b = nil
		for _, x in s.bubbles do
			if x.kind == 0 then
				b = x
				break
			end
		end
		if b ~= nil then
			point = ctx:tile_screen_pos(b.tile)
			if point.X >= 0 then
				point = point - Vector2.new(0, 20)
			end
			around = 18
			word = if ctx.touch then "Tap the bubble" else "Click the bubble"
		end
	elseif id == "infect" or id == "ship" then
		local t = self._target or 0
		local row = if t > 0 then s:country_row(t) else nil
		-- (the ship step is about the ship: only its country counts, not one a hotspot or a traveller took)
		if (id == "infect" and infected_count(s) > (self._base or 0)) or (row ~= nil and (row.I or 0) >= 1) then
			self:_advance()
			return
		end
		-- (the traveller / ship is on its way: nothing to press)
		local sent = false
		for _, f in s.flights do
			if f.infected then
				sent = true
			end
		end
		for _, u in s.units do
			if u.owner == s.plague.pid then
				sent = true
			end
		end
		-- a red hotspot is the quick way in: point at it instead of making the player wait
		local hot = nil
		for _, x in s.bubbles do
			if x.kind == 2 and id == "infect" then
				hot = x
				break
			end
		end
		if sent then
			if self._text.text ~= "On its way! Watch it arrive" then
				self._text:set_text("On its way! Watch it arrive")
			end
		elseif hot ~= nil then
			point = ctx:tile_screen_pos(hot.tile)
			if point.X >= 0 then
				point = point - Vector2.new(0, 20)
			end
			around = 18
			word = "Hotspot!"
			local o = s.owners[s:tile_owner(hot.tile)]
			local want = string.format(
				"%s the red hotspot: it infects %s at once",
				if ctx.touch then "Tap" else "Click",
				if o ~= nil then o.name else "that country"
			)
			if self._text.text ~= want then
				self._text:set_text(want)
			end
		elseif t > 0 then
			point = ctx:tile_screen_pos(s:label_tile(t))
			word = s.owners[t] and s.owners[t].name or nil
			-- (not reachable yet: the card says what is missing, e.g. not enough infected to travel)
			local kind, _, _, reason = p.link.route(ui, t)
			-- (while it builds up, the card says what to do meanwhile, so the wait is not empty)
			local want = if kind == nil and reason ~= nil
				then reason .. ". Pop bubbles and evolve meanwhile"
				else string.format(PlagueTutorial._line(step, ctx), s.owners[t] and s.owners[t].name or "it")
			if self._text.text ~= want then
				self._text:set_text(want)
			end
		end
	elseif id == "evolve" then
		if p.evolve.modal.is_open then
			self:_advance()
			return
		end
		point, around = rect_mark(p.bar._evolve)
		word = if ctx.touch then "Tap EVOLVE" else "Click EVOLVE"
	elseif id == "buy" then
		if owned_count(s) > (self._base or 0) then
			self:_advance()
			return
		end
		if not p.evolve.modal.is_open then
			self:_advance(true)
			return
		end
		local r = p.evolve:buy_rect()
		if r ~= nil then
			point = UICtx.rect_center(r)
			around = math.min(math.max(r.Width, r.Height) * 0.5, r.Height * 0.5 + 18)
			word = "Evolve"
		end
	elseif id == "close" then
		if not p.evolve.modal.is_open then
			self:_advance()
			return
		end
		point, around = rect_mark(p.evolve.modal.close_button)
		word = "Close"
	elseif id == "cure" then
		point, around = rect_mark(p.cure.panel)
		word = "The cure"
	elseif id == "speed" then
		point, around = rect_mark(p.bar._speeds and p.bar._speeds[2])
		word = "2x"
		if p.bar.speed ~= 1 and self._step_t > 1.0 then
			self:_advance()
			return
		end
	end
	if self._step_t > (step.max_s or PlagueTutorial.STEP_MAX_S) then
		-- (the timed steps are read, not done: they pass with a tick)
		self:_advance(id ~= "watch" and id ~= "cure" and id ~= "speed")
		return
	end
	self:_draw_mark(point, word, around)
end

--- The tap mark at logical point `p` (nil / off screen: none). `around`: a control of this radius
--- (the rings close on its edge, no dot).
function PlagueTutorial._draw_mark(self, p: Vector2?, word: string?, around: number?)
	local ctx = self.ctx
	local mark = self._mark
	if p == nil or p.X < 0.0 or p.Y < 0.0 or p.X > ctx.vp.X or p.Y > ctx.vp.Y then
		mark.Visible = false
		return
	end
	ctx:fit_canvas(mark)
	mark.Visible = true
	local k1 = (self._t % 1.1) / 1.1
	local k2 = ((self._t + 0.55) % 1.1) / 1.1
	local inner = if around ~= nil then around + 4.0 else 12.0
	local outer = inner + (if around ~= nil then 16.0 else 22.0)
	UICtx.set_circle(self._ring_a, p, outer - (outer - inner) * k1)
	UICtx.set_circle(self._ring_b, p, outer - (outer - inner) * k2);
	(self._ring_a:FindFirstChild("Stroke") :: UIStroke).Transparency = 1 - k1 * 0.95;
	(self._ring_b:FindFirstChild("Stroke") :: UIStroke).Transparency = 1 - k2 * 0.95
	self._dot.Visible = around == nil
	UICtx.set_circle(self._dot, p, 6.0)
	self._tap.Text = word or (if ctx.touch then "Tap here" else "Click here")
	local gap = outer + 6.0
	local below = p.Y + gap + 26 < ctx.vp.Y - ctx.insets.w - 70
	self._tap.AnchorPoint = Vector2.new(0.5, if below then 0 else 1)
	self._tap.Position = UDim2.fromOffset(p.X, if below then p.Y + gap else p.Y - gap)
end


return PlagueTutorial
