--!strict
-- RoPlague: the evolution skill tree. Bought with DNA (RoWorld's gold) and applied by Core/SimPlague to
-- the owner who evolves (any human player: solo and multiplayer). Three branches, each node joined to
-- the ones it needs. Shared by the Sim (effects, rules) and the Evolve screen (names, layout).
--
-- A trait: {id, tree, name, desc, cost, req, req_n, col, row, fx}
--   cost   DNA (gold)
--   req    ids it can be bought after: nil = a root; with req_n = k it needs k of them, else any one
--   col/row  its cell on the tree's grid (the Evolve screen draws links between req and trait)
--   fx     effects, summed over owned traits (Traits.effects):
--     grow    infection rate: troop growth +share
--     cap     host capacity: max troops +share
--     loss    virulence: troops lost infecting a nation -share
--     nloss   troops lost infecting unclaimed land -share
--     speed   spreading speed: time per tile -share
--     hill    highland costs -share          mount  mountain costs -share
--     post    Defense Posts' extra cost -share
--     gold    DNA income +share
--     boat    transports sail faster (time per tile -share);  boats  more transports at sea (+n)
--     leth    sickness: every bordering nation loses this share of its troops each second
--     panic   bordering nations regrow troops this share slower
--     resist  the cure needs 1 + resist times the work
local Traits = {}

Traits.TREES = { "transmission", "symptoms", "abilities" }
Traits.TREE_NAMES = { transmission = "Transmission", symptoms = "Symptoms", abilities = "Abilities" }

Traits.list = {
	-- Transmission: spread faster, further, over water ---------------------------------------------
	{ id = "cough", tree = "transmission", name = "Coughing", desc = "Spreads in every crowded room. Your infected grow faster.",
		cost = 30000, col = 1, row = 1, fx = { grow = 0.10 } },
	{ id = "sneeze", tree = "transmission", name = "Sneezing", desc = "A spray of infection. Your infected grow much faster.",
		cost = 110000, req = { "cough" }, col = 1, row = 2, fx = { grow = 0.15 } },
	{ id = "airborne", tree = "transmission", name = "Airborne", desc = "Hangs in the air for hours. Faster growth and faster spreading.",
		cost = 420000, req = { "sneeze" }, col = 1, row = 3, fx = { grow = 0.20, speed = 0.12 } },
	{ id = "spores", tree = "transmission", name = "Hardy Spores", desc = "Survives outside a host. Unclaimed land costs fewer infected.",
		cost = 40000, col = 2, row = 1, fx = { nloss = 0.20 } },
	{ id = "rodents", tree = "transmission", name = "Rat Carriers", desc = "Rats carry it into every town. Cheaper and faster on unclaimed land.",
		cost = 160000, req = { "spores" }, col = 2, row = 2, fx = { nloss = 0.25, speed = 0.08 } },
	{ id = "water", tree = "transmission", name = "Waterborne", desc = "Lives in ship tanks. Your transports sail faster.",
		cost = 60000, col = 3, row = 1, fx = { boat = 0.25 } },
	{ id = "ballast", tree = "transmission", name = "Ballast Water", desc = "Every ship carries it. Faster transports, one more at sea.",
		cost = 320000, req = { "water" }, col = 3, row = 2, fx = { boat = 0.25, boats = 1 } },
	{ id = "pandemic", tree = "transmission", name = "Pandemic", desc = "Nothing stops it. Much faster growth and more hosts.",
		cost = 1200000, req = { "airborne", "rodents", "ballast" }, req_n = 2, col = 2, row = 4, fx = { grow = 0.25, cap = 0.15, speed = 0.10 } },

	-- Symptoms: break nations ----------------------------------------------------------------------
	{ id = "fever", tree = "symptoms", name = "Fever", desc = "Hosts burn up. Infecting a nation costs fewer infected.",
		cost = 50000, col = 1, row = 1, fx = { loss = 0.10 } },
	{ id = "vomit", tree = "symptoms", name = "Vomiting", desc = "Messy and contagious. Nations fall faster.",
		cost = 260000, req = { "fever" }, col = 1, row = 2, fx = { loss = 0.15 } },
	{ id = "bleeding", tree = "symptoms", name = "Haemorrhage", desc = "Internal bleeding. Nations fall much faster, and bleed troops.",
		cost = 620000, req = { "vomit" }, col = 1, row = 3, fx = { loss = 0.18, leth = 0.002 } },
	{ id = "nausea", tree = "symptoms", name = "Nausea", desc = "Sickness crosses your borders. Bordering nations slowly lose troops.",
		cost = 80000, col = 2, row = 1, fx = { leth = 0.002 } },
	{ id = "necrosis", tree = "symptoms", name = "Necrosis", desc = "Flesh rots. Bordering nations lose troops faster.",
		cost = 460000, req = { "nausea" }, col = 2, row = 2, fx = { leth = 0.004 } },
	{ id = "insanity", tree = "symptoms", name = "Insanity", desc = "Panic everywhere. Bordering nations regrow troops slower.",
		cost = 350000, req = { "nausea" }, col = 3, row = 2, fx = { panic = 0.3 } },
	{ id = "organs", tree = "symptoms", name = "Organ Failure", desc = "Fatal. Nations collapse in front of you.",
		cost = 1500000, req = { "bleeding", "necrosis" }, req_n = 2, col = 2, row = 4, fx = { loss = 0.22, leth = 0.004 } },

	-- Abilities: survive terrain, medicine and the cure --------------------------------------------
	{ id = "cold", tree = "abilities", name = "Cold Resistance", desc = "Survives the hills. Highlands cost less to infect.",
		cost = 45000, col = 1, row = 1, fx = { hill = 0.30 } },
	{ id = "altitude", tree = "abilities", name = "Mountain Strain", desc = "Thrives in thin air. Mountains cost far less to infect.",
		cost = 260000, req = { "cold" }, col = 1, row = 2, fx = { hill = 0.15, mount = 0.40 } },
	{ id = "drugs", tree = "abilities", name = "Drug Resistance", desc = "Medicine fails. Defense Posts barely slow you down.",
		cost = 120000, col = 2, row = 1, fx = { post = 0.6 } },
	{ id = "shift", tree = "abilities", name = "Gene Shift", desc = "Hides its genes. The cure needs more work.",
		cost = 160000, col = 3, row = 1, fx = { resist = 0.25 } },
	{ id = "shield", tree = "abilities", name = "Gene Shield", desc = "Rewrites itself. The cure needs much more work.",
		cost = 700000, req = { "shift" }, col = 3, row = 2, fx = { resist = 0.40 } },
	{ id = "harvest", tree = "abilities", name = "DNA Harvest", desc = "Feeds on its hosts. More DNA every second.",
		cost = 35000, col = 4, row = 1, fx = { gold = 0.15 } },
	{ id = "bank", tree = "abilities", name = "Mutation Bank", desc = "Stores every mutation. Much more DNA.",
		cost = 380000, req = { "harvest" }, col = 4, row = 2, fx = { gold = 0.25 } },
	{ id = "host", tree = "abilities", name = "Super Host", desc = "Bodies carry more of it. More infected at once.",
		cost = 520000, req = { "bank", "altitude" }, col = 2, row = 3, fx = { cap = 0.25 } },
}

Traits.by_id = {} :: { [string]: any }
for i, t in Traits.list do
	t.index = i
	Traits.by_id[t.id] = t
end

--- Strains a solo match can start as (the pathogen window): each starts with one evolution.
Traits.STRAINS = {
	{ id = "bacterium", name = "Bacterium", desc = "Tough. Starts with Cold Resistance.", start = "cold", color = "#e04848" },
	{ id = "virus", name = "Virus", desc = "Fast. Starts with Coughing.", start = "cough", color = "#c04ae0" },
	{ id = "fungus", name = "Fungus", desc = "Creeping. Starts with Hardy Spores.", start = "spores", color = "#e08a2c" },
	{ id = "parasite", name = "Parasite", desc = "Greedy. Starts with DNA Harvest.", start = "harvest", color = "#3cb06a" },
}
Traits.strain_by_id = {} :: { [string]: any }
for _, s in Traits.STRAINS do
	Traits.strain_by_id[s.id] = s
end

--- True when `id` may be bought given the owned set (prerequisites only; not the price).
function Traits.reachable(id: string, owned: { [string]: boolean }): boolean
	local t = Traits.by_id[id]
	if t == nil or owned[id] then
		return false
	end
	local req = t.req
	if req == nil then
		return true
	end
	local need = t.req_n or 1
	local n = 0
	for _, r in req do
		if owned[r] then
			n += 1
		end
	end
	return n >= need
end

function Traits.price(id: string, _owned: { [string]: boolean }?): number
	local t = Traits.by_id[id]
	return if t ~= nil then t.cost else math.huge
end

--- Effects of an owned set: multipliers ready for the Sim (1 = no change).
function Traits.effects(owned: { [string]: boolean }): { [string]: number }
	local s = {}
	for id, on in owned do
		local t = Traits.by_id[id]
		if on and t ~= nil then
			for k, v in t.fx do
				s[k] = (s[k] or 0) + v
			end
		end
	end
	local function sub(k: string, floor: number): number
		return math.max(floor, 1 - (s[k] or 0))
	end
	return {
		grow = 1 + (s.grow or 0),
		cap = 1 + (s.cap or 0),
		loss = sub("loss", 0.3),
		nloss = sub("nloss", 0.3),
		speed = sub("speed", 0.5),
		hill = sub("hill", 0.3),
		mount = sub("mount", 0.3),
		post = sub("post", 0.0),
		gold = 1 + (s.gold or 0),
		boat = sub("boat", 0.4),
		boats = s.boats or 0,
		leth = s.leth or 0,
		panic = math.min(0.8, s.panic or 0),
		resist = s.resist or 0,
	}
end

return Traits
