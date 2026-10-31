--!strict
-- RoPlague: every tunable number of the plague simulation (DESIGN.md §3-§4). Rates are per in-game
-- DAY; one day is DAY_TICKS ticks (1 s of play at 1x). Tuned with tools/balance/run.luau.
local R = {}

R.TICK_RATE = 10
R.DAY_TICKS = 10

-- Population -------------------------------------------------------------------------------------
--- Infections per infected host per day in a neutral country, before any trait.
R.BASE_BETA = 0.12
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
R.LAND_K = 3.0
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
R.SHIP_TILES_PER_TICK = 4
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
R.CURE_DAYS = { 260, 170, 125 }
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

-- DNA ----------------------------------------------------------------------------------------------
R.DNA_START = 4
--- Passive DNA per day: base + k_i * sqrt(infected share) + k_d * sqrt(dead share).
R.DNA_BASE = 0.06
R.DNA_INFECTED = 0.2
R.DNA_DEAD = 0.12
--- First infection of a country: this much at once, plus a bubble.
R.DNA_NEW_COUNTRY = 0
R.DNA_FIRST_DEATH = 0
--- Bubbles: one every BUBBLE_DAYS (random in range) in a random infected country; it lives
--- BUBBLE_LIFE ticks. Cure bubbles appear in funding countries once research starts.
R.BUBBLE_DAYS = { 6, 10 }
R.BUBBLE_VALUE = { 1, 2 }
R.BUBBLE_LIFE = 140
R.NEW_COUNTRY_BUBBLE = 2
R.CURE_BUBBLE_DAYS = { 10, 18 }
R.CURE_BUBBLE_CUT = 0.004
R.CURE_BUBBLE_DNA = 1

-- The map's red -------------------------------------------------------------------------------------
--- Infected area of a country = tiles * ((infected + dead) / population) ^ AREA_EXP.
R.AREA_EXP = 0.35
--- Dead area = tiles * (dead / population) ^ DEAD_EXP (taken from the oldest infected tiles).
R.DEAD_EXP = 0.6
--- Tile changes per tick over the whole map.
R.TILE_BUDGET = 3000

return R
