--!strict
-- Training servers (DEVELOPMENT.md §25, TUT-03): a reserved server made for one player (MatchmakingService
-- sends them, and brings them back with MULTIPLAYER). Lessons, Vs AI and free flight, with any jet and no
-- rewards.
--   TrainingSetup(mode, difficulty, count)  "FreeFlight", or a Vs AI match of Dogfight / TeamDeathmatch /
--                                           AirSuperiority against `count` AI of one difficulty

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AIBrain = require(Shared.AIBrain)
local Net = require(Shared.Net)
local ServerRole = require(Shared.ServerRole)

local AircraftService = require(script.Parent.AircraftService)
local MatchService = require(script.Parent.MatchService)

local MAX_AI = 11
local VS_AI_MODES = { Dogfight = true, TeamDeathmatch = true, AirSuperiority = true }

local TrainingService = {
	Priority = 52, -- after MatchmakingService
}

function TrainingService:Init()
	Net.Server.on("TrainingSetup", function(player: Player, modeId: string, difficulty: string, count: number)
		if not ServerRole.isTraining() then
			return
		end
		if modeId == "FreeFlight" then
			MatchService:SetMode("FreeFlight")
		elseif VS_AI_MODES[modeId] and (AIBrain.PROFILES :: any)[difficulty] then
			MatchService:StartVsAI(modeId, difficulty, math.clamp(count, 1, MAX_AI))
		end
		-- Let them pick a new jet for it
		for _, jet in AircraftService:GetJets() do
			if jet.pilot == player then
				AircraftService:Despawn(jet, "Despawn")
			end
		end
	end)
	-- A training server is one player's: when they leave, nobody else is coming
	Players.PlayerRemoving:Connect(function()
		if ServerRole.isTraining() and #Players:GetPlayers() <= 1 then
			MatchService:SetMode("FreeFlight")
		end
	end)
end

return TrainingService
