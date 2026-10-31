--!strict
-- The Arsenal: units and boosters a player unlocks for good (2026-10-04: units like Artillery and
-- special nukes, unlocked either by grinding Stars in game or by buying them with Robux — the same model
-- as Pixel Conquest's extra-buildings passes, with its prices).
--
--   stars    the price in Stars, the currency earned by playing (Data/Stars); nil: Robux only
--   product  the developer product that unlocks it for Robux (Data/Products; its `robux` is the
--            price shown until Roblox answers with the real one)
--   pass     RoPlague: a gamepass (Data/Gamepasses) that unlocks it instead of a product: Robux only,
--            and the server grants the unlock to whoever owns the pass (server/ServerMain)
--   bonus    Stars paid once with the unlock, however it was bought
--   bit      the Defs.UNLOCK bit the Sim checks (0: the Sim doesn't care — 2x Stars)
--
-- An unlock is saved on the player's record (server/Purchases: `unlocks`), by ProcessReceipt for a
-- Robux purchase or by Purchases.buy_unlock for Stars. The rules and numbers of each unit are the
-- Sim's (Core/Rules "The Arsenal", Core/SimArsenal); the copy here only describes them.
local IS_ROBLOX = typeof(game) == "Instance"
local Defs: any = if IS_ROBLOX
	then require((game :: any):GetService("ReplicatedStorage"):WaitForChild("Airfront").Core.Defs)
	else require("../Core/Defs")

local Arsenal = {}

export type Item = {
	key: string,
	title: string,
	--- RoPlague: "start" (how a match begins), "spread" (how it travels), "boost" (always on)
	kind: string,
	icon: string,
	tagline: string,
	blurb: string,
	perks: { string },
	--- the shop's one sentence: what it does, in plain words (2026-10-24: the Arsenal UI was too
	--- confusing and had to be simpler)
	plain: string,
	--- the shop's two short facts
	facts: { string },
	stars: number?,
	product: string,
	pass: string?,
	bonus: number?,
	bit: number,
	--- the build / launch kinds it opens in a match (UIRules kinds)
	opens: { string },
	--- card colours (top, bottom), 0xRRGGBB
	color: { number },
}

--- RoPlague: the shop sells plague perks, kept for good and applied to every solo match
--- (Session passes the owned keys to PlagueSim as config.perks; the numbers are Core/Plague/PlagueRules
--- PERK_*). RoWorld's war items (nukes, artillery...) are kept in archive/plague_v1/Arsenal_roworld_items.
--- In shop order: cheapest in Stars first, the Robux-only booster last.
Arsenal.ITEMS = {
	{
		key = "head_start",
		title = "Head Start",
		kind = "start",
		icon = "dna",
		tagline = "Begin every match with 6 extra DNA",
		blurb = "Your plague starts every match with 6 more DNA: an evolution or a few clicks right away.",
		perks = { "+6 DNA", "EVERY MATCH" },
		plain = "Start every match with 6 extra DNA, so you can evolve or spread right away.",
		facts = { "+6 DNA", "Every match" },
		stars = 3000,
		product = "unlock_head_start",
		bit = 0,
		opens = {},
		color = { 0xFF9A3C, 0x8A3A0C },
	},
	{
		key = "bubble_magnet",
		title = "Bubble Magnet",
		kind = "spread",
		icon = "infect",
		tagline = "DNA bubbles come up 45% more often",
		blurb = "Orange DNA bubbles float up over your infected land far more often. More DNA, more spots infected.",
		perks = { "+45% BUBBLES", "MORE DNA" },
		plain = "DNA bubbles float up 45% more often: more DNA and more places infected.",
		facts = { "+45% bubbles", "More DNA" },
		stars = 6000,
		product = "unlock_bubble_magnet",
		bit = 0,
		opens = {},
		color = { 0xFF6A3C, 0x7A1A10 },
	},
	{
		key = "super_spreader",
		title = "Super Spreader",
		kind = "start",
		icon = "carrier",
		tagline = "Patient zero starts with 250 infected",
		blurb = "Your plague begins with 250 people already sick, so it can travel to the next country almost at once.",
		perks = { "250 INFECTED AT START", "TRAVEL SOONER" },
		plain = "Patient zero starts with 250 infected, so your plague can travel to its neighbours almost at once.",
		facts = { "250 at start", "Travel sooner" },
		stars = 8000,
		product = "unlock_super_spreader",
		bit = 0,
		opens = {},
		color = { 0xE2483A, 0x6A1018 },
	},
	{
		key = "sea_legs",
		title = "Sea Legs",
		kind = "spread",
		icon = "tr_water2",
		tagline = "Send ships from the start, and sail further",
		blurb = "Infected ships can sail from the first minute, without evolving Water Supply, and 60 tiles further.",
		perks = { "SHIPS FROM THE START", "+60 RANGE" },
		plain = "Send infected ships from the first minute, without evolving Water Supply, and sail further.",
		facts = { "Ships at once", "+60 range" },
		stars = 12000,
		product = "unlock_sea_legs",
		bit = 0,
		opens = {},
		color = { 0x3CB4FF, 0x10407A },
	},
	{
		key = "gene_bank",
		title = "Gene Bank",
		kind = "boost",
		icon = "evolve",
		tagline = "Every evolution costs 15% less",
		blurb = "Every evolution in the Evolve screen costs 15% less DNA, all match long.",
		perks = { "-15% EVOLVE PRICES", "ALL TREES" },
		plain = "Every evolution costs 15% less DNA.",
		facts = { "-15% prices", "All trees" },
		stars = 18000,
		product = "unlock_gene_bank",
		bit = 0,
		opens = {},
		color = { 0x6AD86A, 0x1A6A2A },
	},
	{
		key = "slow_science",
		title = "Slow Science",
		kind = "boost",
		icon = "cure",
		tagline = "The cure needs 15% more work",
		blurb = "Scientists everywhere work slower against your plague: the cure needs 15% more work to finish.",
		perks = { "CURE 15% SLOWER", "EVERY MATCH" },
		plain = "The world's cure takes 15% longer to finish.",
		facts = { "Cure 15% slower", "Every match" },
		stars = 25000,
		product = "unlock_slow_science",
		bit = 0,
		opens = {},
		color = { 0x50BEFF, 0x14306A },
	},
	{
		key = "mutagen",
		title = "Mutagen",
		kind = "boost",
		icon = "tr_hardy",
		tagline = "A free Transmission evolution every match",
		blurb = "Your plague starts every match with a random first Transmission evolution, already evolved for free.",
		perks = { "FREE EVOLUTION", "EVERY MATCH" },
		plain = "Start every match with a free Transmission evolution.",
		facts = { "Free evolution", "Every match" },
		stars = 35000,
		product = "unlock_mutagen",
		bit = 0,
		opens = {},
		color = { 0xA35BFF, 0x3D1A8A },
	},
	{
		key = "stars2x",
		title = "2x Stars",
		kind = "boost",
		icon = "star",
		tagline = "Every match pays double, forever",
		blurb = "Doubles the Stars every match pays you, for good.",
		perks = { "DOUBLE STARS", "EVERY MATCH" },
		plain = "Every match pays you double Stars, forever.",
		facts = { "2x Stars", "Every match" },
		product = "unlock_stars2x",
		bit = 0,
		opens = {},
		color = { 0xFFC83D, 0x9A6200 },
	},
	{
		key = "auto_pop",
		title = "Auto Pop Bubbles",
		kind = "boost",
		icon = "auto_pop",
		tagline = "Every bubble pops by itself",
		blurb = "DNA, cure and hotspot bubbles pop on their own half a second after they appear. Never miss one again.",
		perks = { "AUTO POP", "DNA, CURE, HOTSPOTS" },
		plain = "Every bubble pops by itself half a second after it appears: DNA, cure and hotspots.",
		facts = { "Pops by itself", "All bubbles" },
		product = "",
		pass = "auto_pop",
		bit = 0,
		opens = {},
		color = { 0x46A0FF, 0x123A8A },
	},
} :: { Item }

local BY_KEY: { [string]: Item } = {}
--- build / launch kind -> the item that opens it
local BY_KIND: { [string]: Item } = {}
for _, it in Arsenal.ITEMS do
	BY_KEY[it.key] = it
	for _, k in it.opens do
		BY_KIND[k] = it
	end
end

function Arsenal.item(key: any): Item?
	return if type(key) == "string" then BY_KEY[key] else nil
end

--- The item a build / launch kind ("artillery", "mega", "airstrike", "reinforce"...) belongs to, or nil
--- for the kinds everyone has.
function Arsenal.item_for(kind: string): Item?
	return BY_KIND[kind]
end

--- The Defs.UNLOCK mask of a set of unlock keys ({ [key] = true } or a list of keys).
function Arsenal.mask(unlocks: any): number
	local m = 0
	if type(unlocks) ~= "table" then
		return m
	end
	for k, v in unlocks do
		local it = BY_KEY[if type(k) == "string" then k else v]
		if it ~= nil and (v == true or type(k) == "number") then
			m = bit32.bor(m, it.bit)
		end
	end
	return m
end

--- The cheapest item (in Stars) the player doesn't own yet: what the Stars they earn go towards.
function Arsenal.next_goal(owned: { [string]: boolean }): Item?
	for _, it in Arsenal.ITEMS do
		if it.stars ~= nil and not owned[it.key] then
			return it
		end
	end
	return nil
end

return Arsenal
