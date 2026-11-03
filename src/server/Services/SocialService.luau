--!strict
-- The friends bonus (DEVELOPMENT.md §25.8; rules in Shared/Social, numbers in Config/Social). Server side only:
-- it asks Roblox and sets the FriendsBonus attribute on each player, which ProgressionService pays from and the
-- hangar chip and results screen show. The client can't set a player's attributes for the server, so it can be
-- trusted.
--   On a match server: a Roblox friend (IsFriendsWith, each pair asked once) or a member of their party (the
--   match record) is here too. In a lobby: they're in a party, which always flies together, so the chip can say
--   it's on. Never on training servers (no rewards there).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ServerRole = require(Shared.ServerRole)
local Social = require(Shared.Social)

local MatchmakingService = require(script.Parent.MatchmakingService)
local PartyService = require(script.Parent.PartyService)

local SocialService = {
	Priority = 55, -- after PartyService and MatchmakingService
}

local REFRESH = 5 -- seconds between friends checks

local friends: { [string]: boolean } = {} -- Social.pairKey → true once Roblox says they're friends
local asked: { [string]: boolean } = {} -- pairs already asked (or being asked)

-- Asks Roblox about every pair of players here not asked yet (one request each, in the background).
local function askFriends(players: { Player })
	for i, a in players do
		for j = i + 1, #players do
			local b = players[j]
			local key = Social.pairKey(a.UserId, b.UserId)
			if not asked[key] then
				asked[key] = true
				task.spawn(function()
					local ok, yes = pcall(a.IsFriendsWith, a, b.UserId)
					if ok and yes then
						friends[key] = true
					elseif not ok then
						asked[key] = nil -- try again next time
					end
				end)
			end
		end
	end
end

local function refresh()
	local players = Players:GetPlayers()
	local role = ServerRole.get()
	if role == "Match" then
		askFriends(players)
		local present = {}
		for _, player in players do
			table.insert(present, player.UserId)
		end
		local parties = MatchmakingService:MatchParties()
		for _, player in players do
			player:SetAttribute(Social.FRIENDS_ATTRIBUTE, Social.withFriends(player.UserId, present, friends, parties))
		end
	elseif role == "Lobby" then
		for _, player in players do
			player:SetAttribute(Social.FRIENDS_ATTRIBUTE, #PartyService:MembersOf(player) > 1)
		end
	else
		for _, player in players do
			player:SetAttribute(Social.FRIENDS_ATTRIBUTE, false)
		end
	end
end

function SocialService:Init() end

function SocialService:Start()
	PartyService.Changed:Connect(refresh)
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH)
		end
	end)
end

return SocialService
