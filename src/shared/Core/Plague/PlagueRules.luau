--!strict
-- RoPlague: every tunable number of the plague simulation (DESIGN.md §3-§4). Rates are per in-game
-- DAY; one day is DAY_TICKS ticks (1 s of play at 1x). Tuned with tools/balance/run.luau.
local R = {}

R.TICK_RATE = 10
R.DAY_TICKS = 10

--- Closure bits (shared with Reach and the interface).
R.C_AIR = 1
R.C_PORT = 2
R.C_BORDER = 4
R.C_QUARANTINE = 8
R.C_COLLAPSE = 16

-- Clicking a country (the "infect" intent) --------------------------------------------------------
--- DNA to infect a country that borders an infected one / one across the sea (a ship sails there).
R.INFECT_LAND_DNA = 1
R.INFECT_SEA_DNA = 2
--- Extra DNA when the target has closed its borders (land) or its ports (sea).
R.INFECT_CLOSED_DNA = 2
--- Travellers (the air traits, fx.air) and ships' water (fx.water): each day the plague may turn up by
--- itself in a far country (air: any country with open airports, by population) or on a coast that
--- shares a sea with an infected one (water). Chance per day = K * fx * reach, where reach grows with
--- how many countries are infected (full at JUMP_FULL).
R.AIR_JUMP_K = 0.12
R.SEA_JUMP_K = 0.08
R.JUMP_FULL = 6
R.JUMP_HOSTS = 3
--- Hosts a click plants.
R.INFECT_HOSTS = 6
--- Patient zero brings this many infected.
R.ZERO_HOSTS = 4
--- The outbreak (so the start is seen to go somewhere): in patient zero's country the plague grows at
--- least ZERO_GROWTH a day, and nobody there recovers, until ZERO_OUTBREAK of its people are infected
--- (India, 4 -> 137M, in about 30 days; a small country much sooner). After that it never falls back
--- under that share: only the infected above it recover.
R.ZERO_OUTBREAK = 0.10
R.ZERO_GROWTH = 0.6
--- A country needs this many infected before a traveller or a ship can leave it for another (the
--- plague has to take hold first: grow it, pop bubbles on it, or evolve).
R.TRAVEL_MIN = 150
--- Every INFECT_COST_STEP infected countries, a click costs 1 DNA more.
R.INFECT_COST_STEP = 25
--- Ships need a water trait (Water Supply, Ballast Water, Sewer Colony, Stowaway, Hardy Spores) or the
--- Sea Legs perk.

-- Shop perks (Data/Arsenal, bought with Stars, kept for good; Session passes them in config.perks) ----
R.PERK_HEAD_START_DNA = 6
R.PERK_BUBBLE_RATE = 1.45
R.PERK_ZERO_HOSTS = 250
--- Sea Legs: as if the plague had this much of the water traits (ships from the start, +60 tiles).
R.PERK_SEA_WATER = 0.075
R.PERK_GENE_BANK = 0.85
R.PERK_SLOW_SCIENCE = 0.15
--- A ship sails at most SEA_RANGE tiles (coast to coast, straight line), plus SEA_RANGE_WATER per
--- point of the water traits (Water Supply 0.15 -> +120; both water traits and Hardy -> about +400).
R.SEA_RANGE = 170
R.SEA_RANGE_WATER = 800
--- A land infection is carried by an infected traveller who walks from inside the infected country to
--- the border: WALK_FROM tiles back from the border at most, WALK_TILES_PER_TICK tiles a tick, taking
--- WALK_MIN..WALK_MAX ticks.
R.WALK_FROM = 34
R.WALK_TILES_PER_TICK = 0.6
R.WALK_MIN_TICKS = 25
R.WALK_MAX_TICKS = 60

-- Population -------------------------------------------------------------------------------------
--- Infections per infected host per day in a neutral country, before any trait.
R.BASE_BETA = 0.052
--- Infected hosts who get better each day (back to healthy: no immunity). The base infectivity is only
--- a little above it, so a plague that never evolves crawls (about 1% a day) and the Transmission and
--- Symptom evolutions are what make it race: each one's `beta` counts TRAIT_BETA times.
R.RECOVER = 0.042
R.TRAIT_BETA = 2.6
--- Climate: share of the infectivity kept in a hot / cold country with no resistance; each level of
--- Heat / Cold Tolerance gives back half of what is lost (two levels: none lost).
R.CLIMATE_KEEP = 0.55
--- Wealth 1 (poorest) .. 5 (richest): health care slows the spread. Drug Resistance levels give back
--- half (one level) or all (two) of a rich country's penalty.
R.WEALTH_BETA = { 1.25, 1.12, 1.0, 0.85, 0.72 }
R.DENSITY_BETA = { urban = 1.2, normal = 1.0, rural = 0.88 }
--- A quarantined country keeps this share of its infectivity.
R.QUARANTINE_KEEP = 0.6
--- New infections land as this many hosts.
R.SEED_HOSTS = 3

-- Land borders -------------------------------------------------------------------------------------
--- Daily chance a neighbour is seeded: 1 - exp(-LAND_K * land * prev^LAND_EXP * share * open), where
--- share is the border's part of the infected country's whole border, and open is 1, or
--- BORDER_LEAK once the neighbour closes its border.
R.LAND_K = 0.5
R.LAND_EXP = 0.6
R.BORDER_LEAK = 0.2

-- Ships and flights --------------------------------------------------------------------------------
--- Mean days between departures from one open port / airport.
R.SHIP_DAYS = 16
R.FLIGHT_DAYS = 6
--- Chance a departure from an infected country carries it: min(CARRY_MAX, prev^CARRY_EXP * (base + bonus)).
R.CARRY_EXP = 0.4
R.SHIP_CARRY = 0.5
R.FLIGHT_CARRY = 0.5
R.CARRY_MAX = 0.95
--- Ships sail this many tiles per tick; flights take dist / FLIGHT_SPEED ticks within the bounds.
R.SHIP_TILES_PER_TICK = 1.2
R.FLIGHT_SPEED = 22
R.FLIGHT_MIN_TICKS = 20
R.FLIGHT_MAX_TICKS = 90
--- At most this many of each on the map (the oldest keep sailing; new departures wait).
R.MAX_SHIPS = 140
--- Flight destinations: sqrt(population) / (1 + distance / FLIGHT_REACH) — long hauls are common.
R.FLIGHT_REACH = 1600
--- Cargo still sails to a closed port (at this share of the traffic); it is turned away, but with
--- CLOSED_LEAK (plus the Stowaway trait) the disease slips ashore anyway.
R.CLOSED_PORT_TRAFFIC = 0.5
R.CLOSED_LEAK = 0.1
R.MAX_FLIGHTS = 90
--- Each port trades with up to SHIP_PARTNERS others (chosen once: near and populous ports first, and
--- every choice goes both ways, so a small island always trades with its region):
--- weight = population ^ PARTNER_POP_EXP / (1 + distance / PARTNER_REACH).
R.SHIP_PARTNERS = 7
R.PARTNER_POP_EXP = 0.3
R.PARTNER_REACH = 350
--- Refugee boats: once a day a healthy country with ports is reached with chance
--- REFUGEE_K * (world dead share) * (1 + REFUGEE_STOW * Stowaway) * (highest infected share among its
--- trading partners) — closed or not. Islands stay hard early, and fall as the world collapses.
R.REFUGEE_K = 0.15
R.REFUGEE_STOW = 2.0
--- New sea routes looked up per tick (cached afterwards).
R.PATH_BUDGET = 2

-- Awareness, governments, cure ---------------------------------------------------------------------
--- Awareness per day = AWARE_K * (severity + SEV_FLOOR) * sqrt(infected share of the world).
--- The world notices at 1.0: research starts, governments may act.
R.AWARE_K = { 0.02, 0.03, 0.042 }
R.SEV_FLOOR = 0.6
--- Days a fully funded, healthy world needs for the cure (by difficulty: casual, normal, brutal).
R.CURE_DAYS = { 360, 175, 150 }
--- Infected researchers work at this share; the dying world funds the cure harder:
--- rate * (1 + PANIC * min(1, PANIC_DEAD * dead share)).
R.SICK_RESEARCHER = 0.75
R.PANIC = 1.0
R.PANIC_DEAD = 3.0
--- Funding ramps from 0 to 1: per day FUND_BASE + FUND_ALARM * alarm, faster in rich countries.
R.FUND_BASE = 1 / 70
R.FUND_ALARM = 0.25
--- A country thinks every GOV_THINK ticks (staggered); an action whose trigger holds fires with
--- this chance per think.
R.GOV_THINK = 15
R.GOV_ACT_P = 0.35
--- Alarm = (infected + dead) / population * (1 + severity / 10), times the country's own nerve.
--- Triggers by difficulty multiplier (a higher multiplier reacts sooner).
R.GOV_DIFF = { 0.7, 1.0, 1.45 }
R.CLOSE_AIR = 0.012
R.CLOSE_AIR_RICH = 0.004
R.CLOSE_PORT = 0.02
R.CLOSE_BORDER_NEIGHBOUR = 0.05
R.QUARANTINE = 0.06
--- Countries with no land neighbour shut early once the world is alarmed.
R.ISLAND_WORLD_ALARM = 0.02
--- ...but only with this chance per think (a few get through first).
R.ISLAND_ACT_P = 0.06
--- Chance (by wealth 1..5) that a country never shuts its ports / its airports: poorer countries keep
--- trading, which is what lets a disease reach the islands after the world wakes up.
R.LAX_PORT = { 0.55, 0.45, 0.2, 0.05, 0 }
R.LAX_AIR = { 0.4, 0.3, 0.12, 0, 0 }
--- Dead share at which a country collapses (stops funding the cure).
R.COLLAPSE_DEAD = 0.5
--- The end (2026-10-30, "it feels a little slow at the end"): the last 1% of humanity took about 200 days,
--- mostly small countries the plague reached late. Once END_WORLD_DEAD of the world is dead, every
--- infected country falls apart: nobody recovers, its survivors catch it at least END_SPREAD a day, its
--- infected die at least END_KILL a day; and wherever fewer than END_FLOOR people (plus END_FLOOR_SHARE
--- of the population) are left alive, they die.
R.END_WORLD_DEAD = 0.85
R.END_SPREAD = 0.3
R.END_KILL = 0.2
R.END_FLOOR = 2000
--- ...and each day a country still untouched then catches it with this chance (survivors fleeing the
--- dying world bring it): a far island or Antarctica no longer holds the last day up for weeks.
R.END_SEED_P = 0.2
R.END_FLOOR_SHARE = 0.0002

-- DNA ----------------------------------------------------------------------------------------------
R.DNA_START = 6
--- Passive DNA per day: base + k_i * sqrt(infected share) + k_d * sqrt(dead share).
R.DNA_BASE = 0.06
R.DNA_INFECTED = 0.2
R.DNA_DEAD = 0.12
--- First infection of a country: this much at once, plus a bubble.
R.DNA_NEW_COUNTRY = 1
R.DNA_FIRST_DEATH = 0
--- Bubbles: one every BUBBLE_DAYS (random in range) in a random infected country; it lives
--- BUBBLE_LIFE ticks. Cure bubbles appear in funding countries once research starts.
--- (2026-10-29, "reduce how many little buttons you can click, but the same reward": half as many,
--- each worth twice as much; and never more than MAX_DNA_BUBBLES DNA bubbles / MAX_CURE_BUBBLES cure
--- bubbles at once: one that would be over the cap is added to the newest live one instead, which
--- then pays both and lives on. Nothing is lost by the cap.)
R.BUBBLE_DAYS = { 8, 16 }
R.BUBBLE_VALUE = { 2, 4 }
R.BUBBLE_LIFE = 160
R.NEW_COUNTRY_BUBBLE = 2
R.MAX_DNA_BUBBLES = 2
R.MAX_CURE_BUBBLES = 1
--- A DNA bubble popped also plants this many infected where it floated (the spot catches it), times
--- how many bubbles went into it.
R.BUBBLE_HOSTS = 20
R.CURE_BUBBLE_DAYS = { 20, 36 }
R.CURE_BUBBLE_CUT = 0.008
R.CURE_BUBBLE_DNA = 2
--- Hotspots (something to do): every HOTSPOT_DAYS a red bubble floats over an uninfected country next to
--- the plague (a festival, a crowded market...); popping it infects the country at once with
--- HOTSPOT_HOSTS and pays HOTSPOT_DNA. Missed, it just goes.
R.HOTSPOT_DAYS = { 12, 20 }
R.HOTSPOT_HOSTS = 40
R.HOTSPOT_DNA = 2
--- News of governments acting and of first cases is gathered for NEWS_BATCH_DAYS and then said in
--- one line per kind ("France, Spain and 3 more close their borders"), not one line a country.
R.NEWS_BATCH_DAYS = 5

-- The map's red -------------------------------------------------------------------------------------
--- Infected area of a country = tiles * ((infected + dead) / population) ^ AREA_EXP.
R.AREA_EXP = 0.62
--- Dead area = tiles * (dead / population) ^ DEAD_EXP (taken from the oldest infected tiles).
R.DEAD_EXP = 0.6
--- Tile changes per tick over the whole map.
R.TILE_BUDGET = 3000

-- Multiplayer (Data/PlagueModes; 2026-10-30) -------------------------------------------------------
--- A server-run match (Co-op, 1v1) whose players have not picked patient zero after this many ticks
--- starts in a big country of its own choosing (nobody can hold a match in its spawn phase).
R.MP_ZERO_TICKS = 300
--- 1v1, the cure's player: research funds, earned each day (more once research has started, and
--- more as the world fills with the sick), spent on actions on countries (PlagueSim._cure_act).
R.DUEL_FUNDS_START = 5
R.DUEL_FUNDS_DAY = 0.06
R.DUEL_FUNDS_RESEARCH = 0.1
R.DUEL_FUNDS_SICK = 0.18
--- Before research starts the cure's one action is RAISE ALARM (awareness + DUEL_ALERT_AWARE). Once
--- it has started, the cure BUILDS, RoWorld's way (R.BUILDINGS): picked from a build row and placed in
--- a country, one of each kind per country. A cure bubble the cure's player pops speeds the cure by
--- CURE_BUBBLE_CUT and pays DUEL_BUBBLE_FUNDS. (2026-10-30: the cure was too strong; the alarm and the
--- funds are weaker, and closing a country now costs a building.)
R.DUEL_COSTS = { alert = 5 }
R.DUEL_ALERT_AWARE = 0.1
R.DUEL_BUBBLE_FUNDS = 1

--- The cure's buildings, RoWorld's way: placed on any land tile, drawn as a RoWorld structure (struct:
--- Defs.S_* 0 city, 1 port, 2 factory, 3 defense post, 6 artillery) and working on every country in
--- its RANGE (tiles; a country is in range when its centre, the building's own country, or for the
--- control one of its ports / airports, is). One of each kind per country it stands in.
R.BUILDINGS = {
	lab = { cost = 9, struct = 2, range = 70, short = "Lab", name = "Research Lab", icon = "factory", desc = "Research in range runs at full funding, twice as fast" },
	hospital = { cost = 7, struct = 0, range = 55, short = "Hospital", name = "Hospital", icon = "city", desc = "In range twice the sick recover, fewer die" },
	camp = { cost = 10, struct = 3, range = 55, short = "Quarantine", name = "Quarantine Camp", icon = "defense", desc = "The plague spreads slower in range" },
	post = { cost = 8, struct = 6, range = 60, short = "Border", name = "Border Post", icon = "sam", desc = "Shuts the land borders in range" },
	control = { cost = 8, struct = 1, range = 80, short = "Ports", name = "Port & Airport Control", icon = "port", desc = "Shuts the ports and airports in range" },
}
R.BUILD_ORDER = { "lab", "hospital", "camp", "post", "control" }
--- A lab's country researches this much more (on top of full funding).
R.LAB_RESEARCH = 1.0
--- A hospital's country: recoveries x HOSPITAL_RECOVER, deaths x HOSPITAL_DEATH.
R.HOSPITAL_RECOVER = 2.0
R.HOSPITAL_DEATH = 0.6

-- A shared world (Plague Race, team games: Data/PlagueModes; 2026-10-30) ---------------------------
--- Plagues on one world at most (each player or team is one).
R.MAX_PLAGUES = 8
--- A country is held by ONE plague at a time. A plague spreads by itself only into free countries; an
--- enemy's country must be ATTACKED, like RoWorld's: a click costs ATTACK_DNA more than a normal
--- infection and sends ATTACK_SHARE of your bordering country's infected (they leave it: recovered).
--- Across a border the attack starts AT ONCE; with no border a ship carries them, and it starts where
--- the ship lands. While it lasts the country under attack spreads no further (the front decides it).
--- The two fight every tick (PlagueSim._fight): the defenders lose
--- FIGHT_RATE * (ATTACK_BASE + the attacker's infectivity) * attackers a day, the attackers
--- FIGHT_RATE * (ATTACK_BASE + the defender's) * DEFEND_K * defenders a day. Defenders down to
--- CAPTURE_FLOOR of the country's people: taken, the attackers move in (sick, yours), and it can't be
--- attacked again for CAPTURE_SHIELD_DAYS. Attackers gone: beaten back.
R.ATTACK_DNA = 3
R.ATTACK_SHARE = 0.5
R.ATTACK_BASE = 0.4
R.DEFEND_K = 1.15
R.FIGHT_RATE = 0.1
--- The invasion (2026-10-30: RoWorld's front, not an instant take): the attackers' front crosses the
--- country tile by tile while they are stronger (troops x (ATTACK_BASE + infectivity) against the
--- defenders' x DEFEND_K), and is pushed back while they are weaker; the country is taken only when the
--- front has crossed all of it. At full strength a 5000-tile country takes INVADE_DAYS, a bigger one
--- longer (by the square root of its size). Tiles repainted a tick per attack, at most INVADE_PAINT.
R.INVADE_DAYS = 6
R.INVADE_REF_TILES = 5000
R.INVADE_PAINT = 800
R.CAPTURE_SHIELD_DAYS = 20
--- Every plague's patient-zero country can't be attacked for its first START_SHIELD_DAYS.
R.START_SHIELD_DAYS = 30

--- How many of a country's `infected` an attack from it sends.
function R.attack_troops(infected: number): number
	return math.floor(math.max(0, infected) * R.ATTACK_SHARE)
end

return R
