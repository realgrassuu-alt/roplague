--!nonstrict
-- RoPlague interface root (replaces RoFront's UIRoot). Built in code on RoFront's kit: one ScreenGui
-- holding a Widgets.Root, the same layers, frame loop and layout rules, so every panel keeps its look.
--
-- Screens: "title" (the wordmark over a plague spreading by itself), "spawn" (choose patient zero),
-- "play" (HUD, cure bar, news, country card, Evolve), "over" (the result window).
-- Wire with setup(session, world, audio). Main owns the top bar and calls toggle_help,
-- toggle_leaderboard, open_settings, open_pause_menu and screen().

local UITheme = require("../UITheme")
local W = require("../Widgets")
local UICtx = require("../UICtx")
local UILayoutProbe = require("../UILayoutProbe")
local Tooltip = require("../Tooltip")
local HelpOverlay = require("../HelpOverlay")
local PauseMenu = require("../PauseMenu")
local EventFeed = require("../EventFeed")
local PUI = require("./PUI")
local PlagueHud = require("./PlagueHud")
local CureBar = require("./CureBar")
local CountryCard = require("./CountryCard")
local EvolveScreen = require("./EvolveScreen")
local PathogenPicker = require("./PathogenPicker")
local PlagueTitle = require("./PlagueTitle")
local ZeroBanner = require("./ZeroBanner")
local PlagueOver = require("./PlagueOver")
local PlagueTutorial = require("./PlagueTutorial")
local Signal = UITheme.core("Signal")
local Defs = UICtx.core("Defs")

local Countries: any = nil
local function countries_of(map: any): any
	if Countries == nil then
		local ok, m = pcall(function()
			if UICtx.IS_ROBLOX then
				local rs = game:GetService("ReplicatedStorage")
				return require(rs:WaitForChild("Airfront").Core.Plague.Countries)
			end
			return (require :: any)("../../../shared/Core/Plague/Countries")
		end)
		Countries = if ok then m else false
	end
	if not Countries or map == nil then
		return nil
	end
	return Countries.get(map)
end

local PlagueRoot = {}
PlagueRoot.__index = PlagueRoot
PlagueRoot.FONT_WAIT_S = 2.5

function PlagueRoot.new(opts: any?)
	local self = setmetatable({}, PlagueRoot)
	opts = opts or {}
	self.music_toggled = Signal.new()
	self.labels_toggled = Signal.new()
	self.leaderboard_toggled = Signal.new()
	self.help_toggled = Signal.new()
	self.screen_changed = Signal.new()
	self.topbar_provider = nil
	self.ctx = UICtx.new()
	self._screen = ""
	self._conns = {}
	self._conns_state = {}
	self._poll = 0.0
	self._last_vp = Vector2.zero
	self._apply_pending = false
	self._last_pathogen = nil
	self._last_difficulty = 1
	self._last_name = nil
	self._reached = 0
	local ctx = self.ctx
	local UIS = if UICtx.IS_ROBLOX then game:GetService("UserInputService") else nil
	ctx.touch_device = UIS ~= nil and UIS.TouchEnabled and not UIS.MouseEnabled
	if opts.touch_device ~= nil then
		ctx.touch_device = opts.touch_device
	end
	ctx.touch = ctx.touch_device
	self.labels_on = ctx:setting("labels", true) ~= false
	self:_make_gui(opts.parent)
	self:_build()
	self:_layout()
	self:_apply_screen()
	return self
end

-- =============================================================================================
-- Construction
-- =============================================================================================

function PlagueRoot._make_gui(self, parent: Instance?)
	local sg = Instance.new("ScreenGui")
	sg.Name = "AirfrontUI"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ScreenInsets = Enum.ScreenInsets.None
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.DisplayOrder = 10
	local p = parent
	if p == nil and UICtx.IS_ROBLOX then
		local lp = game:GetService("Players").LocalPlayer
		p = if lp then lp:WaitForChild("PlayerGui") else nil
	end
	sg.Parent = p
	self.gui = sg
	if UICtx.IS_ROBLOX and not UITheme.fonts_ready() then
		task.spawn(UITheme.init)
		local t0 = os.clock()
		while not UITheme.fonts_ready() and os.clock() - t0 < PlagueRoot.FONT_WAIT_S do
			task.wait()
		end
	end
	local root = W.Root.new(sg, { touch_device = self.ctx.touch_device })
	root.name = "UI"
	self.root = root
	self.ctx.root = root
	W.set_external_driver(true)
end

function PlagueRoot._layer(self, n: string)
	local c = W.Control.new()
	c.name = n
	c.gui.Name = n
	c:set_anchors_and_offsets_preset(W.PRESET_FULL_RECT)
	c:set_mouse_filter(W.MOUSE_IGNORE)
	return c
end

function PlagueRoot._build(self)
	local ctx = self.ctx
	local root = self.root
	-- the HUD layer
	local hud = self:_layer("HUD")
	self.hud = hud
	local cure = CureBar.new(ctx)
	cure.name = "CureBar"
	self.cure = cure
	hud:add_child(cure)
	local feed = EventFeed.new(ctx)
	feed.name = "EventFeed"
	self.feed = feed
	hud:add_child(feed)
	local bar = PlagueHud.new(ctx)
	bar.name = "PlagueHud"
	self.bar = bar
	bar.evolve_pressed:Connect(function()
		self:open_evolve()
	end)
	bar.speed_changed:Connect(function(sp: number)
		ctx:session_call("set_speed", { sp })
		ctx:sfx("tab", -3.0, 0.02)
	end)
	bar.ability_pressed:Connect(function()
		local s = ctx.state
		local p = if s ~= nil then s.plague else nil
		local Traits = UICtx.data("Traits")
		local path = if p ~= nil then Traits.pathogen_by_id[p.pathogen or ""] else nil
		if path ~= nil and path.ability ~= nil then
			ctx:send({ type = "ability", key = path.ability })
			ctx:sfx("confirm")
		end
	end)
	hud:add_child(bar)
	local card = CountryCard.new(ctx)
	card.name = "CountryCard"
	card.top_limit = function()
		return if self.cure.visible then self.cure:bottom_edge() else 60.0
	end
	card.meta_of = function(c: number)
		local cs = countries_of(ctx.state and ctx.state.map)
		return if cs ~= nil then cs.list[c] else nil
	end
	self.card = card
	hud:add_child(card)
	root:add_child(hud)
	local zero = ZeroBanner.new(ctx)
	zero.name = "ZeroBanner"
	self.zero = zero
	root:add_child(zero)
	-- tutorial tips
	local tut = PlagueTutorial.new(ctx)
	tut.name = "Tutorial"
	self.tutorial = tut
	tut.top_limit = function()
		if self.cure.visible then
			return self.cure:bottom_edge()
		end
		if self.zero.visible then
			return self.zero.panel:get_global_rect().Max.Y
		end
		return 60.0
	end
	root:add_child(tut)
	-- title
	local title = PlagueTitle.new(ctx)
	title.name = "Title"
	self.title = title
	title.play:Connect(function()
		ctx:sfx("confirm")
		self.picker:open()
	end)
	title.show_help:Connect(function()
		self:toggle_help()
	end)
	root:add_child(title)
	-- windows
	local picker = PathogenPicker.new(ctx)
	self.picker = picker
	picker.start:Connect(function(pathogen: string, difficulty: number, name: string)
		self:_start_solo(pathogen, difficulty, name)
	end)
	root:add_child(picker.modal)
	local evolve = EvolveScreen.new(ctx)
	self.evolve = evolve
	evolve.closed:Connect(function()
		self:_update_pause()
		self.tutorial:on_event("evolve_closed")
	end)
	root:add_child(evolve.modal)
	local over = PlagueOver.new(ctx)
	self.over = over
	over.again:Connect(function()
		self:_start_solo(self._last_pathogen, self._last_difficulty, self._last_name)
	end)
	over.menu:Connect(function()
		ctx:session_call("start_title")
	end)
	root:add_child(over.modal)
	local help = HelpOverlay.new(ctx)
	help.name = "Help"
	self.help = help
	help.closed:Connect(function()
		self.help_toggled:Fire(false)
		self:_update_pause()
	end)
	root:add_child(help)
	local pause = PauseMenu.new(ctx)
	pause.name = "Pause"
	self.pause = pause
	pause.closed:Connect(function()
		self:_update_pause()
	end)
	pause.help_requested:Connect(function()
		pause:close()
		self:toggle_help()
	end)
	pause.leave_requested:Connect(function()
		pause:close()
		ctx:session_call("start_title")
	end)
	pause.restart_requested:Connect(function()
		pause:close()
		self:_start_solo(self._last_pathogen, self._last_difficulty, self._last_name)
	end)
	pause.music_toggled:Connect(function(on: boolean)
		if ctx.audio ~= nil and ctx.audio.set_music_enabled then
			ctx.audio:set_music_enabled(on)
		end
		self.music_toggled:Fire(on)
	end)
	pause.labels_toggled:Connect(function(on: boolean)
		self.labels_on = on
		ctx:set_setting("labels", on)
		ctx:world_call("set_labels_visible", { on })
		self.labels_toggled:Fire(on)
	end)
	if pause.pops_toggled ~= nil then
		pause.pops_toggled:Connect(function(on: boolean)
			ctx:set_pops(on)
		end)
	end
	if pause.tips_reset ~= nil then
		pause.tips_reset:Connect(function()
			ctx:set_setting("plague_tutorial", nil)
			self.tutorial:reset()
		end)
	end
	root:add_child(pause)
	local tooltip = Tooltip.new(ctx)
	tooltip.name = "Tooltip"
	self.tooltip = tooltip
	ctx.tooltip = tooltip
	root:add_child(tooltip)
	self.probe = UILayoutProbe.new(self)
	if UICtx.IS_ROBLOX then
		local RunService = game:GetService("RunService")
		self._step_name = "RoPlagueUI_" .. tostring(math.random(1, 1e9))
		local FrameClock = require("../../Map/FrameClock") :: any
		RunService:BindToRenderStep(self._step_name, Enum.RenderPriority.Camera.Value + 10, function(real_dt)
			local dt = FrameClock.dt(real_dt)
			W.guard("PlagueRoot._process", self._process, self, dt)
			W.guard("Widgets.step", W.step, dt)
		end)
		table.insert(
			self._conns,
			root.resized:Connect(function()
				self:_layout()
			end)
		)
	end
end

-- =============================================================================================
-- Public API (Main, tests)
-- =============================================================================================

function PlagueRoot.screen(self): string
	return self._screen
end

function PlagueRoot.setup(self, session: any, world: any, audio: any)
	local ctx = self.ctx
	ctx.session = session
	ctx.world = world
	ctx.audio = audio
	W.button_sound = function(kind: string, _button: any)
		if kind == "hover" then
			if not ctx.touch then
				ctx:sfx("hover", -12.0, 0.03)
			end
		elseif kind == "tab" then
			ctx:sfx("tab", -3.0, 0.02)
		else
			ctx:sfx("click", -1.0, 0.03)
		end
	end
	local function sig(obj: any, name: string, cb: (...any) -> ())
		local s = obj ~= nil and obj[name]
		if type(s) == "table" and s.Connect then
			table.insert(self._conns, s:Connect(cb))
		end
	end
	if session ~= nil then
		ctx:reload_settings()
		self.labels_on = ctx:setting("labels", true) ~= false
		sig(session, "state_ready", function(s)
			self:_bind_state(s)
		end)
		sig(session, "mode_changed", function()
			self:_request_apply()
		end)
		sig(session, "building_started", function()
			self:_request_apply()
		end)
		sig(session, "notice", function(text: string, severity: number)
			self.feed:toast(if severity ~= nil and severity > 0 then Defs.MSG_BAD else Defs.MSG_INFO, text)
		end)
		sig(session, "settings_loaded", function()
			ctx:reload_settings()
			self.tutorial:reload()
		end)
		if session.state ~= nil then
			self:_bind_state(session.state)
		end
	end
	if world ~= nil then
		sig(world, "tile_clicked", function(t: number)
			self:_on_tile_clicked(t)
		end)
		sig(world, "bubble_clicked", function(id: number)
			self:_pop_bubble(id)
		end)
		ctx:world_call("set_labels_visible", { self.labels_on })
	end
	if audio ~= nil then
		sig(audio, "music_enabled_changed", function(on)
			self.pause:sync_music(on)
		end)
		if audio.pops_enabled_changed ~= nil then
			sig(audio, "pops_enabled_changed", function(on)
				self.pause:sync_pops(on)
			end)
		end
	end
	self:_request_apply()
end

function PlagueRoot.toggle_help(self)
	if self.help.is_open then
		self.help:close()
	else
		self.help:open()
		self.help_toggled:Fire(true)
	end
	self:_update_pause()
end

--- (The top bar's leaderboard button: RoPlague has no leaderboard; Main hides the button.)
function PlagueRoot.toggle_leaderboard(_self) end

function PlagueRoot.open_settings(self)
	self.pause:open(self.labels_on, "settings")
	self:_update_pause()
end

function PlagueRoot.open_pause_menu(self)
	if self._screen == "title" then
		self:open_settings()
		return
	end
	self.pause:open(self.labels_on)
	self:_update_pause()
end

function PlagueRoot.open_evolve(self)
	if self._screen ~= "play" then
		return
	end
	self.evolve:open()
	self:_update_pause()
	self.tutorial:on_event("evolve_opened")
end

--- The country of the patient-zero pick, for Main's "centre on" button.
function PlagueRoot.home_owner(self): number
	local s = self.ctx.state
	local p = if s ~= nil then s.plague else nil
	return if p ~= nil then (p.start_c or 0) else 0
end

-- =============================================================================================
-- Matches
-- =============================================================================================

function PlagueRoot._start_solo(self, pathogen: string?, difficulty: number?, name: string?)
	local ctx = self.ctx
	self._last_pathogen = pathogen or self._last_pathogen or "bacterium"
	self._last_difficulty = difficulty or self._last_difficulty or 1
	self._last_name = name or self._last_name or PathogenPicker.random_name()
	self.card:hide_card()
	self.bar:set_speed(1, false)
	ctx:session_call("start_solo", {
		self._last_difficulty,
		nil,
		{ pathogen = self._last_pathogen, name = self._last_name },
	})
end

function PlagueRoot._bind_state(self, s: any)
	local ctx = self.ctx
	for _, c in self._conns_state do
		c:Disconnect()
	end
	self._conns_state = {}
	ctx.state = s
	local sm = if ctx.session ~= nil then tonumber(ctx.session.state_mode) else nil
	ctx.state_mode = sm or ctx:mode()
	self.feed:clear()
	self.card:hide_card()
	self._reached = 0
	if s == nil then
		self:_request_apply()
		return
	end
	local function c(name: string, cb: (...any) -> ())
		local sig = s[name]
		if type(sig) == "table" and sig.Connect then
			table.insert(self._conns_state, sig:Connect(cb))
		end
	end
	local function solo(): boolean
		return ctx:mode() == UICtx.MODE_SOLO
	end
	c("plague_changed", function()
		if solo() then
			self.cure:refresh()
			if self.evolve.modal.is_open then
				self.evolve:refresh()
			end
			if self.card.country ~= 0 then
				self.card:refresh()
			end
		end
	end)
	c("message", function(_to, category: number, text: string)
		if solo() then
			self.feed:toast(category, text)
		end
	end)
	c("phase_changed", function(_phase)
		self:_request_apply()
		if solo() and s.phase == Defs.PHASE_PLAYING then
			self.tutorial:on_event("started")
		end
	end)
	c("game_over", function()
		self:_request_apply()
	end)
	c("country_infected", function(_cc, _tile)
		self._reached += 1
		if solo() then
			ctx:sfx("expand_pop", -6.0, 0.05)
		end
	end)
	c("trait_changed", function(id: string, owned: boolean, how: number)
		if not solo() then
			return
		end
		self.bar:refresh()
		if self.evolve.modal.is_open then
			self.evolve:refresh()
		end
		if how == 1 and owned then
			self.tutorial:on_event("mutated")
		elseif how == 0 and owned then
			self.tutorial:on_event("evolved")
		end
		local _ = id
	end)
	c("dna_gained", function(amount: number, tile: number, reason: number)
		if solo() and tile ~= nil and tile >= 0 and reason ~= 0 then
			ctx:world_call("dna_float", { tile, amount })
		end
	end)
	c("bubble_added", function(_id)
		if solo() then
			self.tutorial:on_event("bubble")
		end
	end)
	c("bubble_removed", function(_id, popped: boolean)
		if solo() and popped then
			ctx:sfx("star_tick", -4.0, 0.06)
			self.tutorial:on_event("popped")
		end
	end)
	c("country_closed", function(_cc, _bits, _old)
		if solo() then
			self.tutorial:on_event("closed")
		end
	end)
	self.bar:refresh()
	self.cure:refresh(true)
	self:_request_apply()
end

function PlagueRoot._on_tile_clicked(self, t: number)
	local ctx = self.ctx
	local s = ctx.state
	if s == nil or ctx:mode() ~= UICtx.MODE_SOLO then
		return
	end
	local c = if t ~= nil and t >= 0 then s:tile_owner(t) else 0
	local pid = if s.plague ~= nil then s.plague.pid else -1
	if s.phase == Defs.PHASE_SPAWN then
		if c > 0 and c ~= pid then
			ctx:session_call("send_now", { { type = "zero", tile = t } })
			ctx:sfx("spawn_confirm")
			self.card:show_country(c)
		end
		return
	end
	if c > 0 and c ~= pid then
		self.card:show_country(c)
		ctx:sfx("click", -4.0, 0.03)
	else
		self.card:hide_card()
	end
end

function PlagueRoot._pop_bubble(self, id: number)
	local ctx = self.ctx
	if ctx:mode() ~= UICtx.MODE_SOLO then
		return
	end
	ctx:session_call("send_now", { { type = "pop", id = id } })
end

-- =============================================================================================
-- Screens
-- =============================================================================================

function PlagueRoot._request_apply(self)
	if self._apply_pending then
		return
	end
	self._apply_pending = true
	task.defer(function()
		self._apply_pending = false
		self:_apply_screen()
	end)
end

function PlagueRoot._compute_screen(self): string
	local ctx = self.ctx
	local s = ctx.state
	if s == nil or ctx:mode() ~= UICtx.MODE_SOLO or ctx.state_mode ~= UICtx.MODE_SOLO then
		return "title"
	end
	if s.phase == Defs.PHASE_SPAWN then
		return "spawn"
	elseif s.phase == Defs.PHASE_OVER then
		return "over"
	end
	return "play"
end

function PlagueRoot._apply_screen(self)
	local scr = self:_compute_screen()
	local changed = scr ~= self._screen
	self._screen = scr
	local in_game = scr == "play" or scr == "over"
	self.title:set_visible(scr == "title")
	self.zero:set_visible(scr == "spawn")
	self.hud:set_visible(in_game)
	self.cure:set_visible(in_game)
	self.bar:set_visible(scr == "play")
	if scr ~= "play" and self.evolve.modal.is_open then
		self.evolve:close()
	end
	if scr == "title" or scr == "spawn" then
		self.card:hide_card()
	end
	if changed then
		if scr == "title" then
			self.title:on_show()
			self.tutorial:hide()
			self.ctx:set_music_mood("title")
		elseif scr == "spawn" then
			self.zero:on_show()
			self.tutorial:on_event("spawn")
			self.ctx:set_music_mood("calm")
		elseif scr == "play" then
			self.bar:refresh()
			self.cure:refresh(true)
			self.ctx:set_music_mood("calm")
		elseif scr == "over" then
			local cs = countries_of(self.ctx.state and self.ctx.state.map)
			self.over:show(self._reached, if cs ~= nil then cs.count else 0)
			self.tutorial:hide()
			local s = self.ctx.state
			self.ctx:set_music_mood(if s ~= nil and s.over_reason == Defs.OVER_EXTINCT then "victory" else "defeat")
		end
		self:_layout()
		self.screen_changed:Fire(scr)
	end
	self:_update_pause()
end

--- Solo pauses while a window is open over the map (help, menu, Evolve).
function PlagueRoot._update_pause(self)
	local ctx = self.ctx
	local open = self.help.is_open or self.pause.is_open or self.evolve.modal.is_open
	if ctx:mode() == UICtx.MODE_SOLO then
		ctx:set_paused(open)
	end
	ctx:set_world_input(not (open or self.picker.modal.is_open or self.over.modal.is_open))
end

-- =============================================================================================
-- Layout and frame
-- =============================================================================================

function PlagueRoot._layout(self)
	local root = self.root
	if root == nil then
		return
	end
	local ctx = self.ctx
	local vp = root.vp
	ctx.vp = vp
	ctx:update_origin()
	ctx.insets = self.probe:safe_insets()
	self._last_vp = vp
	ctx.compact = vp.Y < 560.0 or vp.X < 900.0
	ctx.reserved_top_left = self.probe:airship_reserved()
	UITheme.min_font_size = if ctx.touch then 12 else 0
	self.title:apply_layout()
	self.zero:apply_layout()
	self.cure:apply_layout()
	self.bar:apply_layout()
	self.card:apply_layout()
	self.tutorial:apply_layout()
	self.picker:apply_layout()
	self.evolve:apply_layout()
	self.over:apply_layout()
	self.help:apply_layout()
	self.pause:apply_layout()
	local bar_top = if self.bar.visible then self.bar:top_edge() else vp.Y - ctx.insets.w
	self.feed:apply_layout(bar_top - 12.0)
end

function PlagueRoot._process(self, dt: number)
	local ctx = self.ctx
	self.feed:update(dt)
	self._poll += dt
	if self._poll >= 0.5 then
		self._poll = 0.0
		if self._screen == "play" then
			self.bar:refresh()
		end
		local vp = self.root.vp
		if vp ~= self._last_vp then
			self:_layout()
		end
		self.tutorial:poll()
	end
	local _ = ctx
end

function PlagueRoot.destroy(self)
	for _, c in self._conns do
		c:Disconnect()
	end
	for _, c in self._conns_state do
		c:Disconnect()
	end
	if UICtx.IS_ROBLOX and self._step_name then
		game:GetService("RunService"):UnbindFromRenderStep(self._step_name)
	end
	if self.gui then
		self.gui:Destroy()
	end
end

return PlagueRoot
