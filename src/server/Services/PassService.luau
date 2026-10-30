--!strict
-- Game pass ownership (DEVELOPMENT.md §27). Checked with Roblox when a player joins and again when they buy
-- a pass in game; never trusted from the save. Each owned pass shows as a player attribute
-- (Passes.attribute) for the client, and is mirrored into the save as data.Passes (rewritten from Roblox's
-- answer on every join), which is what Shared/Perks reads. Test servers can grant or take passes (admin
-- give.pass / take.pass).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Passes = require(Shared.Config.Passes)
local Signal = require(Shared.Util.Signal)

local DataService = require(script.Parent.DataService)

local PassService = {
	Priority = 7,
	Changed = Signal.new(), -- (player, passName, owned)
}

local owned: { [Player]: { [string]: boolean } } = {}

local function set(player: Player, name: string, has: boolean)
	local list = owned[player]
	if not list or list[name] == has then
		return
	end
	list[name] = has
	player:SetAttribute(Passes.attribute(name), has)
	DataService:Update(player, function(data)
		data.Passes[name] = if has then true else nil
	end)
	PassService.Changed:Fire(player, name, has)
end

-- Whether the player owns the pass (as of their last check). Doesn't yield.
function PassService:Owns(player: Player, name: string): boolean
	local list = owned[player]
	return list ~= nil and list[name] == true
end

-- Test servers only (admin commands): grant or take a pass for this session.
function PassService:Grant(player: Player, name: string, has: boolean)
	set(player, name, has)
end

local function check(player: Player)
	owned[player] = {}
	for name in Passes.LIST do
		player:SetAttribute(Passes.attribute(name), false)
		local id = Passes.idFor(name)
		if id then
			local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
			if ok then
				set(player, name, has == true)
			else
				warn(`[Passes] couldn't check {name} for {player.UserId}: {has}`)
			end
		end
	end
end

function PassService:Init()
	-- The save loaded after (or before) Roblox answered: write what we know, so the mirror is never stale
	DataService.ProfileLoaded:Connect(function(player, data)
		local list = owned[player]
		if not list then
			return
		end
		for name in Passes.LIST do
			data.Passes[name] = if list[name] then true else nil
		end
	end)
end

function PassService:Start()
	Players.PlayerAdded:Connect(check)
	for _, player in Players:GetPlayers() do
		task.spawn(check, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for name in Passes.LIST do
			if Passes.idFor(name) == passId then
				set(player, name, true)
			end
		end
	end)
end

return PassService
