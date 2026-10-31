--!strict
-- RoPlague: the pathogens and the three evolution trees (Transmission, Symptoms, Abilities).
-- Shared by the Sim (effects, rules) and the Evolve screen (names, layout). Pure data.
--
-- A trait: {id, tree, name, desc, icon, cost, req, req_n, col, row, fx}
--   cost   base DNA; the real price adds Traits.STEP for every trait already owned in the same tree
--   req    ids it may be bought next to: nil = a root (buyable any time); with req_n = k, it needs k of
--          them, otherwise any one
--   col/row  its cell on the tree's grid (the Evolve screen draws links between req and trait)
--   fx     effects, summed over owned traits (PlagueSim._recompute):
--     beta          infectivity per day, everywhere
--     hot / urban / rural / cold_beta   infectivity per day in such countries only
--     air / water   chance a flight / ship from an infected country carries it
--     land          land-border spread multiplier (added to 1)
--     sev           severity (makes the world notice)
--     leth          lethality: share of the infected who die per day
--     cold / heat   climate resistance levels (each gives back part of the climate penalty)
--     drug          drug resistance levels (rich countries' health care hurts less)
--     resist        cure resistance (the cure needs 1 + resist times the work)
--     lock          stops symptoms mutating on their own
--     stow          chance an infected ship turned away at a closed port lands it anyway
local Traits = {}

Traits.TREES = { "transmission", "symptoms", "abilities" }
Traits.TREE_NAMES = { transmission = "Transmission", symptoms = "Symptoms", abilities = "Abilities" }
--- Price added per trait already owned in the same tree.
Traits.STEP = 3
--- Share of the price paid back when a trait is devolved.
Traits.REFUND = 0.5

Traits.list = {
	-- Transmission: five carrier chains and one capstone ---------------------------------------
	{ id = "air1", tree = "transmission", name = "Droplets", desc = "Rides tiny droplets on travellers. Now and then it turns up in a far country by itself.",
		cost = 9, col = 1, row = 1, fx = { air = 0.15, beta = 0.010 } },
	{ id = "air2", tree = "transmission", name = "Airborne", desc = "Hangs in the air for hours. It jumps to far countries by itself much more often.",
		cost = 15, req = { "air1" }, col = 1, row = 2, fx = { air = 0.25, beta = 0.015 } },
	{ id = "water1", tree = "transmission", name = "Water Supply", desc = "Survives in drinking water. Sending a ship costs 1 less DNA.",
		cost = 9, col = 2, row = 1, fx = { water = 0.15, beta = 0.010 } },
	{ id = "water2", tree = "transmission", name = "Ballast Water", desc = "Lives in ship tanks for weeks. Ships are cheaper and coastal countries catch it faster.",
		cost = 15, req = { "water1" }, col = 2, row = 2, fx = { water = 0.25, beta = 0.015 } },
	{ id = "insect1", tree = "transmission", name = "Mosquito Bite", desc = "Insects pass it on. Spreads faster in hot countries.",
		cost = 10, col = 3, row = 1, fx = { hot = 0.02 } },
	{ id = "insect2", tree = "transmission", name = "Swarm Carrier", desc = "Every biting insect carries it. Much faster in hot countries.",
		cost = 16, req = { "insect1" }, col = 3, row = 2, fx = { hot = 0.03, land = 0.1 } },
	{ id = "rodent1", tree = "transmission", name = "Rat Fleas", desc = "Rats carry it through drains and markets. Faster in cities.",
		cost = 10, col = 4, row = 1, fx = { urban = 0.02 } },
	{ id = "rodent2", tree = "transmission", name = "Sewer Colony", desc = "Thrives underground. Much faster in crowded countries.",
		cost = 16, req = { "rodent1" }, col = 4, row = 2, fx = { urban = 0.03, water = 0.05 } },
	{ id = "farm1", tree = "transmission", name = "Farm Animals", desc = "Jumps between livestock and farmers. Faster in rural countries.",
		cost = 10, col = 5, row = 1, fx = { rural = 0.02, land = 0.1 } },
	{ id = "farm2", tree = "transmission", name = "Herd Spillover", desc = "Moves with herds and markets across borders.",
		cost = 16, req = { "farm1" }, col = 5, row = 2, fx = { rural = 0.03, land = 0.25 } },
	{ id = "stowaway", tree = "transmission", name = "Stowaway", desc = "Hides in cargo holds. Ships land even where ports are closed, at no extra cost.",
		cost = 14, req = { "air1", "water1" }, col = 6, row = 2, fx = { stow = 0.35, water = 0.05 } },
	{ id = "hardy", tree = "transmission", name = "Hardy Spores", desc = "Tough enough for every route. All transmission is stronger.",
		cost = 24, req = { "air2", "water2", "insect2", "rodent2", "farm2" }, req_n = 2, col = 3, row = 3,
		fx = { beta = 0.03, air = 0.1, water = 0.1, land = 0.2 } },

	-- Symptoms: a graph, buy next to one you own ------------------------------------------------
	{ id = "nausea", tree = "symptoms", name = "Nausea", desc = "Mild sickness. Hardly noticed.",
		cost = 4, col = 1, row = 1, fx = { beta = 0.006, sev = 0.5 } },
	{ id = "cough", tree = "symptoms", name = "Coughing", desc = "Spreads it in every room. Barely worrying.",
		cost = 4, col = 2, row = 1, fx = { beta = 0.012, sev = 0.5 } },
	{ id = "rash", tree = "symptoms", name = "Rash", desc = "Itchy skin passes it by touch.",
		cost = 3, col = 3, row = 1, fx = { beta = 0.008, sev = 0.5 } },
	{ id = "insomnia", tree = "symptoms", name = "Insomnia", desc = "Sleepless hosts. Doctors start to look.",
		cost = 3, col = 4, row = 1, fx = { sev = 0.8 } },
	{ id = "vomit", tree = "symptoms", name = "Vomiting", desc = "Messy and contagious.",
		cost = 7, req = { "nausea" }, col = 1, row = 2, fx = { beta = 0.015, sev = 2.0, leth = 0.0005 } },
	{ id = "sneeze", tree = "symptoms", name = "Sneezing", desc = "A spray of infection in every crowd.",
		cost = 7, req = { "cough" }, col = 2, row = 2, fx = { beta = 0.02, sev = 1.5 } },
	{ id = "fever", tree = "symptoms", name = "Fever", desc = "Hosts burn up. Hospitals fill.",
		cost = 9, req = { "cough", "insomnia" }, col = 3, row = 2, fx = { beta = 0.008, sev = 3.0, leth = 0.002 } },
	{ id = "cysts", tree = "symptoms", name = "Cysts", desc = "Swellings that burst and spread it.",
		cost = 8, req = { "rash" }, col = 4, row = 2, fx = { beta = 0.012, sev = 2.0 } },
	{ id = "anaemia", tree = "symptoms", name = "Anaemia", desc = "Thin blood, weak hosts.",
		cost = 6, req = { "rash", "nausea" }, col = 5, row = 2, fx = { sev = 1.0, leth = 0.001 } },
	{ id = "paranoia", tree = "symptoms", name = "Paranoia", desc = "Frightened hosts hide their illness.",
		cost = 6, req = { "insomnia" }, col = 6, row = 2, fx = { sev = 1.0, leth = 0.0008 } },
	{ id = "pneumonia", tree = "symptoms", name = "Pneumonia", desc = "Lungs fill. Very contagious, very serious.",
		cost = 13, req = { "sneeze", "fever" }, col = 2, row = 3, fx = { beta = 0.02, sev = 5.0, leth = 0.004 } },
	{ id = "bleeding", tree = "symptoms", name = "Haemorrhage", desc = "Internal bleeding. The world takes notice.",
		cost = 15, req = { "vomit", "anaemia" }, col = 4, row = 3, fx = { beta = 0.01, sev = 6.0, leth = 0.008 } },
	{ id = "seizures", tree = "symptoms", name = "Seizures", desc = "Violent fits. Nobody can ignore it now.",
		cost = 14, req = { "paranoia", "fever" }, col = 6, row = 3, fx = { sev = 6.0, leth = 0.006 } },
	{ id = "paralysis", tree = "symptoms", name = "Paralysis", desc = "Hosts stop moving. Fewer travel.",
		cost = 17, req = { "seizures" }, col = 6, row = 4, fx = { beta = -0.01, sev = 8.0, leth = 0.01 } },
	{ id = "immune", tree = "symptoms", name = "Immune Collapse", desc = "The body stops fighting back.",
		cost = 19, req = { "pneumonia", "bleeding" }, col = 3, row = 4, fx = { beta = 0.01, sev = 8.0, leth = 0.014 } },
	{ id = "organs", tree = "symptoms", name = "Organ Failure", desc = "Fatal for most hosts within weeks.",
		cost = 24, req = { "immune", "bleeding" }, col = 4, row = 5, fx = { sev = 10.0, leth = 0.03 } },
	{ id = "coma", tree = "symptoms", name = "Coma", desc = "Hosts sleep and never wake.",
		cost = 22, req = { "paralysis", "immune" }, col = 5, row = 5, fx = { sev = 10.0, leth = 0.025 } },

	-- Abilities: resistances ---------------------------------------------------------------------
	{ id = "cold1", tree = "abilities", name = "Cold Tolerance", desc = "Survives cold winters. Better in cold countries.",
		cost = 8, col = 1, row = 1, fx = { cold = 1 } },
	{ id = "cold2", tree = "abilities", name = "Frost Proof", desc = "Thrives in the cold.",
		cost = 14, req = { "cold1" }, col = 1, row = 2, fx = { cold = 1 } },
	{ id = "heat1", tree = "abilities", name = "Heat Tolerance", desc = "Survives the heat. Better in hot countries.",
		cost = 8, col = 2, row = 1, fx = { heat = 1 } },
	{ id = "heat2", tree = "abilities", name = "Desert Proof", desc = "Thrives in the heat.",
		cost = 14, req = { "heat1" }, col = 2, row = 2, fx = { heat = 1 } },
	{ id = "drug1", tree = "abilities", name = "Drug Resistance", desc = "Medicine works less well. Better in rich countries.",
		cost = 12, col = 3, row = 1, fx = { drug = 1 } },
	{ id = "drug2", tree = "abilities", name = "Superbug", desc = "Shrugs off every medicine.",
		cost = 20, req = { "drug1" }, col = 3, row = 2, fx = { drug = 1 } },
	{ id = "shield1", tree = "abilities", name = "Gene Shield", desc = "Hides its genome. The cure needs more work.",
		cost = 14, col = 4, row = 1, fx = { resist = 0.25 } },
	{ id = "shield2", tree = "abilities", name = "Gene Shield II", desc = "Rewrites its own markers. The cure needs much more work.",
		cost = 22, req = { "shield1" }, col = 4, row = 2, fx = { resist = 0.35 } },
	{ id = "shield3", tree = "abilities", name = "Gene Shield III", desc = "Researchers chase a moving target.",
		cost = 30, req = { "shield2" }, col = 4, row = 3, fx = { resist = 0.4 } },
	{ id = "lock", tree = "abilities", name = "Gene Lock", desc = "Stops symptoms appearing on their own.",
		cost = 10, col = 5, row = 1, fx = { lock = 1 } },
}

Traits.by_id = {} :: { [string]: any }
for i, t in Traits.list do
	t.index = i
	Traits.by_id[t.id] = t
end

--- The pathogens a run can start as.
--- beta / land / sev / leth: multipliers; mutate: chance per day of a free symptom (scaled by spread);
--- start: traits owned from the first day; ability: an active power (see PlagueSim._ability).
Traits.PATHOGENS = {
	{ id = "bacterium", name = "Bacterium", desc = "Tough and balanced. Shrugs off harsh climates.",
		beta = 1.0, land = 1.0, sev = 1.0, leth = 1.0, mutate = 0.004, env = 0.5, color = "#e04848" },
	{ id = "virus", name = "Virus", desc = "Spreads fast and mutates often. Hard to keep quiet.",
		beta = 1.3, land = 1.0, sev = 1.0, leth = 1.15, mutate = 0.03, env = 1.0, color = "#d23ce0" },
	{ id = "fungus", name = "Fungus", desc = "Slow across borders, but can burst spores into distant lands.",
		beta = 1.05, land = 0.5, sev = 1.0, leth = 1.0, mutate = 0.004, env = 1.0, ability = "spores", color = "#e08a2c" },
	{ id = "parasite", name = "Parasite", desc = "Hides well: the world takes longer to notice. Kills slowly.",
		beta = 0.95, land = 1.0, sev = 0.5, leth = 0.7, mutate = 0.004, env = 1.0, color = "#3cb06a" },
}
Traits.pathogen_by_id = {} :: { [string]: any }
for i, p in Traits.PATHOGENS do
	p.index = i
	Traits.pathogen_by_id[p.id] = p
end

--- Active abilities.
Traits.ABILITIES = {
	spores = { name = "Spore Burst", desc = "Fires spores into a random healthy country.", cost = 15, cooldown_days = 60 },
}

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

--- Price of `id` with `owned` (the tree's step for each trait already owned in it).
--- `mult`: the Gene Bank perk's discount (1 without it).
function Traits.price(id: string, owned: { [string]: boolean }, mult: number?): number
	local t = Traits.by_id[id]
	if t == nil then
		return math.huge
	end
	local n = 0
	for k, on in owned do
		local o = Traits.by_id[k]
		if on and o ~= nil and o.tree == t.tree then
			n += 1
		end
	end
	return math.max(1, math.floor((t.cost + Traits.STEP * n) * (mult or 1) + 0.5))
end

--- True when devolving `id` leaves every other owned trait still reachable.
function Traits.can_devolve(id: string, owned: { [string]: boolean }): boolean
	if not owned[id] then
		return false
	end
	local rest = table.clone(owned)
	rest[id] = nil
	for k, on in rest do
		if on then
			local t = Traits.by_id[k]
			if t ~= nil and t.req ~= nil then
				rest[k] = nil
				local ok = Traits.reachable(k, rest)
				rest[k] = true
				if not ok then
					return false
				end
			end
		end
	end
	return true
end

return Traits
