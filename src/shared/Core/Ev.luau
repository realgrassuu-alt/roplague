--!strict
-- Port of scripts/core/ev.gd: event type ids carried in the "ev" array of a Sim delta. Each event
-- is a 1-based Luau array whose first element is one of these ids, followed by the arguments in
-- GDScript order (DESIGN.md §4): { Ev.OWNER_ADD, id, name, color, kind, flags }. Values are part
-- of the network protocol, so never renumber them.
local Ev = {}

Ev.OWNER_ADD = 0 -- id, name, color, kind, flags
Ev.OWNER_OUT = 1 -- id, killer_id
Ev.PHASE = 2 -- phase, ticks_left
Ev.SPAWNED = 3 -- id, tile
Ev.STRUCT_ADD = 4 -- sid, kind, owner, tile
Ev.STRUCT_OWNER = 5 -- sid, new_owner
Ev.STRUCT_DEL = 6 -- sid
Ev.ROAD_ADD = 7 -- rid, sid_a, sid_b, tiles  (a railroad: its tile path from a's end to b's end)
Ev.ROAD_DEL = 8 -- rid (, sid_a, sid_b)
Ev.UNIT_ADD = 9 -- uid, kind, owner, path, start_tick, ticks_per_tile_x100, troops
Ev.UNIT_MOVE = 10 -- uid, tile
Ev.UNIT_DEL = 11 -- uid, reason
Ev.NUKE = 12 -- uid, kind, owner, from_tile, to_tile, launch_tick, flight_ticks
Ev.BOOM = 13 -- uid, kind, tile, radius_tiles, owner
Ev.ATTACK = 14 -- aid, attacker, target, troops, anchor_tile, retreating  (re-sent to update)
Ev.ATTACK_END = 15 -- aid
Ev.ALLY_REQ = 16 -- from, to, created_tick
Ev.ALLY = 17 -- a, b, expires_at
Ev.ALLY_END = 18 -- a, b, traitor_id, expired
Ev.MSG = 19 -- to_owner (-1 all), category, text
Ev.GAME_OVER = 20 -- winner_id, reason
Ev.ALLY_REQ_END = 21 -- from, to   (request answered or expired)
Ev.TRAITOR = 22 -- id, until_tick
Ev.STRUCT_LEVEL = 23 -- sid, level, active_tick  (upgrade, or construction start: active from active_tick)
Ev.SHELL = 24 -- shell_id, shooter_kind (0 warship, 1 defense post), shooter_id (uid / sid), from_tile, target_uid, fire_tick, impact_tick, damage
Ev.UNIT_HP = 25 -- uid, hp, max_hp  (at most once per unit per tick)
Ev.UNIT_VET = 26 -- uid, veterancy_level
Ev.UNIT_STATE = 27 -- uid, state (0 patrolling, 1 retreating, 2 docked / repairing), patrol_tile
Ev.UNIT_PATH = 28 -- uid, path, start_tick, ticks_per_tile_x100  (a warship changed course)
Ev.SAM_LAUNCH = 29 -- sam_sid, nuke_uid, fire_tick, intercept_tick, will_hit  (BOOM radius 0 follows at intercept_tick)
Ev.ALLY_EXT = 30 -- a, b, expires_at, asked  (renewal asked: bit 1 by min(a, b), bit 2 by max(a, b); a renewal resets it to 0)
Ev.CONQUEST = 31 -- conqueror, conquered, gold  (the gold `conqueror` took)
Ev.STRUCT_SHOTS = 32 -- sid, ticks  (SAM / silo: launch or upgrade ticks of its missiles still reloading
--   — each reloads for Rules.SAM / SILO_COOLDOWN_TICKS)

Ev.REINFORCE = 33 -- id, troops, ready_tick  (Reinforcements arrived; the next call is ready at ready_tick)

Ev.BONUS = 34 -- owner, tile, gold  (gold `owner` earned at `tile`, a train's
--   stop at a station. Only for a person, and sent to that person alone)

-- RoPlague (Core/SimPlague)
Ev.EVOLVE = 35 -- owner, trait id  (an evolution bought, or a strain's starting one)
Ev.CURE = 36 -- progress x 10000, research on (1 / 0), per-second rate x 1e7  (solo, once a second)

-- RoPlague solo (Core/Plague/PlagueSim)
Ev.P_INFECTED = 37 -- country, tile  (the first infection of a country)
Ev.P_CLOSE = 38 -- country, closed bits (PlagueRules.C_AIR / C_PORT / C_BORDER / C_QUARANTINE / C_COLLAPSE)
Ev.P_BUBBLE = 39 -- id, kind (0 DNA, 1 cure), country, tile, value, expire_tick
Ev.P_BUBBLE_END = 40 -- id, popped (1 / 0)
Ev.P_TRAIT = 41 -- trait id, owned (1 / 0), how (0 bought, 1 mutated, 2 devolved)
Ev.P_FLIGHT = 42 -- uid, from_tile, to_tile, launch_tick, flight_ticks, infected (1 / 0), from_country
Ev.P_FLIGHT_END = 43 -- uid, seeded (1 / 0)
Ev.P_DNA = 44 -- amount, tile (-1: none), reason (0 passive, 1 bubble, 2 new country, 3 first death, 4 cure bubble)
Ev.P_ABILITY = 45 -- key, tile, ready_tick

-- RoPlague multiplayer: country, the plague that took it (owner id), the plague it was taken from
Ev.P_CAPTURE = 46

--- Number of event ids (ids are 0..COUNT-1).
Ev.COUNT = 47

return Ev
