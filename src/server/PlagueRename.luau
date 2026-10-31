--!strict
-- RoPlague: the "Rename your plague" gamepass (Data/Gamepasses.rename). The client asks over
-- ReplicatedStorage.RoPlagueRename (a RemoteFunction):
--   ("owns")       -> owned (boolean), pass id, price
--   ("set", name)  -> ok, filtered name | reason
-- A name is 3 to 22 letters, digits, spaces, dashes or apostrophes, and is put through Roblox's text
-- filter for everyone (TextService, broadcast) before the client may show it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local TextService = game:GetService("TextService")

local PlagueRename = {}

PlagueRename.MIN_LEN = 3
PlagueRename.MAX_LEN = 22
PlagueRename.COOLDOWN = 3.0

local function pass_info(): any
	local ok, passes = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Airfront").Data.Gamepasses)
	end)
	return if ok and type(passes) == "table" then passes.rename else nil
end

local owned_cache: { [Player]: boolean } = {}
local last_set: { [Player]: number } = {}

local function owns(player: Player): boolean
	if owned_cache[player] then
		return true
	end
	local info = pass_info()
	local id = if info ~= nil then tonumber(info.id) or 0 else 0
	if id <= 0 then
		-- not created yet: Studio may try it, a live server may not
		return RunService:IsStudio()
	end
	local ok, has = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)
	if ok and has then
		owned_cache[player] = true
		return true
	end
	return false
end

--- Trims, collapses spaces, and checks the characters. nil when it can't be a name.
function PlagueRename.clean(name: any): string?
	if type(name) ~= "string" then
		return nil
	end
	local s = name:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
	if #s < PlagueRename.MIN_LEN or #s > PlagueRename.MAX_LEN then
		return nil
	end
	if s:find("[^%w %-']") then
		return nil
	end
	return s
end

function PlagueRename.start()
	local rf = Instance.new("RemoteFunction")
	rf.Name = "RoPlagueRename"
	rf.OnServerInvoke = function(player: Player, op: any, name: any): (any, any, any)
		if op == "owns" then
			local info = pass_info()
			return owns(player), if info then info.id else 0, if info then info.robux else 19
		elseif op == "set" then
			local now = os.clock()
			if now - (last_set[player] or -math.huge) < PlagueRename.COOLDOWN then
				return false, "Wait a moment and try again"
			end
			last_set[player] = now
			if not owns(player) then
				return false, "You need the Rename pass"
			end
			local s = PlagueRename.clean(name)
			if s == nil then
				return false, ("Use %d to %d letters, numbers or spaces"):format(PlagueRename.MIN_LEN, PlagueRename.MAX_LEN)
			end
			local ok, out = pcall(function()
				local r = TextService:FilterStringAsync(s, player.UserId, Enum.TextFilterContext.PublicChat)
				return r:GetNonChatStringForBroadcastAsync()
			end)
			if not ok or type(out) ~= "string" then
				return false, "The name check is busy. Try again"
			end
			if out ~= s or out:find("#") then
				return false, "That name isn't allowed"
			end
			return true, out
		end
		return false, "?"
	end
	rf.Parent = ReplicatedStorage
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, id: number, bought: boolean)
		local info = pass_info()
		if bought and info ~= nil and tonumber(info.id) == tonumber(id) then
			owned_cache[player] = true
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		owned_cache[player] = nil
		last_set[player] = nil
	end)
end

return PlagueRename
