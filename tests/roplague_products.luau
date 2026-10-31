--!nocheck
-- RoPlague: every developer product of OUR universe (Data/Products with an id, build/products_manifest
-- .json) grants what its card says when its receipt comes (server/Purchases.process_receipt): each
-- perk unlocks its Arsenal item, 2x Stars, the starter pack its three items (while its offer runs),
-- the crate offers their crate credits (1 / 1 / 3 / 10), Take Over a credit, every colour of the colour
-- shop is owned AND worn, the Halloween bundle all four with its rarest worn; a crate credit opens into
-- a crate colour (never a duplicate) and it can be worn (the "color" slot), and a retried receipt pays
-- nothing twice.
require("./prelude")
local Products = require("../src/shared/Data/Products")
local Purchases = require("../src/server/Purchases")
local Arsenal = require("../src/shared/Data/Arsenal")
local Starter = require("../src/shared/Data/Starter")
local Shop = require("../src/shared/Data/Shop")
local Strains = require("../src/shared/Data/Strains")
local Cosmetics = require("../src/shared/Data/Cosmetics")
local Gamepasses = require("../src/shared/Data/Gamepasses")

local fails = 0
local function expect(c: any, w: string)
	if c then
		print("  ok   " .. w)
	else
		fails += 1
		print("FAIL " .. w)
	end
end

local rows = {}
local store = {}
function store:UpdateAsync(k, fn)
	local new = fn(rows[k])
	if new ~= nil then
		rows[k] = new
	end
	return new
end
function store:GetAsync(k)
	return rows[k]
end

local t = 1800000000
local P = { UserId = 7, Name = "Buyer" }
Purchases.reset()
Purchases.configure({
	datastore = store,
	players = {
		GetPlayerByUserId = function(_, id)
			return if id == 7 then P else nil
		end,
	},
	now = function()
		return t
	end,
})
Purchases.load(P)

local n = 0
local function buy(key: string): string
	n += 1
	local p = Products[key]
	return Purchases.process_receipt({ PlayerId = 7, ProductId = p.id, PurchaseId = "r" .. n, CurrencySpent = p.robux })
end
local function rec()
	return rows.u7
end

-- every product with an id is ours and unique
local seen = {}
local dup = false
local live = 0
for key, p in Products do
	if p.id ~= 0 then
		live += 1
		if seen[p.id] then
			dup = true
		end
		seen[p.id] = key
	end
end
expect(live >= 34 and not dup, ("%d live products, no id twice"):format(live))
for _, k in { "unlock_mega", "unlock_scatter", "unlock_reinforce", "unlock_artillery", "unlock_airfield", "unlock_railgun", "unlock_reload2x" } do
	expect(Products[k].id == 0, k .. " is not sold (RoWorld's war items)")
end
expect(Gamepasses.rename.id > 0 and Gamepasses.rename.robux == 19, "the Rename pass has its id, 19 Robux")

-- the perks: each unlocks its item (and 2x Stars too)
for _, it in Arsenal.ITEMS do
	if it.product ~= nil and Products[it.product] ~= nil and Products[it.product].id ~= 0 then
		expect(buy(it.product) == "granted" and rec().unlocks[it.key] == true, "perk " .. it.key .. " unlocks")
	end
end
expect(Purchases.has_unlock(P, "stars2x"), "2x Stars is unlocked")

-- the starter pack: refused without a running offer, then granted with one (a fresh account)
local P2 = { UserId = 8 }
Purchases.configure({
	players = {
		GetPlayerByUserId = function(_, id)
			return if id == 7 then P elseif id == 8 then P2 else nil
		end,
	},
})
rows.u8 = { stars_earned = 100 }
Purchases.load(P2)
local sp = Products.starter_pack
expect(
	Purchases.process_receipt({ PlayerId = 8, ProductId = sp.id, PurchaseId = "s1" }) == "not_processed",
	"starter pack: no offer running, not granted"
)
Purchases.starter_seen(P2)
expect(
	Purchases.process_receipt({ PlayerId = 8, ProductId = sp.id, PurchaseId = "s2" }) == "granted",
	"starter pack: granted while its offer runs"
)
local all = true
for _, k in Starter.ITEMS do
	all = all and rows.u8.unlocks[k] == true
end
expect(all, "starter pack: its three items unlocked")

-- crates: 1 / 1 / 3 / 10 credits
local c0 = rec().credits.crate or 0
expect(buy("crate_first") == "granted" and rec().credits.crate == c0 + 1, "first crate: 1 credit")
expect(buy("crate") == "granted" and rec().credits.crate == c0 + 2, "crate: 1 credit")
expect(buy("crate3") == "granted" and rec().credits.crate == c0 + 5, "3 crates: 3 credits")
expect(buy("crate10") == "granted" and rec().credits.crate == c0 + 15, "10 crates: 10 credits")
expect(buy("takeover") == "granted" and rec().credits.takeover == 1, "take over: 1 credit")

-- open the crates: every one a crate colour not owned yet, worn when nothing was worn
local seed = 12345
Purchases.configure({
	rng = {
		NextNumber = function()
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end,
	},
})
local got = {}
local okall, colour_all = true, true
for i = 1, 15 do
	local ok, id = Purchases.open_crate(P)
	okall = okall and ok
	if ok then
		local it = Cosmetics.item(id)
		colour_all = colour_all and it ~= nil and it.kind == "color" and it.crate_color == true and not got[id]
		got[id] = true
	end
end
expect(okall, "15 crates open")
expect(colour_all, "every crate gave a crate colour, never one twice")
expect(rec().credits.crate == c0, "the crates' credits are spent")
local crate_colours = 0
for _, it in Cosmetics.all() do
	crate_colours += 1
	if it.kind ~= "color" then
		colour_all = false
	end
end
expect(crate_colours == 20, "the crate catalog is 20 colours")
expect(Strains.key_of_item(rec().equipped.color) ~= nil, "the first crate colour was put on")

-- the colour shop: each colour owned and worn, a second buy pays Stars
for _, f in Shop.flags() do
	if f.set == nil then
		local key = "shop_" .. f.key
		local r = buy(key)
		expect(r == "granted" and rec().owned[key] == true and rec().equipped.color == key, "colour " .. f.key .. " owned and worn")
	end
end
local stars = rec().stars
expect(buy("shop_toxic") == "granted" and rec().stars > stars, "toxic again pays Stars")

-- the Halloween bundle
expect(buy("shopset_halloween") == "granted", "the Halloween bundle is granted")
local hk = Shop.set_keys("halloween")
local has = true
for _, k in hk do
	has = has and rec().owned["shop_" .. k] == true
end
expect(#hk == 4 and has, "it holds the set's 4 colours")
expect(rec().equipped.color == "shop_" .. hk[1], "its rarest is worn")

-- wearing: any owned colour (shop or crate), the free default (false), never one not owned
local crate_id = next(got)
expect(Purchases.equip(P, "color", crate_id) == true and rec().equipped.color == crate_id, "a crate colour can be worn")
expect(Purchases.equip(P, "color", false) == true and rec().equipped.color == nil, "back to the free colour")
local ok3 = Purchases.equip(P, "color", "color_nebula")
expect(ok3 == (rec().owned.color_nebula == true), "a colour not owned can't be worn")

-- a retried receipt pays nothing twice
local before = rec().credits.crate or 0
local p = Products.crate10
expect(
	Purchases.process_receipt({ PlayerId = 7, ProductId = p.id, PurchaseId = "retry" }) == "granted"
		and Purchases.process_receipt({ PlayerId = 7, ProductId = p.id, PurchaseId = "retry" }) == "granted"
		and rec().credits.crate == before + 10,
	"a retried receipt is granted once"
)

if fails > 0 then
	error(("%d failed"):format(fails))
end
print("roplague products ok")
