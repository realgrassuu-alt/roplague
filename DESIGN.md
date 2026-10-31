# DESIGN — RoPlague (v3: RoWorld, with a plague you click across the real world)

**RoPlague is RoWorld with a plague game in its solo mode.** Everything RoWorld ships stays: the title,
the map renderer, the glass UI, the shop with crates, the 399 R$ subscription ("General"), the Arsenal,
the flag shop, the starter pack, the leaderboard, the menus, multiplayer.

The user's direction, in order (2026-10-28):
1. "the entire game is just RoWorld with this plague stuff" (v1, a separate Plague Inc-style game, was
   rejected; archived in `archive/plague_v1/`).
2. "don't remove anything" (v2 had hidden RoWorld content).
3. "the player should not have a land, he should just destroy the world / control it", "click a
   country to spread to it but you don't take its land", "if you're near it you infect it, if not you
   travel by boat", "only real countries like Morocco", "Antarctica as 3 countries", "no airport /
   dock clutter, no flying planes", "the red overlay looks weird", "a clearer EVOLVE button and skill
   tree", "starting a game is confusing, 4 strains", "rename the virus with a 19 Robux gamepass",
   "draw icons for the viruses and stuff". That is v3.

## The solo game (v3)
- **Map**: RoWorld's World map, coloured as 174 real countries (Natural Earth, public domain;
  `tools/maps/make_countries.py` → `Data/Maps/WorldCountries`). Micro-territories under 50,000 people
  are dropped. Antarctica is West Antarctica / Antarctica / East Antarctica. 7.66 billion people.
- **The player has no land and no troops.** The plague is an owner with zero tiles; countries keep
  their own colours. An infected country's tiles take a crisp per-tile tint toward the plague's colour,
  dead tiles go dark (`Map/MapSurface.plague_mix`). Under each country's name: its infected people
  (nothing while it has none).
- **The outbreak** (`R.ZERO_OUTBREAK`, `R.ZERO_GROWTH`): in patient zero's country the plague grows at
  least 0.6 a day and nobody recovers until 10% of its people are infected (India in about 30 days, a
  small country much sooner), then the usual rules. So the first minute visibly goes somewhere: 10% of the
  people is about 24% of the country's tiles.
- **Start**: PLAY SOLO starts at once (no strain window; the plague is a Bacterium). Click any country
  to plant patient zero. A new player's first match is the same on Casual, with the step-by-step tutorial below.
- **Spread** (`Core/Plague/Reach`, `PlagueSim._infect_click` / `_walk`): only a country that shares a
  land border with an infected one can be infected by land; a click sends an **infected traveller**
  who walks from inside the infected country to the border (`Map/CarrierLayer`, 2.5–6 s) and plants it
  there (1 DNA, +2 if borders are closed). A coastal country within sailing range of an infected coast
  (`R.SEA_RANGE` 170 tiles, +800 per point of water traits) gets an **infected ship** (2 DNA; ships
  sail 1.2 tiles a tick). Anything else is out of reach, and the hover tooltip / card say why.
  Border spread on its own is slow (`LAND_K` 0.5) and so is the spread inside a country
  (`BASE_BETA` 0.09), so clicking and evolving matter. Air / water traits let it turn up by itself in
  far countries (`PlagueSim._jumps`, nothing drawn).
- **DNA bubbles** (`Map/BubbleLayer`): glowing DNA bubbles with a pulsing ring float up over infected
  places every 4-8 days (and over each newly reached country); a click pops it (flash, shock ring,
  particles) and a dark "+2 [DNA]" pill springs up ABOVE the burst (`BubbleLayer.pay`; DNA from a new
  country uses the same pill). It gives 1–2 DNA and plants 20 more infected on that spot. Blue cure
  bubbles slow the cure.
- **Where a bubble sits** (`BubbleLayer`): bigger (58 px base), glossy (gradient core, white rim,
  highlight, drop shadow), and never on a country's name or the line under it: it is pushed above any
  name plate in the way (NameLayer's `p.rect`), with a thin stem down to a pin on the spot it is for.
- **Hotspots** (something to do, `R.HOTSPOT_*`): every 8-14 days a red spinning bubble floats over one
  uninfected country next to the plague; popping it infects that country at once (30 people) and pays
  1 DNA. Missed, it goes. One at a time.
- **The map**: an infected country keeps its colour; its infected tiles are flushed crimson in soft
  patches (`MapSurface.plague_mix`, smooth value noise over a few tiles), their number following
  (infected + dead) / people ^ 0.62, so 3 infected are 1 tile, not a splash. The infected tiles grow as
  one solid patch with a wandering edge (`PlagueSim._next_tile`: of 6 front tiles, the one with the most
  infected neighbours plus a noise term wins), not coral with holes. Dead land darkens. A country's first case pops a double red wave
  (`FxLayer.infect`). Under each name: `UNINFECTED`, `12.3K INFECTED` (and `4.5M DEAD` under it once the
  plague has killed there), `4.5M DEAD` alone where it burned out, or `WIPED OUT` (`NameLayer`).
- **Tutorial** (`UI/Plague/PlagueTutorial`, a new player's first match, Casual): RoWorld's card and tap
  mark; 8 short steps (patient zero in a good country: crowded, poor, many neighbours, India is marked;
  pop a bubble; infect a neighbour; open EVOLVE; buy Water Supply, picked for them; close; send an
  infected ship overseas; the cure bar). While a neighbour cannot be reached yet the card says why and
  to pop bubbles and evolve meanwhile; on the land step a red hotspot, if there is one, is pointed at
  instead (never on the ship step: it would pass it without a ship). Nothing is drawn over the game
  menu, help or shop. Evolve and Rename pause the game.
- **Evolve** opens on the Transmission tab. Every hex wears its own colour (`NODE_COLORS`: one per
  carrier, body system or resistance), so a tree is not one block of orange; a double press on a hex
  evolves it.
- **Not infected yet** (`UI/Plague/WorldList`, the HUD's `N LEFT` button): every country the plague has
  not reached, the reachable ones first (BORDER, then SHIP), the biggest first; a press flies there and
  opens its card. It does not re-sort under the pointer.
- **End screen**: people killed, the most infected at once (`peak`, from the sim), countries reached,
  evolutions, match time (RoWorld's land / troops cards stay for war mode).
- **Gates** (so evolving and DNA matter): a country needs `R.TRAVEL_MIN` (150) infected before a
  traveller or a ship can leave it; ships need a water evolution (or the Sea Legs perk); every
  `INFECT_COST_STEP` (25) infected countries a click costs 1 DNA more. The hover / card say which gate
  is in the way.
- **Evolve** (`Data/Traits`, `UI/Plague/EvolveScreen`): a short window (the body is `VIEW_H` 330 px:
  the board scrolls inside it, scrollbars only when it overflows, centred while smaller); the plague's
  three meters sit in its header; one step past the revealed hexes the next ones show as dark "?" hexes
  (LOCKED) with faint links, so the board has a shape. A honeycomb skill tree per tab that opens up as
  you evolve (a hex shows once it is owned, needs nothing, or something it needs is owned; new ones pop
  in; "N MORE TO DISCOVER" under the tree; the detail panel says what it UNLOCKS NEXT; the tree area
  clips its glow so it never reaches the tabs) (hexes drawn by
  `tools/assets/make_hex.py`, icon + name + DNA price / OWNED / LOCKED, links that light up, affordable
  hexes glowing, hexes popping in), and the picked evolution big on the right in RoWorld's Arsenal style (animated icon on its tree's colour, chips, plain effects, what it needs, one green EVOLVE
  button with its price). Buying flashes, kicks the icon, throws sparks, counts the DNA down and pulses
  what it opened. The HUD's EVOLVE shows how many are affordable; the game pauses while it is open.
- **Shop** (RoWorld's Arsenal, now "PLAGUE SHOP"; `Data/Arsenal`): permanent perks bought with Stars,
  applied to every solo match through `config.perks` (`R.PERK_*`): Head Start (+6 DNA, 3K), Super
  Spreader (250 at start, 8K), Bubble Magnet (+45% bubbles, 6K), Sea Legs (ships at once, +60 range,
  12K), Gene Bank (-15% evolve prices, 18K), Slow Science (cure +15% work, 25K), Mutagen (free
  Transmission evolution, 35K), and 2x Stars. Plague matches pay Stars (`Core/Plague/PlagueStars`,
  the same report the server already pays for RoWorld matches: about 600-1,500 a match). Each perk plays its own animated scene in the shop (`UI/Plague/PerkDemos` on RoWorld's
  `ArsenalDemo` stage), over a LIVE map: 8 frames of a real piece of the world in the game's colours whose
  infection moves with what the perk does (`tools/assets/make_perk_maps.py` -> two 1024 atlases,
  `Assets/PerkMaps` with the points each scene needs: patient zero, the two coasts, the bubble spots);
  each scene has ONE big caption along the top saying what the perk does
  (`PerkDemos.CAPTIONS`, e.g. "START WITH 250 SICK") and the picture shows only that. Their Robux
  products are id 0 (not created), so they are Stars-only until they are made. RoWorld's war items are
  in `archive/plague_v1/Arsenal_roworld_items.luau`; the starter pack now holds Super Spreader + Sea
  Legs + 2x Stars; its tiles are a dark card with the item's icon on a round badge of its colour, and
  under each "WORTH (Robux) N" in green (the item's own live price).
- **The world fights back**: awareness → cure research (top pill), governments close airports, ports
  and borders, quarantine, collapse. Win = humanity extinct (`OVER_EXTINCT`); lose = cured
  (`OVER_CURED`) or burned out (`OVER_BURNOUT`).
- **Country card**: name, people, healthy / infected / dead, then three details: the climate (Hot in
  red, Cold in light blue, Normal in the card's colour) and under it wealth and crowding, then what is
  closed and the INFECT button.
- **The traveller** (`Map/CarrierLayer`, 2026-10-29 v2: "make it like RoWorld, simple"): drawn the way
  RoWorld draws its ships. A 16 x 16 pixel sprite (`tools/assets/make_pixel_walker.py` -> `walker_pixel`:
  body white, rim grey, two frames) tinted in the plague's infection colour, a ship's size (13 full-size
  tiles, at least 20 px), walking the straight line to the border with a wake behind it (the ship's: the
  plague's colour at 0.588). No shadow, puffs, route dots or target ring any more. The plague's ships wear
  its infection colour too (`Strains.tint(Strains.worn(state))`, read by UnitLayer and CarrierLayer).
- **Fewer bubbles, the same reward** (2026-10-29): half as many timed bubbles worth twice as much
  (`BUBBLE_DAYS` 8-16, value 2-4; cure bubbles 20-36 days, cut 0.008, 2 DNA; hotspots 12-20 days, 40
  people, 2 DNA), and never more than 2 DNA bubbles / 1 cure bubble at once: one over the cap is ADDED to
  the newest live one (`PlagueSim._add_bubble`: value, plants and life add up; the same id is sent again
  and BubbleLayer updates its "+N" and punches it). Nothing is lost by the cap.
- **Big top lines** (`UI/Plague/TopNotice`, under the cure pill): "+3 DNA" in white with a thick black
  outline whenever the plague's DNA goes up (gains within 2 s of a line's first add to it), and the cure's
  milestones ("THE CURE RACE HAS STARTED", "CURE RESEARCH 25% / 50% / 75% / 90% DONE").
- **Quieter news**: governments acting and first cases are gathered for 5 days and said in one line a
  kind ("France, Spain and 3 more close their borders", `PlagueSim._queue_news` / `_flush_news`); the
  feed keeps 3 lines at most in a plague match (`EventFeed.max_toasts`).
- **Crates hold colours** (2026-10-29): the crate catalog (`Cosmetics.all`) is 20 crate-only infection
  colours (`Strains` entries with `crate = true`, items "color_<key>": 8 common, 6 rare, 4 epic, 2
  legendary), never a duplicate, the first one put on. RoWorld's skins and flags are still items
  (`Cosmetics.world`: saves keep them, multiplayer bots and AI nations wear them) but in no crate. The
  Locker's first tab is COLOURS: every colour, the shop's and the crates'; press an owned one to wear it
  ("Crimson", the free default, is the "None" card); a locked one says COLOUR SHOP or IN A CRATE. The
  Skins / Flags tabs show only while the player owns some. The crate opens as soon as its credit arrives.
- **The colour shop** (RoWorld's flag shop, 2026-10-29): a plague has no flag, so the shop sells
  INFECTION COLOURS (`Data/Strains`: 19 colours, 15 in the daily pool, 3 a day, plus the Halloween set of
  4 with a 199 R$ bundle; rare 49 / epic 99 / legendary 149). Two-tone colours swirl across the map's
  patches (`a` -> `b` by the noise), Rainbow Plague turns them into hue. Bought or worn, a colour goes in
  the inventory's `color` slot (server/Purchases), reaches GameState cosmetics through
  `Session._apply_own_cosmetics`, and `MapSurface._read_strain` repaints every infected tile with it.
  The machinery (rotation, sets, bundles, receipts "shopflag:<key>") is RoWorld's unchanged; the old
  `Assets/ShopFlags` (their art and products) is emptied.
- **Rename** (`UI/Plague/RenameWindow`, `server/PlagueRename`, `Data/Gamepasses.rename`, 19 R$): the
  pencil next to the plague's name. The name is checked (3–22 letters, digits, spaces, `-`, `'`) and
  put through Roblox's text filter on the server, then applied to the running match and kept in
  settings. While the pass id is 0 it counts as owned in Studio only.
- **Sound effects** (2026-10-31): `Assets/Audio` holds 46 public Roblox Creator Store sounds, played by
  asset id (Creator Store audio is free to use in Roblox experiences; none is re-uploaded), each over the
  region that was auditioned and at its own `gain`. `AudioExtra` and `AudioUI` are empty: none of
  RoWorld's sounds play. The five plague sounds below and the war-mode sounds RoPlague never plays come
  from `Assets/AudioPlague`, which is also every store sound's stand-in while it loads.
- **Sounds** (`Assets/AudioPlague`): 68 effects of our own, synthesised by
  `tools/assets/make_plague_sfx.py` (no samples), packed into ONE audio sprite (OGG, 136 s) and uploaded by
  `tools/assets/upload_plague_sfx.py` (Open Cloud, the key from talon-spoofer's keyring). AudioDirector
  takes AudioPlague over every other table with no stand-in; `Audio`, `AudioExtra`, `AudioUI` and
  `Soundtrack` were emptied at the time (later refilled: see above and Assets/Soundtrack).
  Plague sounds: `plague_pop` (DNA bubble), `plague_hotspot`, `plague_cure`, `plague_infect` (a new
  country), `plague_send` (a traveller), `plague_evolve`. The music is Rodrigo Flores' CC BY 4.0
  tracks, uploaded by us (`Assets/Soundtrack`).
- **Icons**: our own, drawn by `tools/assets/make_plague_icons.py` (virus, dna, evolve, cure, pencil,
  infect, transmission, symptoms, abilities, death, world), ids in `Assets/PlagueIcons`.

## Multiplayer (2026-10-30)
The title's three cards (where RoWorld's public matches were; `ServerMain.WAR_PUBLIC = false` keeps the
war lobbies off) are RoPlague's modes (`Data/PlagueModes`), in this order: **1V1** (Plague vs Cure, the
map is always the World), **PLAGUE RACE** (always the World, free for all) and **TEAM PLAGUE** (Duos / Trios / Quads /
4 Teams, map and format rotate). Press one, `server/PlagueMatch` matchmakes and teleports to the ONLINE
place (`Data/Places`). On the online place the title shows only a "joining your match" panel (no dock,
no PLAY SOLO).
- **Rotation**: every `PlagueModes.ROTATE_S` (300 s, `os.time`, the same on every server)
  `PlagueModes.variant(mode, now)` moves the team game's map + format on (1v1 and the race stay on the
  World) (maps:
  World + the five continents, each with a country layer, `tools/maps/make_countries.py --map <id>
  --pop-share cities`). The cards show the variant's map thumbnail (Assets/MapThumbs) and "Map · format".
  A line entry carries its variant id (`teams:asia:duos`) and only meets others on the same one; a group
  still waiting when the rotation moves follows it.
- **Matchmaking**: a MemoryStore line (`rp_mm_line_v1`, a group per entry: a party goes together). Each
  second ONE lobby server with players waiting takes a short lock (`rp_mm_go_v1` `_lock`), forms matches
  (`PlagueMatch.form`), reserves a server of the online place and leaves each group's `{code, room}` under
  its key; each group's own server teleports it with `TeleportData = {rp = room}`. Studio has no
  teleports: the match plays on the same server, a lone player is matched alone after 2 s, and a race or
  team game with one player gets an unplayed "Rival Plague" to try the shared world against.
- **1v1**: pressing the card first asks VIRUS or CURE (`TitleScreen._build_side_pick`); the line pairs a
  virus with a cure, never two of a side. A party of two plays each other (the presser's side, the friend
  the other). A party bigger than a mode allows is refused with `PlagueMatch.TOO_MANY` ("You have too many
  party members for this mode."). The cure's player is its own owner (`cure_pid`), with research FUNDS
  (`R.DUEL_*`). Before research starts its one action is RAISE ALARM; once it has started, the bar's
  RAISE ALARM button gives way to five building slots, RoWorld's build row (`R.BUILDINGS`: Research
  Lab, Hospital, Quarantine Camp, Border Post, Port & Airport Control). Pick a slot, the building's range
  follows the cursor (and the cure's other buildings' ranges show), click the tile it goes on. It is a
  RoWorld structure of the cure's on the map (`Ev.STRUCT_ADD`) and works on every country in its range
  (`PlagueSim._in_range`: a country's centre, the building's own country, or for the control one of its
  ports / airports). One of each kind per country it stands in. The cure also pops the cure bubbles.
  Balance (2026-10-30, "the cure is too strong"): weaker alarm and funds, and closing a country costs a
  building; `tools/balance/duel.luau` (the plague bot against a greedy scripted cure) ends with the
  cure at 83-99% and the plague winning. Auto Pop Bubbles works in 1v1 too.
- **Plague Race and team games are ONE SHARED WORLD on the server** (`PlagueSim` with `config.plagues`):
  each player (race) or team (teams) is a plague, owner `C + k`. Its own numbers (DNA, evolutions, effects,
  bubbles, mutation, kills: `PL_FIELDS`) live in `self.P[k]`; `PlagueSim._use(k)` loads plague k onto
  `self`, so the single-plague code runs for each in turn and solo is the same code with K = 1 (verified
  bit-identical on the balance run). A country is HELD by one plague (`holder[c]`, cleared when nobody is
  sick there); a plague spreads by itself (land, ships, jumps, hotspots) only into free countries. An
  enemy's country is ATTACKED, RoWorld's way: a click costs `R.ATTACK_DNA` more than an infection and
  sends `ATTACK_SHARE` (half) of your bordering country's infected. Across a border the attack starts AT
  ONCE (no traveller); with no border a ship carries the troops and the attack starts where it lands. It
  is a RoWorld attack on the wire (`Ev.ATTACK`, with the country as its 7th field), so RoWorld's attacks
  panel lists it (yours and the ones on you, with their counts, Retreat) and its front layer puts the
  troop number on the border (blue yours, red on you). `PlagueSim._fight` runs it every tick
  (`FIGHT_RATE`, Lanchester-style: each side loses in proportion to the other's numbers and
  infectivity, the defender times `DEFEND_K`); the country under attack spreads no further meanwhile.
  It is an INVASION, not a take: the attackers' front crosses the country tile by tile outward from
  where it began (`_front_order`, painted in the attacker's colour, the troop count riding it) while
  they are the stronger, and is pushed back while they are the weaker (`R.INVADE_*`: a 5000-tile
  country takes 6 days at full strength, bigger ones longer). The country is taken only once the front
  has crossed it; the attackers move in, shielded `CAPTURE_SHIELD_DAYS`. Attackers gone: beaten back,
  and the land flips back. Each plague picks its own patient zero (not in a
  taken country); the match starts when all are placed, or 30 s after the first player joins the rest
  are placed in the biggest free countries away from the others; every start country is shielded
  `START_SHIELD_DAYS` (30). A held country wears its player's head shot by its name (NameLayer). The cure is shared (the mean resistance of the plagues still alive). The end: the last plague
  standing (`Defs.OVER_LAST`), humanity gone (the deadliest wins), cured, or every plague out.
- **Client**: `GameState.plague.plagues` mirrors every plague's row and the local player's plague is
  copied onto the top level (`_local_plague`), so the HUD reads its own plague as in solo; country rows
  carry `holder`; events carry their plague (DNA / trait / bubble events of other plagues are dropped).
  Map: tiles carry their plague in flag bits 3..5; each plague wears its owner's strain, and
  `Strains.distinct` turns it round the colour wheel where it would look like an earlier plague's (three
  players in Crimson: crimson, orange-red, magenta). Every held country's border is drawn in its plague's
  colour (`MapSurface.set_holders`). The country card and tooltip say who holds a country and offer
  ATTACK with its DNA and win chance; the board (`RaceBoard.show_world`) lists the plagues, their colour
  and countries held.
- Leaving a match (or its end) teleports back to the LOBBY place.
- **Not testable in Studio**: the teleports themselves, two real players, and the online place's boot.
  Tests: `tests/plague_mp.luau` (co-op / duel rules, the shared world: holders, attacks, shields,
  bubbles, the last plague standing; the wire), `tests/plague_match.luau` (rotation, forming matches,
  strict 1v1 sides, parties, teams, rooms), `tests/continent_countries.luau` (the continent layers).

## Where it plugs in
- Sim: `Core/Plague/*` (PlagueSim, PlagueRules, Countries, Reach, PlagueBot). Session runs PlagueSim for
  solo and for the title backdrop (the bot plays it).
- UI: `UI/Plague/PlagueLink` is called from UIRoot's hook points (search "PlagueLink"): map hover and
  clicks, the war HUD hidden in a plague match, the plague HUD (PlagueHud, CureBar, CountryCard), the
  Evolve and Rename windows, the first-match guide.
- Multiplayer stays RoWorld's war mode (its own Evolve layer: `Core/SimPlague`, `Data/WarTraits`).

## Look and feel (2026-10-28, later)
- Shop scenes and the Evolve preview play over pictures of the game's own world with the plague on it
  (`tools/assets/make_world_scenes.py`: the real country grid, the game's colours, the same soft crimson
  patches as the map with ragged fronts; ids
  `scene_*` in `Assets/PlagueIcons`), drifting slowly under a tinted wash.
- EVOLVE carries a red badge with a white rim and, centred in it, the number of evolutions the DNA buys.
- The HUD's numbers count to their values (`PUI.counter`); the infectivity / severity / lethality
  meters live only in the Evolve window. The line under a country's name has a thick dark outline (no
  country colour shows through the gaps of an 8) and hides when it would be tiny.
- The title's right-hand column (shop, crates, flag shop, starter pack, General) re-stacks when a
  button appears late (the starter pack's loads after the layout), so none is left under another.
- `tools/balance/tiles_png.luau [day]` plays the bot and writes the infected tiles of a crop as a PPM,
  to check how countries fill in.
- Messages are short and say what to do ("India needs 150 infected to spread (40 now)"); the same note
  is not repeated within 4 s (`PlagueLink.say_once`).
- Early game: patient zero brings 4 infected, the plague starts with 6 DNA, the first bubble comes on
  day 1, travel needs 150 infected.

## Balance (tools/balance/run.luau)
Infected people recover (`R.RECOVER` 0.042/day) and the base infectivity (`BASE_BETA` 0.052) is only a
little above it, so a plague that never evolves crawls: the "none" bot ends 12 minutes at under 1% of
the world. Evolutions' infectivity counts `TRAIT_BETA` (2.6) times. Normal, "balanced" bot (2026-10-29,
after hotspots and the compact tile growth): 3/3 wins, about 13 minutes, 3.4 ms a tick; random play on
Casual 4/4. Cure days: 360 / 175 / 150.
2026-10-30 ("it feels a little slow at the end"): the last 1% of humanity took about 200 days, mostly
small countries reached late. `R.END_*`: once 85% of the world is dead every infected country falls
apart (no recovery, survivors catch it at 30%/day, the sick die at 20%/day, the last ~2,000 die), and
untouched places catch it at 20% a day. The 99%-to-100% tail is about 21 days now; balanced 5/5 wins,
mean 8.7 minutes (was 12.5); the early and middle game are unchanged.

## Open items
- Tests that hard-code RoWorld's old shop items now fail by design: `offers` (5), `purchases` (the
  starter pack's Mega Nuke lines) and `uiscreens_logic` (2 war radial checks). Multiplayer war mode has no
  Arsenal units to unlock any more.
- Products are ours now (2026-10-29, `tools/assets/create_products.py`, ids in
  `build/products_manifest.json`, store icons by `make_product_icons.py` put on with `set_product_icons.py`):
  the 7 perks, 2x Stars, the starter pack, 4 crate offers, Take Over, 19 colours, the Halloween bundle,
  the Rename gamepass (2058707947) and the Auto Pop Bubbles gamepass (2061497487, 99 Robux, 2026-10-30).
  RoWorld's war-weapon products are not sold any more (id 0).
- **Auto Pop Bubbles** (Data/Arsenal `auto_pop`, `pass = "auto_pop"`): the shop's only gamepass item. The
  Arsenal prompts the gamepass; ServerMain grants the unlock (receipt "pass:auto_pop", so once) to an owner
  on join and right after the purchase; PlagueLink then pops every bubble (DNA, cure, hotspot) 0.5 s of real
  time after it shows, the same way a press does. Its shop scene is PerkDemos `auto_pop`. The 2x Stars scene
  is on our live map now (the war map image under it was the original developer's and never loaded).
- The "RoPlague General" subscription has no id (the old one was the original developer's): create it
  on the dashboard and put its "EXP-..." id in `Data/Subscription`; until then its card is hidden.
- Studio can test purchases now: with "Studio access to API services" off the purchase store's calls
  are refused, so ServerMain probes it and falls back to a session store (Studio only; live servers
  unchanged). Roblox's "bought" sheet must be closed with OK before PromptProductPurchaseFinished fires.
  Verified in Studio 2026-10-29: first crate (opened into a colour), Blood Moon, Head Start, the starter
  pack, renaming. `tests/roplague_products.luau` grants every product; `tools/assets/check_products.py`
  checks all 35 on Roblox (for sale, price, icon). The Rename pass reads as owned for its creator.
- `Assets/MapFx` is our upload of `make_map_fx.py`'s atlas (112832498438155); the original developer's
  was refused in our experience.
- RoWorld's products, subscription and flag shop ids are the original developer's: they must be
  recreated before publishing. 
- The experience must have Game Settings > Security > "Allow Mesh / Image APIs" on (the map is an
  EditableImage; without it the map is Roblox's magenta checkerboard and MapSurface puts a note on it).
  It was switched on for universe 10773573507 on 2026-10-29 (`isMeshTextureApiAccessAllowed`).
- `HelpOverlay.SOURCE_REPO` points at our public repo, realgrassuu-alt/roplague (AGPL).
- Hover was only seen with Studio's virtual mouse; check it on a real mouse and on touch.
