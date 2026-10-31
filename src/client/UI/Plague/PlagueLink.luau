--!nonstrict
-- RoPlague inside RoWorld's interface. UIRoot stays the interface root with everything it has (title,
-- shops, crates, subscription, Arsenal, locker, leaderboard, menus, spawn banner, game-over screen);
-- this module is called from a few hook points in UIRoot (search "PlagueLink") and only takes over
-- in a solo plague match (Core/Plague/PlagueSim):
--   * the war HUD (command bar, world-control bar, attacks, coach) steps aside for the plague's: the
--     bottom bar (UI/Plague/PlagueHud), the world / cure pill (CureBar) and the country card
--   * hovering a country says what a click does; clicking a country infects it (across a border, or
--     by sending an infected ship) — the plague never takes a country's land
--   * EVOLVE opens the skill tree (EvolveScreen); the plague's name can be changed with a gamepass

local UITheme = require("../UITheme")
local PUI = require("./PUI")
local UICtx = require("../UICtx")
local PlagueHud = require("./PlagueHud")
local CureBar = require("./CureBar")
local CountryCard = require("./CountryCard")
local EvolveScreen = require("./EvolveScreen")
local RenameWindow = require("./RenameWindow")
local PlagueTutorial = require("./PlagueTutorial")
local TopNotice = require("./TopNotice")
local WorldList = require("./WorldList")
local RaceBoard = require("./RaceBoard")

--- The cure's milestones a TopNotice line says (and when research starts).
local CURE_MARKS = { 0.25, 0.5, 0.75, 0.9 }
local Defs = UICtx.core("Defs")

local PlagueLink = {}

--- Auto Pop Bubbles (Data/Arsenal auto_pop, a gamepass): every bubble pops by itself this many seconds
--- after it shows, exactly as if it had been pressed (its sound, its DNA, the tutorial's count).
PlagueLink.AUTO_POP_S = 0.5

local plague_core: any = nil
local function core(name: string): any
	plague_core = plague_core or {}
	if plague_core[name] == nil then
		local ok, m = pcall(function()
			if UICtx.IS_ROBLOX then
				local rs = game:GetService("ReplicatedStorage")
				return require(rs:WaitForChild("Airfront").Core.Plague[name])
			end
			return (require :: any)("../../../shared/Core/Plague/" .. name)
		end)
		plague_core[name] = if ok then m else false
	end
	return plague_core[name] or nil
end

local function countries_of(map: any): any
	local C = core("Countries")
	return if C ~= nil and map ~= nil then C.get(map) else nil
end

--- A solo plague match is on screen (the title backdrop is a plague too, but it is not a match).
function PlagueLink.active(ui: any): boolean
	local ctx = ui.ctx
	local s = ctx.state
	if s == nil or s.plague == nil then
		return false
	end
	local mode = ctx:mode()
	-- (RoPlague multiplayer: a server-run plague match, Co-op or 1v1, server/PlagueMatch)
	return (mode == UICtx.MODE_SOLO and ctx.state_mode == UICtx.MODE_SOLO)
		or (mode == UICtx.MODE_MULTI and ctx.state_mode == UICtx.MODE_MULTI)
end

--- A server-run plague match (Co-op, 1v1): no speed buttons, no pause, no tutorial.
function PlagueLink.online(ui: any): boolean
	return PlagueLink.active(ui) and ui.ctx:mode() == UICtx.MODE_MULTI
end

--- This player is a 1v1's cure side (Core/Plague/PlagueSim cure_pid).
function PlagueLink.is_cure(ui: any): boolean
	local s = ui.ctx.state
	local pl = if s ~= nil then s.plague else nil
	return pl ~= nil and (pl.cure_pid or 0) ~= 0 and s.local_owner == pl.cure_pid
end

--- The HUD and the country card follow the match: online or not, plague or cure.
function PlagueLink.set_role(ui: any)
	local p = ui.plague
	if p == nil then
		return
	end
	local cure = PlagueLink.is_cure(ui)
	p.bar:set_role(PlagueLink.online(ui), if cure then "cure" else "plague")
	p.card.cure_side = cure
end

function PlagueLink.modal_open(ui: any): boolean
	local p = ui.plague
	if p == nil then
		return false
	end
	return p.evolve.modal.is_open or p.rename.modal.is_open
end

function PlagueLink.home_owner(ui: any): number
	local s = ui.ctx.state
	local pl = if s ~= nil then s.plague else nil
	if pl ~= nil then
		return pl.start_c or 0
	end
	return ui.ctx:me()
end

--- The plague's name for the next match: the one renamed with the gamepass, else a generated one kept
--- for good (settings "plague_name").
function PlagueLink.plague_name(ui: any): string
	local ctx = ui.ctx
	local n = ctx:setting("plague_name", nil)
	if type(n) ~= "string" or n == "" then
		n = RenameWindow.random_name()
		ctx:set_setting("plague_name", n)
	end
	return n
end

-- =============================================================================================
-- Build (end of UIRoot._build)
-- =============================================================================================

function PlagueLink.build(ui: any)
	local ctx = ui.ctx
	local p = { conns = {}, reached = 0, link = PlagueLink }
	ui.plague = p
	p.meta_of = function(c: number)
		local cs = countries_of(ctx.state and ctx.state.map)
		return if cs ~= nil then cs.list[c] else nil
	end
	local hud = ui.hud
	local cure = CureBar.new(ctx)
	cure.name = "PlagueCure"
	p.cure = cure
	hud:add_child(cure)
	-- big lines under the pill: "+3 DNA", the cure's milestones
	local notice = TopNotice.new(ctx, function()
		if not cure.visible or not cure.panel.visible then
			return nil, nil
		end
		local g = cure.panel.gui
		return g.AbsolutePosition.X + g.AbsoluteSize.X * 0.5, g.AbsolutePosition.Y + g.AbsoluteSize.Y
	end)
	notice.name = "PlagueNotice"
	p.notice = notice
	cure:add_child(notice)
	local bar = PlagueHud.new(ctx)
	-- a 1v1's cure side: its buildings (PlagueRules.BUILDINGS), in the build row and on the country card
	do
		local Rules = core("PlagueRules")
		if Rules and Rules.BUILD_ORDER then
			local list, actions = {}, {}
			for _, k in Rules.BUILD_ORDER do
				local b = Rules.BUILDINGS[k]
				table.insert(list, { k, b.short or b.name, b.cost, b.icon, b.desc, b.name, b.range })
				table.insert(actions, { "build_" .. k, string.upper(b.name), b.cost, b.icon })
			end
			bar:set_build_list(list)
			bar.alarm_cost = Rules.DUEL_COSTS.alert
			CountryCard.CURE_ACTIONS = actions
		end
	end
	bar.name = "PlagueHud"
	p.bar = bar
	bar.evolve_pressed:Connect(function()
		if PlagueLink.is_cure(ui) then
			-- (before research: RAISE ALARM; after it the building slots replace this button)
			ctx:session_call("send_now", { { type = "cure", kind = "alert" } })
			ctx:sfx("confirm")
			return
		end
		PlagueLink.open_evolve(ui)
	end)
	bar.build_picked:Connect(function(key: string)
		-- placing: the next country clicked gets it (PlagueLink.on_click / on_hover)
		local Rules = core("PlagueRules")
		local b = if Rules then Rules.BUILDINGS[key] else nil
		if p.placing == key then
			-- (its slot again: placing called off)
			PlagueLink.set_placing(ui, nil)
			ctx:sfx("close")
			return
		end
		PlagueLink.set_placing(ui, key)
		p.notice:say(
			("CLICK WHERE THE %s GOES"):format(string.upper(if b then b.name else key)),
			UITheme.CYAN:Lerp(Color3.new(1, 1, 1), 0.4)
		)
		ctx:sfx("click")
	end)
	-- RoWorld's SHOP slot: the Arsenal (the plague's perks and colours)
	bar.shop_wanted:Connect(function(key: string?, from: string?)
		ctx:sfx("confirm")
		ui:open_arsenal(key, from or (if key ~= nil then "locked" else "match"))
	end)
	bar.speed_changed:Connect(function(sp: number)
		ctx:session_call("set_speed", { sp })
	end)
	bar.rename_pressed:Connect(function()
		p.rename:request()
		ui:_update_pause()
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
	card.route_of = function(c: number)
		return PlagueLink.route(ui, c)
	end
	card.enemy_of = function(c: number): any?
		return PlagueLink.enemy_of(ui, c)
	end
	card.troops_of = function(src: number): number
		return PlagueLink.attack_troops(ui, src)
	end
	card.infect_pressed:Connect(function(c: number)
		PlagueLink.infect(ui, c)
	end)
	-- a 1v1's cure side: its actions on the country
	card.cure_pressed:Connect(function(kind: string, c: number)
		ctx:session_call("send_now", { { type = "cure", kind = kind, target = c } })
		ctx:sfx(if string.sub(kind, 1, 6) == "build_" then "build" else "confirm")
	end)
	card.built_of = function(c: number): { [string]: boolean }
		return PlagueLink.built_of(ui, c)
	end
	p.card = card
	hud:add_child(card)
	-- the countries not infected yet (the HUD's countries button)
	local world = WorldList.new(ctx)
	world.name = "PlagueWorld"
	world.top_limit = card.top_limit
	world.bottom_limit = function()
		return if bar.visible then bar:top_edge() else ui.root.vp.Y
	end
	world.rows = function()
		return PlagueLink.uninfected(ui)
	end
	world.picked:Connect(function(c: number)
		world:close()
		ctx:world_call("focus_owner", { c })
		card:show_country(c)
	end)
	p.world = world
	hud:add_child(world)
	-- a Plague Race's standings (Session.race)
	local race = RaceBoard.new(ctx)
	race.name = "PlagueRace"
	race.top_limit = function(): number
		return math.max(70.0 + ctx.insets.y, ctx.reserved_top_left.Max.Y + 10.0) - 10.0
	end
	race.leave_pressed:Connect(function()
		ctx:sfx("click")
		ctx:session_call("leave_race")
	end)
	p.race = race
	hud:add_child(race)
	bar.countries_pressed:Connect(function()
		if not world.is_open then
			card:hide_card()
		end
		world:toggle()
		ctx:sfx(if world.is_open then "open" else "close")
	end)
	local evolve = EvolveScreen.new(ctx)
	p.evolve = evolve
	evolve.closed:Connect(function()
		ui:_update_pause()
		ui:_update_input_gate()
	end)
	ui.root:add_child(evolve.modal)
	local rename = RenameWindow.new(ctx)
	p.rename = rename
	rename.renamed:Connect(function(name: string)
		ctx:set_setting("plague_name", name)
		if ui.title ~= nil then
			ui.title:set_plague_name(name)
		end
		if PlagueLink.active(ui) then
			ctx:session_call("rename_plague", { name })
			p.bar:refresh()
			ui.feed:toast(Defs.MSG_GOOD, ("Your plague is now called %s"):format(name))
		end
	end)
	-- the PLAY SOLO window: the name the next plague gets, and a press renames it
	if ui.title ~= nil then
		ui.title:set_plague_name(PlagueLink.plague_name(ui))
		ui.title.rename_plague:Connect(function()
			ctx:sfx("click")
			rename:request()
			ui:_update_input_gate()
		end)
	end
	rename.closed:Connect(function()
		ui:_update_pause()
		ui:_update_input_gate()
	end)
	ui.root:add_child(rename.modal)
	-- the first match's tutorial: last, so its mark is drawn over the windows it points into
	local tut = PlagueTutorial.new(ctx, ui)
	p.tutorial = tut
	ui.root:add_child(tut)
end

--- UIRoot.setup (the session exists now): a Plague Race's board follows Session.race.
function PlagueLink.setup(ui: any)
	local sess = ui.ctx.session
	local p = ui.plague
	if sess == nil or p == nil or sess.race_changed == nil then
		return
	end
	sess.race_changed:Connect(function(r: any)
		p.race:show_race(r)
	end)
end

--- The title's PLAY SOLO starts at once (no strain window any more).
function PlagueLink.open_picker(ui: any, _difficulty: number): boolean
	ui._plague_opts = { name = PlagueLink.plague_name(ui) }
	-- (a Plague Race started from the server names its plague the same way)
	local sess = ui.ctx.session
	if sess ~= nil then
		sess._race_name = ui._plague_opts.name
	end
	return false
end

--- A new player's first match (UIRoot.start_tutorial): a plague on the easiest difficulty with its
--- own step-by-step tutorial (UI/Plague/PlagueTutorial) instead of RoWorld's war tutorial.
function PlagueLink.start_first(ui: any, difficulty: number, map_id: string): boolean
	local ctx = ui.ctx
	ctx:set_setting("tutorial", "done")
	if ui.plague ~= nil then
		ui.plague.tutorial:begin()
	end
	ctx:session_call("start_solo", { difficulty, map_id, { name = PlagueLink.plague_name(ui) } })
	return true
end

--- "How to play" from the game menu / title can replay the tutorial in the next solo match.
function PlagueLink.replay_tutorial(ui: any)
	if ui.plague ~= nil then
		ui.plague.tutorial:begin()
	end
end

function PlagueLink.open_evolve(ui: any)
	local p = ui.plague
	if p == nil or not PlagueLink.active(ui) or ui._screen ~= "play" then
		return
	end
	p.evolve:open()
	ui:_update_pause()
	ui:_update_input_gate()
end

-- =============================================================================================
-- Reach: what a click on a country does (Core/Plague/Reach, on the mirror)
-- =============================================================================================

--- The countries not infected yet: { {c, name, pop, kind} } (kind: how it can be reached now, "land" or
--- "sea"; nil while out of reach). A country someone's traveller is walking into is left out.
function PlagueLink.uninfected(ui: any): { any }
	local s = ui.ctx.state
	local cs = countries_of(s and s.map)
	local out = {}
	if s == nil or s.plague == nil or cs == nil then
		return out
	end
	local rows = s.plague.countries
	for c, meta in cs.list do
		local o = s.owners[c]
		local r = rows[c]
		if o ~= nil and (o.tiles or 0) > 0 and (r == nil or ((r.I or 0) < 1 and (r.D or 0) < 1)) then
			if not ui.plague.card:_coming(c) then
				local kind = PlagueLink.route(ui, c)
				table.insert(out, { c = c, name = o.name or meta.name or "?", pop = meta.pop or 0, kind = kind })
			end
		end
	end
	return out
end

function PlagueLink.route(ui: any, c: number): (string?, number, number, string?)
	local s = ui.ctx.state
	local Reach = core("Reach")
	local cs = countries_of(s and s.map)
	if s == nil or s.plague == nil or Reach == nil or cs == nil then
		return nil, 0, 0, nil
	end
	local rows = s.plague.countries
	local Traits = UICtx.data("Traits")
	-- (the same options as PlagueSim._route_opts, from the mirror)
	local water, stow = s.plague.sea_bonus or 0, 0
	for id, on in s.plague.owned or {} do
		local t = Traits.by_id[id]
		if on and t ~= nil then
			water += t.fx.water or 0
			stow += t.fx.stow or 0
		end
	end
	-- (a shared world: only the local plague's countries carry it, PlagueSim.route)
	local shared = s:shared_world()
	local me = s.plague.pid
	local function mine(r: any): boolean
		return not shared or (r.holder or 0) == me
	end
	local n = 0
	for _, r in rows do
		if (r.I or 0) >= 1 and mine(r) then
			n += 1
		end
	end
	local Rules = core("PlagueRules")
	local opts = {
		water = water,
		stow = stow,
		ships = water > 0,
		min_hosts = if Rules ~= nil then Rules.TRAVEL_MIN else 1,
		extra = if Rules ~= nil then math.floor(n / Rules.INFECT_COST_STEP) else 0,
	}
	local kind, src, cost, reason = Reach.route(cs, s.map, c, function(x)
		local r = rows[x]
		return if r ~= nil and mine(r) then (r.I or 0) else 0
	end, function(x)
		local r = rows[x]
		return if r ~= nil then (r.closed or 0) else 0
	end, opts)
	if kind ~= nil and PlagueLink.enemy_of(ui, c) ~= nil and Rules ~= nil then
		cost += Rules.ATTACK_DNA
	end
	return kind, src, cost, reason
end

--- A shared world: the enemy plague's row (GameState.plague_row) holding country c, or nil (free, or
--- the local plague's own, or not a shared world).
function PlagueLink.enemy_of(ui: any, c: number): any?
	local s = ui.ctx.state
	if s == nil or s.plague == nil or not s:shared_world() then
		return nil
	end
	local r = s.plague.countries[c]
	local h = if r ~= nil then (r.holder or 0) else 0
	if h == 0 or h == s.plague.pid or (r.I or 0) < 1 then
		return nil
	end
	return s:plague_row(h)
end

--- A 1v1's cure side: placing `key` (nil: not placing). The slot reads pressed, and the map shows the
--- building's range under the cursor and the ranges of the cure's other buildings (RoWorld's way).
function PlagueLink.set_placing(ui: any, key: string?)
	local p = ui.plague
	p.placing = key
	p.bar:set_placing(key)
	PlagueLink.show_ranges(ui, p.hover_tile)
end

--- The range circles while placing: the one under the cursor (tile t) and every cure building's.
function PlagueLink.show_ranges(ui: any, t: number?)
	local p = ui.plague
	local s = ui.ctx.state
	local Rules = core("PlagueRules")
	if p.placing == nil or s == nil or s.plague == nil or Rules == nil then
		ui.ctx:world_call("set_plague_ranges", { nil })
		return
	end
	local list = {}
	local by_struct = {}
	for _, b in Rules.BUILDINGS do
		by_struct[b.struct] = b
	end
	for _, st in s.structures do
		local b = by_struct[st.kind]
		if st.owner == s.plague.cure_pid and b ~= nil then
			table.insert(list, { tile = st.tile, range = b.range, ghost = false })
		end
	end
	local b = Rules.BUILDINGS[p.placing]
	if b ~= nil and t ~= nil and t >= 0 then
		table.insert(list, { tile = t, range = b.range, ghost = true })
	end
	ui.ctx:world_call("set_plague_ranges", { list })
end

--- A 1v1: the cure's buildings in country c (a set of PlagueRules.BUILDINGS keys), from the cure's
--- structures on the map.
function PlagueLink.built_of(ui: any, c: number): { [string]: boolean }
	local s = ui.ctx.state
	local Rules = core("PlagueRules")
	local out = {}
	if s == nil or s.plague == nil or Rules == nil or (s.plague.cure_pid or 0) == 0 then
		return out
	end
	local by_struct = {}
	for key, b in Rules.BUILDINGS do
		by_struct[b.struct] = key
	end
	for _, st in s.structures do
		if st.owner == s.plague.cure_pid and s:tile_owner(st.tile) == c then
			local key = by_struct[st.kind]
			if key ~= nil then
				out[key] = true
			end
		end
	end
	return out
end

--- How many infected an attack out of country `src` sends (PlagueRules.attack_troops).
function PlagueLink.attack_troops(ui: any, src: number): number
	local s = ui.ctx.state
	local Rules = core("PlagueRules")
	if s == nil or s.plague == nil or Rules == nil then
		return 0
	end
	local r = s.plague.countries[src]
	return Rules.attack_troops(if r ~= nil then (r.I or 0) else 0)
end

--- A short note for the player, once: the same note (its numbers aside) again within SAY_GAP seconds
--- is not shown twice (a player clicking a country over and over got a stack of near-identical lines).
PlagueLink.SAY_GAP = 4.0
function PlagueLink.say_once(ui: any, text: string)
	local p = ui.plague
	local key = string.gsub(text, "%d+", "#")
	local now = os.clock()
	if p.said_key == key and now - (p.said_at or 0) < PlagueLink.SAY_GAP then
		return
	end
	p.said_key, p.said_at = key, now
	ui.feed:toast(Defs.MSG_INFO, text, nil, 3.5)
end

function PlagueLink.infect(ui: any, c: number)
	local ctx = ui.ctx
	local kind, _, cost, reason = PlagueLink.route(ui, c)
	local s = ctx.state
	if kind == nil then
		if reason ~= nil and reason ~= "Already infected" then
			PlagueLink.say_once(ui, reason)
		end
		ctx:sfx("error", -4.0)
		return
	end
	if s ~= nil and (s.plague.dna or 0) < cost then
		PlagueLink.say_once(ui, ("You need %d DNA"):format(cost))
		ctx:sfx("error", -4.0)
		return
	end
	ctx:session_call("send_now", { { type = "infect", target = c } })
	ctx:sfx(if kind == "sea" then "boat" else "plague_send", -3.0, 0.05)
end

-- =============================================================================================
-- Input (UIRoot.setup's world signals)
-- =============================================================================================

local function country_at(ui: any, t: number): number
	local s = ui.ctx.state
	if s == nil or t == nil or t < 0 then
		return 0
	end
	local c = s:tile_owner(t)
	return if s.plague ~= nil and c ~= s.plague.pid then c else 0
end

--- A click on the map in a plague match: patient zero during the spawn phase, else infect the country
--- under it (and show its card). True when handled (RoWorld's war interaction then gets nothing).
function PlagueLink.on_click(ui: any, t: number): boolean
	if not PlagueLink.active(ui) then
		return false
	end
	local ctx = ui.ctx
	local s = ctx.state
	local p = ui.plague
	local c = country_at(ui, t)
	if s.phase == Defs.PHASE_SPAWN then
		local row0 = if c > 0 then s:country_row(c) else nil
		if PlagueLink.is_cure(ui) then
			-- (a 1v1's cure side: the plague's player picks where it starts)
			p.notice:say("THE PLAGUE IS CHOOSING WHERE TO START", PUI.CURE:Lerp(Color3.new(1, 1, 1), 0.55))
			ctx:sfx("deny", -6.0)
		elseif s:shared_world() and (s.plague.start_c or 0) > 0 then
			-- (a shared world: placed; everyone starts once the last plague is placed)
			p.notice:say("WAITING FOR THE OTHER PLAGUES TO START", PUI.INFECTED:Lerp(Color3.new(1, 1, 1), 0.55))
			ctx:sfx("deny", -6.0)
		elseif row0 ~= nil and (row0.holder or 0) ~= 0 then
			PlagueLink.say_once(ui, "Another plague starts there: pick another country")
			ctx:sfx("error", -4.0)
		elseif c > 0 then
			ctx:session_call("send_now", { { type = "zero", tile = t } })
			ctx:sfx("spawn_confirm")
		end
		return true
	end
	if c <= 0 then
		p.card:hide_card()
		return true
	end
	if PlagueLink.is_cure(ui) and p.placing ~= nil then
		-- (the cure's side: a building is being placed, on the tile clicked)
		local key = p.placing
		PlagueLink.set_placing(ui, nil)
		if PlagueLink.built_of(ui, c)[key] then
			PlagueLink.say_once(ui, "It already has one")
			ctx:sfx("error", -4.0)
			return true
		end
		ctx:session_call("send_now", { { type = "cure", kind = "build_" .. key, target = c, tile = t } })
		ctx:sfx("build")
		p.card:show_country(c)
		return true
	end
	p.world:close()
	p.card:show_country(c)
	if PlagueLink.is_cure(ui) then
		-- (the cure's side: the card's buttons act; a click infects nothing)
		return true
	end
	local row = s:country_row(c)
	if row == nil or (row.I or 0) < 1 or PlagueLink.enemy_of(ui, c) ~= nil then
		-- (a shared world: an enemy plague's country is attacked the same way)
		PlagueLink.infect(ui, c)
	end
	return true
end

--- A bubble on the map was pressed (MapView.bubble_clicked): collect it.
function PlagueLink.on_bubble(ui: any, id: number)
	if not PlagueLink.active(ui) then
		return
	end
	local ctx = ui.ctx
	-- (each kind its own sound: a DNA bubble's pop, a hotspot's thump, a cure bubble's chime)
	local b = ctx.state and ctx.state.bubbles and ctx.state.bubbles[id]
	local kind = if b ~= nil then b.kind else 0
	if PlagueLink.is_cure(ui) and kind ~= 1 then
		-- (a 1v1's cure side pops only the cure bubbles: the others are the plague's)
		ctx:sfx("deny", -6.0)
		return
	end
	ctx:session_call("send_now", { { type = "pop", id = id } })
	ctx:sfx(if kind == 2 then "plague_hotspot" elseif kind == 1 then "plague_cure" else "plague_pop", -1.0, 0.1)
	if ui.plague ~= nil then
		ui.plague.popped = (ui.plague.popped or 0) + 1
	end
end

--- Hovering the map in a plague match: the country and what a click on it would do.
function PlagueLink.on_hover(ui: any, t: number): boolean
	if not PlagueLink.active(ui) then
		return false
	end
	local ctx = ui.ctx
	local s = ctx.state
	local c = country_at(ui, t)
	ui.plague.hover_tile = t
	if ui.plague.placing ~= nil then
		PlagueLink.show_ranges(ui, t)
	end
	-- RoWorld's country highlight under the cursor
	ctx:world_call("set_hover_owner", { c })
	local tooltip = ui.tooltip
	if tooltip == nil or ctx.touch then
		return true
	end
	if c <= 0 then
		tooltip:hide_tip()
		return true
	end
	local cs = countries_of(s.map)
	local meta = if cs ~= nil then cs.list[c] else nil
	local row = s:country_row(c)
	local pop = if meta ~= nil then meta.pop else 0
	local H = if row ~= nil then row.H else pop
	local I = if row ~= nil then row.I else 0
	local D = if row ~= nil then row.D else 0
	local spec = {
		title = if s.owners[c] then s.owners[c].name else "",
		sub = "Population " .. PUI.people(pop),
		rows = {
			{ "Healthy", PUI.people(H), Color3.fromRGB(120, 214, 160) },
			{ "Infected", PUI.people(I), Color3.fromRGB(255, 90, 90) },
			{ "Dead", PUI.people(D), Color3.fromRGB(150, 150, 165) },
		},
	}
	if s.phase == Defs.PHASE_SPAWN then
		spec.hint = if PlagueLink.is_cure(ui)
			then "The plague is choosing where to start"
			elseif s:shared_world() and (s.plague.start_c or 0) > 0 then "Waiting for the other plagues to start"
			elseif row ~= nil and (row.holder or 0) ~= 0 then "Another plague starts here"
			else "Click: start your plague here"
		spec.hint_color = UITheme.AMBER
	elseif PlagueLink.is_cure(ui) and ui.plague.placing ~= nil then
		local Rules = core("PlagueRules")
		local b = if Rules then Rules.BUILDINGS[ui.plague.placing] else nil
		if b ~= nil then
			local funds = math.floor(s.plague.funds or 0)
			if PlagueLink.built_of(ui, c)[ui.plague.placing] then
				spec.hint = ("It already has a %s"):format(b.name)
				spec.hint_color = UITheme.TEXT_3
			elseif funds < b.cost then
				spec.hint = ("A %s costs %d funds (you have %d)"):format(b.name, b.cost, funds)
				spec.hint_color = UITheme.TEXT_3
			else
				spec.hint = ("Click: build a %s here (%d funds). %s"):format(b.name, b.cost, b.desc)
				spec.hint_color = UITheme.CYAN
			end
		end
	elseif PlagueLink.is_cure(ui) then
		spec.hint = if s.plague.research == true
			then "Click: see it. BUILD to place a building"
			else "Click: see it. Raise the alarm to start research"
		spec.hint_color = UITheme.CYAN
	elseif I < 1 and D >= 1 and H < 1 then
		spec.hint = "Wiped out: no one left to infect"
		spec.hint_color = UITheme.TEXT_3
	elseif PlagueLink.enemy_of(ui, c) ~= nil then
		-- a shared world: another plague holds it, so a click attacks it
		local foe = PlagueLink.enemy_of(ui, c)
		spec.sub = ("Held by %s  ·  "):format(foe.name or "another plague") .. spec.sub
		if ui.plague.card:_coming(c) then
			spec.hint = "Your attack is on the way"
			spec.hint_color = PUI.INFECTED
		else
			local kind, src, cost, reason = PlagueLink.route(ui, c)
			if kind ~= nil then
				local troops = PUI.people(PlagueLink.attack_troops(ui, src))
				spec.hint = if kind == "sea"
					then ("Click: send a ship of %s infected to attack (%d DNA)"):format(troops, cost)
					else ("Click: ATTACK with %s infected (%d DNA)"):format(troops, cost)
				spec.hint_color = Color3.fromRGB(255, 110, 90)
			else
				spec.hint = reason or "Out of reach: border it or reach its coast first"
				spec.hint_color = UITheme.TEXT_3
			end
		end
	elseif I < 1 and ui.plague.card:_coming(c) then
		spec.hint = "An infected traveller is on the way"
		spec.hint_color = PUI.INFECTED
	elseif I < 1 then
		local kind, _, cost, reason = PlagueLink.route(ui, c)
		if kind == "land" then
			spec.hint = ("Click: infect it across the border (%d DNA)"):format(cost)
			spec.hint_color = UITheme.AMBER
		elseif kind == "sea" then
			spec.hint = ("Click: send an infected ship (%d DNA)"):format(cost)
			spec.hint_color = UITheme.CYAN
		else
			spec.hint = reason or "Out of reach"
			spec.hint_color = UITheme.TEXT_3
		end
	end
	tooltip:show_follow(spec)
	return true
end

-- =============================================================================================
-- State, screens, layout (UIRoot._bind_state / _apply_screen / _layout / slow poll)
-- =============================================================================================

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
	p.last_dna = nil
	p.cure_mark = nil
	p.notice:clear()
	p.card:hide_card()
	p.world:close()
	p.race:show_world(nil)
	p.held_at = 0
	ui.ctx:world_call("set_plague_holders", { nil })
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
	-- a shared world (Plague Race, teams): a country won or lost in an attack
	c("country_captured", function(country: number, new_pid: number, old_pid: number)
		if not on() or ui._screen ~= "play" then
			return
		end
		local me = s.plague and s.plague.pid
		local name = if s.owners[country] then s.owners[country].name else "a country"
		if new_pid == me then
			p.notice:say(("YOU TOOK %s"):format(string.upper(name)), PUI.INFECTED:Lerp(Color3.new(1, 1, 1), 0.4))
			ctx:sfx("conquer", -2.0)
		elseif old_pid == me then
			local foe = s:plague_row(new_pid)
			p.notice:say(
				("%s TOOK %s"):format(string.upper(if foe ~= nil then tostring(foe.name) else "AN ENEMY"), string.upper(name)),
				Color3.fromRGB(255, 120, 100)
			)
			ctx:sfx("alarm", -4.0)
		end
	end)
	c("plague_changed", function()
		local pl = s.plague
		if s:shared_world() then
			p.race:show_world(s)
			-- (each held country's border in its plague's colour; checked twice a second)
			local now = os.clock()
			if now - (p.held_at or 0) >= 0.5 then
				p.held_at = now
				local index = {}
				for i, r in pl.plagues do
					index[r.pid] = i
				end
				local held = {}
				for country, row in pl.countries do
					local k = index[row.holder or 0]
					if k ~= nil and (row.I or 0) >= 1 then
						held[country] = k
					end
				end
				ctx:world_call("set_plague_holders", { held })
			end
		end
		-- DNA gained since the last update (spending lowers it: not said), and the cure's milestones
		local dna = if pl ~= nil then tonumber(pl.dna) or 0 else 0
		if p.last_dna ~= nil and dna > p.last_dna and on() and ui._screen == "play" and not PlagueLink.is_cure(ui) then
			p.notice:dna(dna - p.last_dna)
		end
		p.last_dna = dna
		if pl ~= nil and pl.research == true then
			local cure = tonumber(pl.cure) or 0
			if p.cure_mark == nil then
				-- (joined mid-way: only the milestones still ahead are said; research has started
				-- unless this is its first update)
				p.cure_mark = 0
				for _, m in CURE_MARKS do
					if cure >= m then
						p.cure_mark = m
					end
				end
				if cure <= 0.001 and on() and ui._screen == "play" then
					p.notice:say("THE CURE RACE HAS STARTED", PUI.CURE:Lerp(Color3.new(1, 1, 1), 0.55))
				end
			end
			for _, m in CURE_MARKS do
				if cure >= m and p.cure_mark < m then
					p.cure_mark = m
					if on() and ui._screen == "play" then
						p.notice:say(("CURE RESEARCH %d%% DONE"):format(math.floor(m * 100 + 0.5)), PUI.CURE:Lerp(Color3.new(1, 1, 1), 0.55))
						ctx:sfx("plague_cure", -4.0, 0.05)
					end
				end
			end
		elseif pl ~= nil then
			p.cure_mark = nil
		end
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
	-- Auto Pop Bubbles: owned now (bought mid-match counts at once), pops the bubble AUTO_POP_S later
	c("bubble_added", function(id: number)
		local sess = ctx.session
		local inv = if sess ~= nil then sess.inventory else nil
		if inv == nil or inv.unlocks == nil or not inv.unlocks.auto_pop then
			return
		end
		task.delay(PlagueLink.AUTO_POP_S, function()
			local st = ctx.state
			if st ~= s or st.bubbles[id] == nil or st.phase ~= Defs.PHASE_PLAYING or not on() then
				return
			end
			PlagueLink.on_bubble(ui, id)
		end)
	end)
	c("country_infected", function()
		p.reached += 1
		-- (a new country catching it is heard, not only seen; patient zero has its own sound)
		if on() and p.reached > 1 then
			ctx:sfx("plague_infect", -3.0, 0.06)
		end
	end)
	c("trait_changed", function(id: string, owned: boolean, how: number)
		if not on() then
			return
		end
		p.bar:refresh()
		if p.evolve.modal.is_open then
			p.evolve:refresh()
		end
		-- a bought evolution already sounds from the Evolve screen; a random mutation is news
		local Traits = UICtx.data("Traits")
		local t = Traits.by_id[id]
		if t ~= nil and owned and how == 1 then
			-- (the sim's own news line says it: "<plague> mutated: <symptom>"; a second toast was spam)
			ctx:sfx("unlock")
		end
	end)
	local cs = countries_of(s.map)
	p.bar.country_total = if cs ~= nil then cs.count else 0
	p.bar:refresh()
	p.cure:refresh(true)
end

--- End of UIRoot._update_input_gate: the war HUD pieces it re-shows stay hidden in a plague match.
function PlagueLink.gate(ui: any)
	if ui.plague == nil or not PlagueLink.active(ui) then
		return
	end
	ui.coach:set_visible(false)
	ui.spectate_pill:set_visible(false)
	ui.interact.enabled = false
end

function PlagueLink.apply_screen(ui: any, scr: string, changed: boolean)
	local p = ui.plague
	if p == nil then
		return
	end
	local on = PlagueLink.active(ui)
	-- (a plague match keeps its news short: three lines at most)
	ui.feed.max_toasts = if on then 3 else nil
	p.cure:set_visible(on and (scr == "play" or scr == "over"))
	p.bar:set_visible(on and scr == "play")
	if not on or scr ~= "play" then
		p.world:close()
	end
	if not on or scr == "title" then
		p.card:hide_card()
		if p.tutorial.active and p.tutorial.in_match and scr == "title" then
			p.tutorial:stop("left")
		end
		if p.evolve.modal.is_open then
			p.evolve:close()
		end
		return
	end
	-- the war HUD steps aside (RoWorld's spawn banner, tooltip, menus and game over stay)
	ui.top:set_visible(false)
	ui.bar:set_visible(false)
	-- (a shared world keeps RoWorld's attacks panel: who you attack, who attacks you, how many)
	local st = ui.ctx.state
	ui.attacks:set_visible(scr == "play" and st ~= nil and st:shared_world())
	ui.spectate_pill:set_visible(false)
	ui.board:set_visible(false)
	ui.coach:set_visible(false)
	if ui.alert ~= nil then
		ui.alert:set_visible(false)
	end
	if ui.tutorial ~= nil and ui.tutorial.active then
		ui.tutorial:stop("left")
	end
	if scr ~= "play" and p.evolve.modal.is_open then
		p.evolve:close()
	end
	if changed and scr == "play" then
		PlagueLink.set_role(ui)
		p.bar:refresh()
		p.cure:refresh(true)
	end
end

function PlagueLink.layout(ui: any)
	local p = ui.plague
	if p == nil then
		return
	end
	p.cure:apply_layout()
	p.bar:apply_layout()
	p.tutorial:apply_layout()
	p.card:apply_layout()
	p.world:apply_layout()
	p.race:apply_layout()
	p.evolve:apply_layout()
	p.rename:apply_layout()
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
		-- the tooltip under a still cursor follows the country (infected since, now reachable...)
		local t = p.hover_tile
		if t ~= nil and t >= 0 and ui.tooltip ~= nil and ui.tooltip:is_shown() then
			PlagueLink.on_hover(ui, t)
		end
	end
	local bottom = if p.bar.visible then p.bar:top_edge() else ui.root.vp.Y - ui.ctx.insets.w
	ui.feed:apply_layout(bottom - 12.0)
end

return PlagueLink
