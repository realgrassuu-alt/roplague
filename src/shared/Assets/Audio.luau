-- RoPlague's sound effects: public Roblox Creator Store audio, played by asset id (Creator Store
-- audio is free to use in Roblox experiences; nothing here is re-uploaded). Picked by ear on
-- 2026-10-31 (RoPlague_Artwork/RoPlagueSFXRework/picks_final.json) to replace every sound the game
-- used to play. Each entry is the region of the asset that was auditioned (leading and trailing
-- silence cut at -60 dB) and `gain` (dB) the level that matched it to the sound it replaced.
-- Names not listed here (plague_hotspot / infect / send / cure / evolve, and the war-mode sounds
-- RoPlague never plays) come from Assets/AudioPlague, our own synthesised set.
-- sfx entries: {sprite, start, stop, length, gain} (Sound.PlaybackRegion = NumberRange.new(start, stop)).
return {
	-- (no looping themes: the soundtrack is Assets/Soundtrack)
	music = {},
	sfx = {
		-- "ship horn sound effect" by SmugFaceFrieren
		boat_launch = { sprite = "rbxassetid://113335743695644", start = 0.0, stop = 2.253, length = 2.253, gain = -6.8 },
		-- "Building" by Brainlexe_hasldied
		build = { sprite = "rbxassetid://82678416752853", start = 0.033, stop = 2.152, length = 2.119, gain = 6.1 },
		-- "Purchase Sound Effect" by Marshymelona
		buy_spend = { sprite = "rbxassetid://134952684776633", start = 0.021, stop = 2.011, length = 1.99, gain = 1.9 },
		-- "Drawing Card SFX" by zerindimondc
		card_flip = { sprite = "rbxassetid://85390887615121", start = 0.064, stop = 0.395, length = 0.331, gain = 2.7 },
		-- "Audio_swoosh" by thy_doggeth
		card_whoosh = { sprite = "rbxassetid://137431264282253", start = 0.043, stop = 0.54, length = 0.497, gain = -11.2 },
		-- "Success Stinger 02" by BuilderBillbert
		conquer = { sprite = "rbxassetid://89593894732695", start = 0.0, stop = 3.068, length = 3.068, gain = -1.8 },
		-- "gong sfx" by SmilinSphere
		countdown_gamestart = { sprite = "rbxassetid://17798541626", start = 0.077, stop = 3.092, length = 3.015, gain = -15.4 },
		-- "timer tick" by kittiequeenee
		countdown_tick = { sprite = "rbxassetid://113416294133952", start = 0.0, stop = 0.166, length = 0.166, gain = -2.5 },
		-- "SFX_Countdown" by Red Riptide
		countdown_tick_1 = { sprite = "rbxassetid://9062373867", start = 0.0, stop = 0.911, length = 0.911, gain = -14.4 },
		-- "SFX_Countdown" by Red Riptide
		countdown_tick_2 = { sprite = "rbxassetid://9062373867", start = 0.0, stop = 0.911, length = 0.911, gain = -16.0 },
		-- "SFX_Countdown" by Red Riptide
		countdown_tick_3 = { sprite = "rbxassetid://9062373867", start = 0.0, stop = 0.911, length = 0.911, gain = -18.6 },
		-- "SFX_Countdown" by Red Riptide
		countdown_tick_4 = { sprite = "rbxassetid://9062373867", start = 0.0, stop = 0.911, length = 0.911, gain = -20.4 },
		-- "SFX_Countdown" by Red Riptide
		countdown_tick_5 = { sprite = "rbxassetid://9062373867", start = 0.0, stop = 0.911, length = 0.911, gain = -21.7 },
		-- "item_drop3_rare" by TeaBean_funny
		crate_drop = { sprite = "rbxassetid://108936817882815", start = 0.0, stop = 2.052, length = 2.052, gain = -7.5 },
		-- "Heavy critical impact 1" by spinelsnowydoggo
		crate_land = { sprite = "rbxassetid://138232937818879", start = 0.0, stop = 0.598, length = 0.598, gain = -9.5 },
		-- "Chest opening" by TmasterTACO
		crate_open = { sprite = "rbxassetid://116841971399984", start = 0.085, stop = 1.506, length = 1.421, gain = -7.2 },
		-- "Build Up 1" by Astro_Galactoes
		crate_preview_common = { sprite = "rbxassetid://122580867123271", start = 0.001, stop = 1.668, length = 1.667, gain = -11.3 },
		-- "Skybound_Gacha_Reveal_Epic" by N4W1N
		crate_preview_epic = { sprite = "rbxassetid://128526733840627", start = 0.0, stop = 3.064, length = 3.064, gain = -12.3 },
		-- "Skybound_Gacha_Reveal_Legendary" by N4W1N
		crate_preview_legendary = { sprite = "rbxassetid://71806017567681", start = 0.0, stop = 3.49, length = 3.49, gain = -12.3 },
		-- "Skybound_Gacha_Reveal_Rare" by N4W1N
		crate_preview_rare = { sprite = "rbxassetid://90459740584113", start = 0.0, stop = 2.61, length = 2.61, gain = -11.4 },
		-- "Snake Rattle Strike Hissy Fishing Reel 2 (SFX)" by ProSoundEffects
		crate_rattle = { sprite = "rbxassetid://9119303861", start = 0.0, stop = 0.678, length = 0.678, gain = -14.7 },
		-- "shimmer" by veltrixtheperson013
		crate_shimmer = { sprite = "rbxassetid://136730840543746", start = 0.192, stop = 3.511, length = 3.319, gain = -5.6 },
		-- "Defeated" by DistrokidOfficial
		defeat = { sprite = "rbxassetid://135261658507155", start = 0.021, stop = 5.642, length = 5.621, gain = 8.3 },
		-- "swirl kick knockout sfx" by Axellatic
		eliminate = { sprite = "rbxassetid://111448010787576", start = 0.021, stop = 0.756, length = 0.735, gain = -7.0 },
		-- "gong sfx" by SmilinSphere
		game_start = { sprite = "rbxassetid://17798541626", start = 0.077, stop = 3.092, length = 3.015, gain = -11.3 },
		-- "Short siren" by killerguy1322
		nuke_alarm = { sprite = "rbxassetid://2136001428", start = 2.215, stop = 5.478, length = 3.263, gain = -5.7 },
		-- "cartoon bubble pop" by ad0xsus
		plague_pop = { sprite = "rbxassetid://109359226723492", start = 0.021, stop = 0.89, length = 0.869, gain = -5.0 },
		-- "Notification Chime" by Flare Studio (Flare Works)
		queue_start = { sprite = "rbxassetid://104000340117740", start = 0.041, stop = 1.664, length = 1.623, gain = -8.6 },
		-- "Skybound_Gacha_Reveal_Common" by N4W1N
		reveal_common = { sprite = "rbxassetid://137357606937971", start = 0.0, stop = 1.899, length = 1.899, gain = -1.8 },
		-- "reward_screen_reveal_day5" by thienbao2109
		reveal_epic = { sprite = "rbxassetid://4612378364", start = 0.0, stop = 3.212, length = 3.212, gain = -1.7 },
		-- "legendary_-mythic-drop" by HappyAppleBay
		reveal_legendary = { sprite = "rbxassetid://95448393681386", start = 0.043, stop = 2.197, length = 2.154, gain = 3.0 },
		-- "reward_screen_reveal" by thienbao2109
		reveal_rare = { sprite = "rbxassetid://4612378086", start = 0.0, stop = 3.228, length = 3.228, gain = -3.5 },
		-- "slime splat 2" by feelingsrestricted
		spawn_confirm = { sprite = "rbxassetid://75221355097604", start = 0.0, stop = 1.214, length = 1.214, gain = -3.1 },
		-- "Roblox_UI_Paper_Swipe" by Roblox
		spectate_switch = { sprite = "rbxassetid://15675037413", start = 0.0, stop = 0.446, length = 0.446, gain = -8.7 },
		-- "DonasiLevel3" by Republik Insomnia
		star_get = { sprite = "rbxassetid://75134371853151", start = 0.0, stop = 1.268, length = 1.268, gain = 2.3 },
		-- "Tick Sound" by BeaminYo
		star_tick = { sprite = "rbxassetid://75290320204186", start = 0.0, stop = 0.05, length = 0.05, gain = 9.7 },
		-- "RBLX UI Back (SFX)" by Roblox
		ui_back = { sprite = "rbxassetid://10066914500", start = 0.0, stop = 0.533, length = 0.533, gain = 13.2 },
		-- "Button Click" by RoninWrath
		ui_click = { sprite = "rbxassetid://6042053626", start = 0.0, stop = 0.079, length = 0.079, gain = -4.5 },
		-- "UI - Menu Select" by SodaBreadle
		ui_confirm = { sprite = "rbxassetid://111174530730534", start = 0.0, stop = 0.564, length = 0.564, gain = 3.1 },
		-- "UI - Error 1" by lluma3D
		ui_error = { sprite = "rbxassetid://91660275693179", start = 0.0, stop = 0.352, length = 0.352, gain = -8.9 },
		-- "UI - Hover 1" by SodaBreadle
		ui_hover = { sprite = "rbxassetid://119354387183704", start = 0.0, stop = 0.076, length = 0.076, gain = -4.0 },
		-- "Lock Click" by zimglo
		ui_locked = { sprite = "rbxassetid://127004816100960", start = 0.0, stop = 0.071, length = 0.071, gain = -3.4 },
		-- "Smaltra UI window open" by Porevoz
		ui_open = { sprite = "rbxassetid://104492563723558", start = 0.0, stop = 0.364, length = 0.364, gain = 3.2 },
		-- "mixkit-typewriter-soft-click-1125" by HDTV_GO
		ui_tab = { sprite = "rbxassetid://96949444184991", start = 0.095, stop = 0.216, length = 0.121, gain = 5.6 },
		-- "Unlock Item" by ForeverHD
		unlock = { sprite = "rbxassetid://873617644", start = 0.0, stop = 1.52, length = 1.52, gain = -9.3 },
		-- "Victory Fanfare Sting" by APMOfficial
		victory = { sprite = "rbxassetid://1836473422", start = 0.213, stop = 5.782, length = 5.569, gain = -2.9 },
	},
}
