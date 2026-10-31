--!strict
-- RoPlague: infection colours, the plague's own cosmetics (2026-10-29: they replace RoWorld's country
-- flags in the flag shop; a plague has no flag, it has a colour). The equipped one paints every infected
-- tile of a solo match: `a` in the patches' low parts, `b` in their high parts (MapSurface.plague_mix's
-- smooth noise), so a two-tone strain reads as two colours swirling; `rainbow` turns the noise into hue.
-- "crimson" is the free default. Each other strain is a developer product (`product`, our universe),
-- sold in the colour shop at its rarity's price (Data/Shop.PRICES), daily or in a limited set.
local Strains = {}

Strains.DEFAULT = "crimson"

export type Strain = {
	key: string,
	name: string,
	rarity: string,
	a: { number },
	b: { number },
	rainbow: boolean?,
	set: string?,
	product: number?,
	--- a crate's colour (Data/Cosmetics item "color_<key>"): never in the shop
	crate: boolean?,
}

Strains.LIST = {
	{ key = "crimson", name = "Crimson", rarity = "free", a = { 214, 28, 40 }, b = { 240, 70, 60 } },
	-- the daily shop's pool
	{ key = "toxic", name = "Toxic Green", rarity = "rare", a = { 60, 210, 70 }, b = { 150, 240, 60 }, product = 3724049020 },
	{ key = "bruise", name = "Bruise Purple", rarity = "rare", a = { 120, 40, 170 }, b = { 190, 80, 220 }, product = 3724049033 },
	{ key = "bile", name = "Bile Yellow", rarity = "rare", a = { 210, 190, 30 }, b = { 250, 230, 90 }, product = 3724049054 },
	{ key = "frost", name = "Frostbite", rarity = "rare", a = { 40, 120, 230 }, b = { 120, 200, 255 }, product = 3724049088 },
	{ key = "fever", name = "Fever Orange", rarity = "rare", a = { 235, 90, 20 }, b = { 255, 170, 60 }, product = 3724049102 },
	{ key = "rot", name = "Rot", rarity = "rare", a = { 110, 60, 30 }, b = { 170, 110, 50 }, product = 3724049118 },
	{ key = "neon", name = "Neon Pink", rarity = "epic", a = { 240, 40, 150 }, b = { 255, 120, 210 }, product = 3724049129 },
	{ key = "radioactive", name = "Radioactive", rarity = "epic", a = { 120, 230, 20 }, b = { 230, 255, 90 }, product = 3724049142 },
	{ key = "ghost", name = "Ghost White", rarity = "epic", a = { 200, 210, 230 }, b = { 250, 252, 255 }, product = 3724049159 },
	{ key = "void", name = "Void", rarity = "epic", a = { 50, 20, 80 }, b = { 120, 40, 160 }, product = 3724049176 },
	{ key = "lava", name = "Lava", rarity = "legendary", a = { 200, 30, 0 }, b = { 255, 190, 30 }, product = 3724049189 },
	{ key = "galaxy", name = "Galaxy", rarity = "legendary", a = { 60, 30, 180 }, b = { 240, 70, 200 }, product = 3724049208 },
	{ key = "gold", name = "Molten Gold", rarity = "legendary", a = { 200, 130, 10 }, b = { 255, 230, 110 }, product = 3724049210 },
	{ key = "rainbow", name = "Rainbow Plague", rarity = "legendary", a = { 255, 0, 0 }, b = { 0, 0, 255 }, rainbow = true, product = 3724049236 },
	{ key = "mold", name = "Mold", rarity = "rare", a = { 30, 150, 130 }, b = { 110, 220, 190 }, product = 3724049268 },
	-- the Halloween set (Data/Shop.SETS.halloween)
	{ key = "pumpkin", name = "Pumpkin Rot", rarity = "epic", a = { 240, 110, 10 }, b = { 60, 30, 10 }, set = "halloween", product = 3724049281 },
	{ key = "witch", name = "Witch's Brew", rarity = "epic", a = { 110, 40, 160 }, b = { 80, 220, 60 }, set = "halloween", product = 3724049299 },
	{ key = "spectre", name = "Spectre", rarity = "epic", a = { 150, 250, 190 }, b = { 235, 255, 250 }, set = "halloween", product = 3724049325 },
	{ key = "bloodmoon", name = "Blood Moon", rarity = "legendary", a = { 110, 0, 10 }, b = { 255, 40, 40 }, set = "halloween", product = 3724049337 },
	-- the crates' colours (2026-10-29: crates hold infection colours, Data/Cosmetics; never in the shop)
	{ key = "lime", name = "Sickly Lime", rarity = "common", a = { 150, 200, 60 }, b = { 200, 230, 110 }, crate = true },
	{ key = "clay", name = "Clay", rarity = "common", a = { 170, 90, 60 }, b = { 210, 140, 100 }, crate = true },
	{ key = "ash", name = "Ash", rarity = "common", a = { 90, 90, 100 }, b = { 150, 150, 160 }, crate = true },
	{ key = "rust", name = "Rust", rarity = "common", a = { 150, 60, 20 }, b = { 200, 110, 50 }, crate = true },
	{ key = "swamp", name = "Swamp", rarity = "common", a = { 70, 100, 40 }, b = { 120, 150, 60 }, crate = true },
	{ key = "rose", name = "Pale Rose", rarity = "common", a = { 220, 120, 130 }, b = { 245, 180, 185 }, crate = true },
	{ key = "ink", name = "Ink", rarity = "common", a = { 30, 40, 90 }, b = { 70, 90, 160 }, crate = true },
	{ key = "sand", name = "Sandstorm", rarity = "common", a = { 200, 160, 90 }, b = { 235, 205, 140 }, crate = true },
	{ key = "ocean", name = "Ocean Fever", rarity = "rare", a = { 20, 150, 180 }, b = { 100, 220, 230 }, crate = true },
	{ key = "coral", name = "Coral", rarity = "rare", a = { 240, 90, 80 }, b = { 255, 160, 130 }, crate = true },
	{ key = "venom", name = "Venom", rarity = "rare", a = { 30, 120, 40 }, b = { 200, 240, 40 }, crate = true },
	{ key = "amethyst", name = "Amethyst", rarity = "rare", a = { 130, 60, 200 }, b = { 200, 140, 255 }, crate = true },
	{ key = "cherry", name = "Cherry", rarity = "rare", a = { 180, 0, 60 }, b = { 250, 80, 120 }, crate = true },
	{ key = "teal", name = "Teal Rot", rarity = "rare", a = { 0, 110, 100 }, b = { 70, 200, 170 }, crate = true },
	{ key = "aurora", name = "Aurora", rarity = "epic", a = { 30, 200, 140 }, b = { 120, 80, 230 }, crate = true },
	{ key = "sunset", name = "Sunset", rarity = "epic", a = { 240, 80, 40 }, b = { 150, 40, 170 }, crate = true },
	{ key = "icefire", name = "Ice and Fire", rarity = "epic", a = { 40, 140, 255 }, b = { 255, 80, 40 }, crate = true },
	{ key = "toxicsky", name = "Toxic Sky", rarity = "epic", a = { 120, 230, 40 }, b = { 40, 120, 230 }, crate = true },
	{ key = "inferno", name = "Inferno", rarity = "legendary", a = { 255, 60, 0 }, b = { 255, 240, 120 }, crate = true },
	{ key = "nebula", name = "Nebula", rarity = "legendary", a = { 20, 10, 60 }, b = { 0, 220, 255 }, crate = true },
} :: { Strain }

--- A limited set's bundle product (Data/Shop.SETS: its dates and price), our universe; 0 = not made.
Strains.SETS = {
	halloween = { product = 3724049349 },
}

local by_key: { [string]: Strain } = {}
for _, s in Strains.LIST do
	by_key[s.key] = s
end

function Strains.get(key: any): Strain?
	return if type(key) == "string" then by_key[key] else nil
end

--- The strain key of a cosmetic item id: a shop colour "shop_<key>" or a crate colour "color_<key>"
--- (nil: not a colour).
function Strains.key_of_item(id: any): string?
	if type(id) ~= "string" then
		return nil
	end
	local key = string.match(id, "^shop_(.+)$") or string.match(id, "^color_(.+)$")
	return if key ~= nil and by_key[key] ~= nil then key else nil
end

--- The strain the plague of match state `st` (a GameState) wears: its cosmetics' `color` (the plague
--- player's, or the local player's), or DEFAULT.
function Strains.worn(st: any): string
	if type(st) ~= "table" or st.plague == nil then
		return Strains.DEFAULT
	end
	local cos = st.cosmetics or {}
	local c = cos[st.plague.pid] or cos[st.local_owner or 0]
	return Strains.key_of_item(if type(c) == "table" then c.color else nil) or Strains.DEFAULT
end

--- The strain owner `pid` wears (its cosmetics' `color`; none: the default).
function Strains.worn_by(st: any, pid: number): string
	local cos = if type(st) == "table" then st.cosmetics or {} else {}
	local c = cos[pid]
	return Strains.key_of_item(if type(c) == "table" then c.color else nil) or Strains.DEFAULT
end

local function to_hsv(c: { number }): (number, number, number)
	local r, g, b = c[1] / 255, c[2] / 255, c[3] / 255
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, if mx > 0 then d / mx else 0, mx
end

local function from_hsv(h: number, sat: number, v: number): { number }
	h = (h % 1) * 6
	local i = math.floor(h)
	local f = h - i
	local p, q, t = v * (1 - sat), v * (1 - sat * f), v * (1 - sat * (1 - f))
	local r, g, b
	if i == 0 then
		r, g, b = v, t, p
	elseif i == 1 then
		r, g, b = q, v, p
	elseif i == 2 then
		r, g, b = p, v, t
	elseif i == 3 then
		r, g, b = p, q, v
	elseif i == 4 then
		r, g, b = t, p, v
	else
		r, g, b = v, p, q
	end
	return { math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5) }
end

--- How far apart two plagues' hues must be to tell them apart on the map (a turn of the wheel = 1).
Strains.DISTINCT_HUE = 0.085

--- A shared world's plague colours (Plague Race, teams): each plague's worn strain (`keys`, in plague
--- order), moved round the colour wheel where it would look like an earlier plague's. Two players
--- wearing the same strain still tell their plagues apart: the same family, a noticeably different
--- shade. Only the first rainbow stays a rainbow. { {a, b, rainbow, hue} } in plague order.
function Strains.distinct(keys: { string }): { any }
	local out, hues = {}, {}
	local rainbow_taken = false
	local step = Strains.DISTINCT_HUE
	local function free(h: number): boolean
		for _, x in hues do
			local d = math.abs(h - x) % 1
			if math.min(d, 1 - d) < step * 0.999 then
				return false
			end
		end
		return true
	end
	for i, key in keys do
		local s = by_key[key] or by_key[Strains.DEFAULT]
		if s.rainbow and not rainbow_taken then
			rainbow_taken = true
			out[i] = { a = s.a, b = s.b, rainbow = true }
			continue
		end
		local base = if s.rainbow then { 214, 28, 40 } else s.a
		local tip = if s.rainbow then { 240, 70, 60 } else s.b
		local h, sa, va = to_hsv(base)
		local hb, sb, vb = to_hsv(tip)
		-- (a nearly grey strain has no hue to move: it takes a strong one)
		local grey = sa < 0.25
		if grey then
			sa, sb = 0.75, 0.6
		end
		local shift = 0
		for n = 0, 12 do
			local cand = if n == 0 then 0 elseif n % 2 == 1 then step * ((n + 1) // 2) else -step * (n // 2)
			if free(h + cand) then
				shift = cand
				break
			end
		end
		table.insert(hues, (h + shift) % 1)
		out[i] = {
			a = if shift == 0 and not grey then base else from_hsv(h + shift, sa, va),
			b = if shift == 0 and not grey then tip else from_hsv(hb + shift, sb, vb),
			rainbow = false,
			hue = (h + shift) % 1,
		}
	end
	return out
end

--- One colour that stands for a strain on the map (its ships, its travellers): between its two, or,
--- for the rainbow, the hue of time `t` (seconds).
function Strains.tint(key: any, t: number?): Color3
	local a, b, rainbow = Strains.colors(key)
	if rainbow then
		return Color3.fromHSV(((t or 0) * 0.12) % 1, 0.8, 1)
	end
	return a:Lerp(b, 0.35)
end

--- The strain's two colours as Color3 (an unknown key: the default's).
function Strains.colors(key: any): (Color3, Color3, boolean)
	local s = by_key[key] or by_key[Strains.DEFAULT]
	local a, b = s.a, s.b
	return Color3.fromRGB(a[1], a[2], a[3]), Color3.fromRGB(b[1], b[2], b[3]), s.rainbow == true
end

return Strains
