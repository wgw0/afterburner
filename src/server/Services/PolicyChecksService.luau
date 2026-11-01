--!strict
-- Roblox's policy rules for each player (CMP-02; the rules are Shared/Policy). Asked on join, retried a few
-- times; until Roblox answers, or if it never does, the player gets the strict rules (everything regulated
-- off). The answer is shown as player attributes so the client sees it too.

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Policy = require(Shared.Policy)

local PolicyChecksService = {
	Priority = 8,
}

local TRIES = 3

local rules: { [Player]: Policy.Rules } = {}

-- The player's rules (strict until Roblox has answered). Doesn't yield.
function PolicyChecksService:Get(player: Player): Policy.Rules
	return rules[player] or Policy.STRICT
end

local function check(player: Player)
	Policy.show(player, Policy.STRICT, false)
	for attempt = 1, TRIES do
		local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
		if ok then
			if player.Parent then
				rules[player] = Policy.read(info)
				Policy.show(player, rules[player], true)
			end
			return
		end
		warn(`[Policy] couldn't read the policy for {player.UserId} (try {attempt}): {info}`)
		task.wait(2 ^ attempt)
	end
end

function PolicyChecksService:Start()
	Players.PlayerAdded:Connect(check)
	for _, player in Players:GetPlayers() do
		task.spawn(check, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		rules[player] = nil
	end)
end

return PolicyChecksService
