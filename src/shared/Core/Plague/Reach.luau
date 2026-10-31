--!native
-- RoPlague: how the plague can reach a country when the player clicks it (shared by the Sim, which acts,
-- and the interface, which says what a click would do).
--
--   Reach.route(cs, map, target, infected, closed, opts?) -> kind ("land" / "sea" / nil), src
--     country, cost in DNA, reason (when nil)
--     infected(c) -> number: infected hosts of country c (sim: self.Ic[c]; client: the mirror's rows)
--     closed(c) -> number: closure bits of c (PlagueSim.C_*)
--   land: target shares a land border with an infected country (only a neighbour: never across the map);
--   sea: an infected country's coast is on the same sea as target's and within sailing range
--     (Rules.SEA_RANGE tiles, plus SEA_RANGE_WATER per point of the water traits).
--   Reach.coasts(cs, map) -> [c] = {[water body] = {coastal tiles of c on it, sampled}}  (cached on cs)
--   Reach.sea_dist(cs, map, a, b) -> distance in tiles between the nearest coasts of a and b on a sea
--     they share (math.huge when none), their two tiles and the body (cached per pair)
local Rules = require("./PlagueRules")

local readu8 = buffer.readu8

local Reach = {}

--- Coastal tiles kept per country and sea (spread along the coast) for the distance test.
Reach.SAMPLES = 40

function Reach.coasts(cs: any, map: any): { [number]: { [number]: { number } } }
	local cached = cs._coasts
	if cached ~= nil then
		return cached
	end
	local out = {}
	local coastal = map.coastal
	for c = 1, cs.count do
		local cc = cs.list[c]
		local all = {}
		local tl = cc.tile_list
		for k = 0, cc.tiles - 1 do
			local t = buffer.readi32(tl, k * 4)
			if readu8(coastal, t) == 1 then
				local b = map:coast_body_of(t)
				if b > 0 then
					local l = all[b]
					if l == nil then
						l = {}
						all[b] = l
					end
					l[#l + 1] = t
				end
			end
		end
		local by = {}
		for b, l in all do
			if #l <= Reach.SAMPLES then
				by[b] = l
			else
				local s = table.create(Reach.SAMPLES)
				for i = 1, Reach.SAMPLES do
					s[i] = l[1 + math.floor((i - 1) * #l / Reach.SAMPLES)]
				end
				by[b] = s
			end
		end
		out[c] = by
	end
	cs._coasts = out
	cs._sea_dist = {}
	return out
end

function Reach.sea_dist(cs: any, map: any, a: number, b: number): (number, number, number, number)
	local coasts = Reach.coasts(cs, map)
	local cache = cs._sea_dist
	local key = if a < b then a * 512 + b else b * 512 + a
	local hit = cache[key]
	if hit == nil then
		local W = map.W
		local lo, hi = math.min(a, b), math.max(a, b)
		local best, ta, tb, body = math.huge, -1, -1, 0
		local ca, cb = coasts[lo], coasts[hi]
		for bo, la in ca do
			local lb = cb[bo]
			if lb ~= nil then
				for _, t in la do
					local ax, ay = t % W, t // W
					for _, u in lb do
						local d = (ax - u % W) ^ 2 + (ay - u // W) ^ 2
						if d < best then
							best, ta, tb, body = d, t, u, bo
						end
					end
				end
			end
		end
		-- stored as seen from the lower id
		hit = { math.sqrt(best), ta, tb, body }
		cache[key] = hit
	end
	if a < b then
		return hit[1], hit[2], hit[3], hit[4]
	end
	return hit[1], hit[3], hit[2], hit[4]
end

--- How far (tiles) a ship can sail with `water` points of the water traits.
function Reach.sea_range(water: number?): number
	return Rules.SEA_RANGE + Rules.SEA_RANGE_WATER * (water or 0)
end

--- What a click on `target` does: ("land" | "sea" | nil, source country, DNA cost, reason when nil).
--- `opts`: {water (points of the water traits), stow, ships (true: ships can sail), min_hosts (a source
--- country needs this many infected before anything leaves it), extra (DNA added to every click)}.
function Reach.route(
	cs: any,
	map: any,
	target: number,
	infected: (number) -> number,
	closed: (number) -> number,
	opts: any?
): (string?, number, number, string?)
	local o = opts or {}
	local water = o.water or 0
	local min_hosts = o.min_hosts or 1
	local extra = o.extra or 0
	if target <= 0 or target > cs.count then
		return nil, 0, 0, "Not a country"
	end
	if infected(target) >= 1 then
		return nil, 0, 0, "Already infected"
	end
	if next(cs.list[target].neighbors) == nil and next(Reach.coasts(cs, map)[target]) == nil then
		return nil, 0, 0, "Can't be reached"
	end
	local tc = cs.list[target]
	-- land: the bordering infected country with the longest shared border, strong enough to travel
	local best, best_n, weak, weak_i = 0, -1, 0, -1
	for _, nb in tc.neighbors do
		local i = infected(nb[1])
		if i >= min_hosts and nb[2] > best_n then
			best, best_n = nb[1], nb[2]
		elseif i >= 1 and i > weak_i then
			weak, weak_i = nb[1], i
		end
	end
	if best > 0 then
		local cost = Rules.INFECT_LAND_DNA + extra
		if bit32.band(closed(target), Rules.C_BORDER) ~= 0 then
			cost += Rules.INFECT_CLOSED_DNA
		end
		return "land", best, cost, nil
	end
	-- sea: the nearest strong infected coast on a sea the target's coast touches, within range
	local coasts = Reach.coasts(cs, map)
	local src, sd, any_coast = 0, math.huge, false
	if next(coasts[target]) ~= nil then
		for c = 1, cs.count do
			if c ~= target and infected(c) >= 1 and next(coasts[c]) ~= nil then
				local d = Reach.sea_dist(cs, map, c, target)
				if d < math.huge then
					any_coast = true
					if infected(c) >= min_hosts and d < sd then
						sd = d
						src = c
					end
				end
			end
		end
	end
	if src > 0 and sd <= Reach.sea_range(water) and o.ships ~= false then
		local cost = Rules.INFECT_SEA_DNA + extra
		-- (Stowaway: closed ports cost nothing extra)
		if bit32.band(closed(target), Rules.C_PORT) ~= 0 and (o.stow or 0) < 0.1 then
			cost += Rules.INFECT_CLOSED_DNA
		end
		if water >= 0.15 then
			cost = math.max(1, cost - 1)
		end
		return "sea", src, cost, nil
	end
	-- why not: the reasons a player can act on, the nearest first
	if weak > 0 then
		return nil,
			0,
			0,
			string.format("%s needs %d infected to spread (%d now)", cs.list[weak].name, min_hosts, math.floor(weak_i))
	end
	if any_coast and o.ships == false then
		return nil, 0, 0, "Evolve Water Supply to send ships"
	end
	if src > 0 then
		return nil, 0, 0, "Too far to sail. Infect somewhere closer"
	end
	if any_coast then
		return nil, 0, 0, string.format("Your coasts need %d infected to send a ship", min_hosts)
	end
	return nil, 0, 0, "Not next to your plague yet"
end

--- The coastal tiles a ship from `src` to `target` sails between (nearest pair on a sea they share).
function Reach.sea_ends(cs: any, map: any, src: number, target: number): (number, number, number)
	local _, a, b, body = Reach.sea_dist(cs, map, src, target)
	return a, b, body
end

return Reach
