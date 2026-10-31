--!nonstrict
-- RoPlague inside RoWorld's interface. UIRoot stays the interface root, with everything it has (title,
-- shops, crates, subscription, Arsenal, locker, leaderboard, menus); this module adds the plague match's
-- HUD and windows to it and is called from a few hook points in UIRoot (search "PlagueLink").
--
-- In a solo plague match the war HUD (command bar, world-control status, spawn banner, attacks, coach)
-- steps aside for the plague's (UI/Plague): the bottom HUD, the cure bar, the patient-zero banner, the
-- country card, Evolve, tips and the result window. The title and every meta screen are RoWorld's own.

local UICtx = require("../UICtx")
local PlagueHud = require("./PlagueHud")
local CureBar = require("./CureBar")
local CountryCard = require("./CountryCard")
local EvolveScreen = require("./EvolveScreen")
local PathogenPicker = require("./PathogenPicker")
local ZeroBanner = require("./ZeroBanner")
local PlagueOver = require("./PlagueOver")
local PlagueTutorial = require("./PlagueTutorial")
local Defs = UICtx.core("Defs")

local PlagueLink = {}

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

--- A solo plague match is on screen (the title backdrop is a plague too, but it is not a match).
function PlagueLink.active(ui: any): boolean
	local ctx = ui.ctx
	local s = ctx.state
	return s ~= nil and s.plague ~= nil and ctx:mode() == UICtx.MODE_SOLO and ctx.state_mode == UICtx.MODE_SOLO
end

--- A plague window is open over the map (it pauses a solo match and takes the map's input).
function PlagueLink.modal_open(ui: any): boolean
	local p = ui.plague
	if p == nil then
		return false
	end
	return p.evolve.modal.is_open or p.picker.modal.is_open or p.over.modal.is_open
end

function PlagueLink.home_owner(ui: any): number
	local s = ui.ctx.state
	local p = if s ~= nil then s.plague else nil
	return if p ~= nil then (p.start_c or 0) else 0
end

-- =============================================================================================
-- Build (end of UIRoot._build)
-- =============================================================================================

function PlagueLink.build(ui: any)
	local ctx = ui.ctx
	local p = { reached = 0, conns = {} }
	ui.plague = p
	local hud = ui.hud
	local cure = CureBar.new(ctx)
	cure.name = "PlagueCure"
	p.cure = cure
	hud:add_child(cure)
	local bar = PlagueHud.new(ctx)
	bar.name = "PlagueHud"
	p.bar = bar
	bar.evolve_pressed:Connect(function()
		PlagueLink.open_evolve(ui)
	end)
	bar.speed_changed:Connect(function(sp: number)
		ctx:session_call("set_speed", { sp })
	end)
	bar.ability_pressed:Connect(function()
		local s = ctx.state
		local pl = if s ~= nil then s.plague else nil
		local Traits = UICtx.data("Traits")
		local path = if pl ~= nil then Traits.pathogen_by_id[pl.pathogen or ""] else nil
		if path ~= nil and path.ability ~= nil then
			ctx:session_call("send_now", { { type = "ability", key = path.ability } })
			ctx:sfx("confirm")
		end
	end)
	hud:add_child(bar)
	local card = CountryCard.new(ctx)
	card.name = "PlagueCountry"
	card.top_limit = function()
		return if cure.visible then cure:bottom_edge() else 60.0
	end
	card.meta_of = function(c: number)
		local cs = countries_of(ctx.state and ctx.state.map)
		return if cs ~= nil then cs.list[c] else nil
	end
	p.card = card
	hud:add_child(card)
	local zero = ZeroBanner.new(ctx)
	zero.name = "PlagueZero"
	p.zero = zero
	hud:add_child(zero)
	local tut = PlagueTutorial.new(ctx)
	tut.name = "PlagueTips"
	tut.top_limit = function()
		if cure.visible then
			return cure:bottom_edge()
		end
		if zero.visible then
			return zero.panel:get_global_rect().Max.Y
		end
		return 60.0
	end
	p.tut = tut
	hud:add_child(tut)
	local picker = PathogenPicker.new(ctx)
	p.picker = picker
	picker.start:Connect(function(pathogen: string, difficulty: number, name: string)
		ui._plague_opts = { pathogen = pathogen, name = name }
		ui._plague_go = true
		ui:_on_play_solo(difficulty)
	end)
	picker.closed:Connect(function()
		ui:_update_input_gate()
	end)
	ui.root:add_child(picker.modal)
	local evolve = EvolveScreen.new(ctx)
	p.evolve = evolve
	evolve.closed:Connect(function()
		ui:_update_pause()
		ui:_update_input_gate()
		tut:on_event("evolve_closed")
	end)
	ui.root:add_child(evolve.modal)
	local over = PlagueOver.new(ctx)
	p.over = over
	over.again:Connect(function()
		ui:_restart_solo(tonumber(ctx:setting("difficulty", 1)) or 1)
	end)
	over.menu:Connect(function()
		ctx:session_call("start_title")
	end)
	ui.root:add_child(over.modal)
end

-- =============================================================================================
-- Setup / state (UIRoot.setup, UIRoot._bind_state)
-- =============================================================================================

function PlagueLink.setup(ui: any)
	local world = ui.ctx.world
	if world ~= nil and world.bubble_clicked ~= nil then
		table.insert(
			ui._conns,
			world.bubble_clicked:Connect(function(id: number)
				if PlagueLink.active(ui) then
					ui.ctx:session_call("send_now", { { type = "pop", id = id } })
				end
			end)
		)
	end
	ui.ctx:world_call("set_borders", { nil })
end

--- The title's PLAY SOLO: the pathogen window first (UIRoot._on_play_solo calls this, then starts the
--- match once START is pressed). True when the window took over.
function PlagueLink.open_picker(ui: any, difficulty: number): boolean
	local p = ui.plague
	if p == nil then
		return false
	end
	p.picker.difficulty = math.clamp(tonumber(difficulty) or 1, 0, 2)
	p.picker:open()
	ui:_update_input_gate()
	return true
end

function PlagueLink.open_evolve(ui: any)
	local p = ui.plague
	if p == nil or not PlagueLink.active(ui) or ui._screen ~= "play" then
		return
	end
	p.evolve:open()
	ui:_update_pause()
	ui:_update_input_gate()
	p.tut:on_event("evolve_opened")
end

function PlagueLink.bind_state(ui: any, s: any)
	local p = ui.plague
	if p == nil then
		return
	end
	for _, c in p.conns do
		c:Disconnect()
	end
	p.conns = {}
	p.reached = 0
	p.card:hide_card()
	if s == nil or s.plague == nil then
		return
	end
	local ctx = ui.ctx
	local function c(name: string, cb: (...any) -> ())
		local sig = s[name]
		if type(sig) == "table" and sig.Connect then
			table.insert(p.conns, sig:Connect(cb))
		end
	end
	local function on(): boolean
		return PlagueLink.active(ui)
	end
	c("plague_changed", function()
		if on() then
			p.cure:refresh()
			if p.evolve.modal.is_open then
				p.evolve:refresh()
			end
			if p.card.country ~= 0 then
				p.card:refresh()
			end
		end
	end)
	c("phase_changed", function()
		if on() and s.phase == Defs.PHASE_PLAYING then
			p.tut:on_event("started")
		end
	end)
	c("country_infected", function()
		p.reached += 1
		if on() then
			ctx:sfx("expand_pop", -6.0, 0.05)
		end
	end)
	c("trait_changed", function(_id: string, owned: boolean, how: number)
		if not on() then
			return
		end
		p.bar:refresh()
		if p.evolve.modal.is_open then
			p.evolve:refresh()
		end
		if how == 0 and owned then
			p.tut:on_event("evolved")
		end
	end)
	c("dna_gained", function(amount: number, tile: number, reason: number)
		if on() and tile ~= nil and tile >= 0 and reason ~= 0 then
			ctx:world_call("dna_float", { tile, amount })
		end
	end)
	c("bubble_added", function()
		if on() then
			p.tut:on_event("bubble")
		end
	end)
	c("bubble_removed", function(_id, popped: boolean)
		if on() and popped then
			ctx:sfx("star_tick", -4.0, 0.06)
			p.tut:on_event("popped")
		end
	end)
	c("country_closed", function()
		if on() then
			p.tut:on_event("closed")
		end
	end)
	p.bar:refresh()
	p.cure:refresh(true)
end

-- =============================================================================================
-- Input (UIRoot.setup's world signals)
-- =============================================================================================

--- A click on the map in a plague match: patient zero during the spawn phase, the country card after.
--- True when handled (the war interaction then gets nothing).
function PlagueLink.on_click(ui: any, t: number): boolean
	if not PlagueLink.active(ui) then
		return false
	end
	local ctx = ui.ctx
	local s = ctx.state
	local p = ui.plague
	local c = if t ~= nil and t >= 0 then s:tile_owner(t) else 0
	local pid = s.plague.pid
	if s.phase == Defs.PHASE_SPAWN then
		if c > 0 and c ~= pid then
			ctx:session_call("send_now", { { type = "zero", tile = t } })
			ctx:sfx("spawn_confirm")
			p.card:show_country(c)
		end
		return true
	end
	if c > 0 and c ~= pid then
		p.card:show_country(c)
	else
		p.card:hide_card()
	end
	return true
end

-- =============================================================================================
-- Screens, layout, frame (UIRoot._apply_screen / _layout / _process)
-- =============================================================================================

function PlagueLink.apply_screen(ui: any, scr: string, changed: boolean)
	local p = ui.plague
	if p == nil then
		return
	end
	local on = PlagueLink.active(ui)
	p.zero:set_visible(on and scr == "spawn")
	p.cure:set_visible(on and (scr == "play" or scr == "over"))
	p.bar:set_visible(on and scr == "play")
	if not on or scr == "title" then
		p.card:hide_card()
		p.tut:hide()
		if p.evolve.modal.is_open then
			p.evolve:close()
		end
		if p.over.modal.is_open then
			p.over.modal:close(true)
		end
		return
	end
	-- the war HUD steps aside
	ui.spawn:set_visible(false)
	ui.top:set_visible(false)
	ui.bar:set_visible(false)
	ui.attacks:set_visible(false)
	ui.spectate_pill:set_visible(false)
	ui.board:set_visible(false)
	ui.coach:set_visible(false)
	if ui.alert ~= nil then
		ui.alert:set_visible(false)
	end
	ui.interact.enabled = false
	if ui.tutorial ~= nil and ui.tutorial.active then
		ui.tutorial:stop("left")
	end
	if scr ~= "play" and p.evolve.modal.is_open then
		p.evolve:close()
	end
	if changed then
		if scr == "spawn" then
			p.zero:on_show()
			p.tut:on_event("spawn")
		elseif scr == "play" then
			p.bar:refresh()
			p.cure:refresh(true)
		elseif scr == "over" then
			local cs = countries_of(ui.ctx.state and ui.ctx.state.map)
			p.tut:hide()
			p.over:show(p.reached, if cs ~= nil then cs.count else 0)
		end
	end
end

function PlagueLink.layout(ui: any)
	local p = ui.plague
	if p == nil then
		return
	end
	p.zero:apply_layout()
	p.cure:apply_layout()
	p.bar:apply_layout()
	p.card:apply_layout()
	p.tut:apply_layout()
	p.picker:apply_layout()
	p.evolve:apply_layout()
	p.over:apply_layout()
	if PlagueLink.active(ui) then
		local ctx = ui.ctx
		local bottom = if p.bar.visible then p.bar:top_edge() else ui.root.vp.Y - ctx.insets.w
		ui.feed:apply_layout(bottom - 12.0)
	end
end

--- Twice a second (UIRoot's slow poll).
function PlagueLink.poll(ui: any)
	local p = ui.plague
	if p == nil or not PlagueLink.active(ui) then
		return
	end
	if ui._screen == "play" then
		p.bar:refresh()
	end
	p.tut:poll()
	local bottom = if p.bar.visible then p.bar:top_edge() else ui.root.vp.Y - ui.ctx.insets.w
	ui.feed:apply_layout(bottom - 12.0)
end

--- War HUD parts whose per-frame update UIRoot skips in a plague match.
PlagueLink.WAR_FRAME = { bar = true, top = true, board = true, attacks = true, alert = true }

return PlagueLink
