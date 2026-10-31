--!strict
-- RoPlague's places (2026-10-30: the game moved to the group 439068166). Both carry the same build:
--   LOBBY   the title: solo, the shop, crates, and the multiplayer cards (server/PlagueMatch matchmakes)
--   ONLINE  where a multiplayer match plays (Co-op, Plague Race, 1v1): a reserved server per match,
--           told what to play by the teleport data
local Places = {
	UNIVERSE = 10773823004,
	LOBBY = 107897816258319,
	ONLINE = 97800069016389,
}

--- True on the online place (a multiplayer match's server, or a client on one).
function Places.is_online(): boolean
	return typeof(game) == "Instance" and (game :: any).PlaceId == Places.ONLINE
end

return Places
