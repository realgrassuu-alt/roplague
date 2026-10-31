--!strict
-- RoPlague gamepasses (Creator Dashboard → Monetization → Passes). `id` is the pass's id in OUR
-- universe; 0 = not created yet (in Studio the pass then counts as owned so the feature can be tried;
-- on a live server it stays locked).
local PASSES: { [string]: any } = {
	--- Rename your plague (UI/Plague/RenameWindow, server/PlagueRename): 19 Robux, for good.
	rename = { id = 2062169203, robux = 19 },
	--- Auto Pop Bubbles (Data/Arsenal auto_pop; server/ServerMain grants the unlock to an owner, the
	--- client's PlagueLink pops every bubble AUTO_POP_S after it shows): 99 Robux, for good.
	auto_pop = { id = 2063039042, robux = 99 },
}

return PASSES
