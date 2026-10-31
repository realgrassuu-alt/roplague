--!strict
-- RoPlague: a plague match's result for its Stars (Data/Stars). RoWorld's Stars.Tracker follows the war
-- Sim's land and conquests; this follows a PlagueSim and reports the same shape, so the server pays it
-- with the same formula and the same caps (server/Rewards: Stars.sanitize, Stars.solo_cap):
--   territory  the peak share of the world infected or dead, as FIELD shares (the whole world: FIELD)
--   conquests  one for every KILL_EVERY countries reached
--   placed     first when humanity is wiped out, last otherwise
--   victory    humanity wiped out
-- Same API as Stars.Tracker: new(sim), watch / unwatch / adopt(id), step(events), final(id),
-- result(id, left).
local Defs = require("../Defs")

local PlagueStars = {}
PlagueStars.__index = PlagueStars

PlagueStars.FIELD = 20
PlagueStars.KILL_EVERY = 12

local TICKS_PER_MINUTE = Defs.TICK_RATE * 60

function PlagueStars.new(sim: any): any
	return setmetatable({ sim = sim, id = 0, peak = 0.0 }, PlagueStars)
end

function PlagueStars.watch(self: any, id: number)
	self.id = id
end

function PlagueStars.unwatch(_self: any, _id: number) end

function PlagueStars.adopt(self: any, _old: number, new: number)
	self.id = new
end

function PlagueStars.step(self: any, _events: any)
	local sim = self.sim
	if sim.phase ~= Defs.PHASE_PLAYING then
		return
	end
	local wp = math.max(sim.world_pop or 1, 1)
	local f = ((sim.Iw or 0) + (sim.Dw or 0)) / wp
	if f > self.peak then
		self.peak = f
	end
end

function PlagueStars.final(self: any, _id: number): boolean
	return self.sim.phase == Defs.PHASE_OVER
end

function PlagueStars.result(self: any, _id: number, left: boolean?): any
	local sim = self.sim
	local started = (sim.playing_since or -1) >= 0
	local field = PlagueStars.FIELD
	if not started then
		return { spawned = false, left = left == true, won = false, minutes = 0, shares = 0, kills = 0, place = 1, field = 1 }
	end
	local reached = 0
	for c = 1, sim.C do
		if (sim.first_tick[c] or -1) >= 0 then
			reached += 1
		end
	end
	local over = sim.phase == Defs.PHASE_OVER
	local won = over and sim.over_reason == Defs.OVER_EXTINCT
	local gone = left == true and not over
	return {
		spawned = true,
		left = gone,
		won = won and not gone,
		minutes = math.max(0, sim.tick - sim.playing_since) / TICKS_PER_MINUTE,
		shares = self.peak * field,
		kills = math.floor(reached / PlagueStars.KILL_EVERY),
		place = if won then 1 else field,
		field = field,
	}
end

return PlagueStars
