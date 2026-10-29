--!strict
-- Training servers (DEVELOPMENT.md §26, MMK-02/04 groundwork). A player presses TRAINING on a multiplayer
-- server: we reserve a private server and teleport them into it. A reserved server is a training server:
-- lessons, Vs AI and free flight, with any jet and no rewards. MULTIPLAYER teleports them back to a
-- public server (matchmaking by BR comes with MMK-03).
--   Travel(target)                          "Training" | "Multiplayer"
--   TrainingSetup(mode, difficulty, count)  on a training server: "FreeFlight", or a Vs AI match of
--                                           Dogfight / TeamDeathmatch / AirSuperiority against `count` AI
-- Studio can't teleport between servers, so there Travel switches this server's role in place instead.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AIBrain = require(Shared.AIBrain)
local MatchRules = require(Shared.MatchRules)
local Net = require(Shared.Net)
local ServerRole = require(Shared.ServerRole)

local AircraftService = require(script.Parent.AircraftService)
local MatchService = require(script.Parent.MatchService)

local MAX_AI = 11
local VS_AI_MODES = { Dogfight = true, TeamDeathmatch = true, AirSuperiority = true }

local TrainingService = {
	Priority = 52, -- after MatchService
}

local function setRole(role: string)
	ReplicatedStorage:SetAttribute("ServerRole", role)
	-- A training server starts in free flight; a multiplayer one in the rotation
	MatchService:SetMode(if role == "Training" then "FreeFlight" else MatchRules.ROTATION[1])
end

-- Sends a player to a training server, or back to a multiplayer one.
local function travel(player: Player, target: string)
	if target ~= "Training" and target ~= "Multiplayer" then
		return
	end
	if RunService:IsStudio() then
		-- No teleports in Studio: this server becomes the destination instead
		for _, jet in AircraftService:GetJets() do
			if jet.pilot == player then
				AircraftService:Despawn(jet, "Despawn")
			end
		end
		setRole(target)
		return
	end
	local ok, err = pcall(function()
		if target == "Training" then
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = TeleportService:ReserveServer(game.PlaceId)
			options:SetTeleportData({ role = "Training" })
			TeleportService:TeleportAsync(game.PlaceId, { player }, options)
		else
			TeleportService:TeleportAsync(game.PlaceId, { player })
		end
	end)
	if not ok then
		warn(`[Training] teleport to {target} failed for {player.Name}: {err}`)
		Net.Server.fire("SpawnRefused", player, "Couldn't get there just now. Try again in a moment.")
	end
end

function TrainingService:Init()
	-- A reserved server (no owner) is a training server: those are only made by Travel("Training")
	local reserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
	ReplicatedStorage:SetAttribute("ServerRole", if reserved then "Training" else "Multiplayer")

	Net.Server.on("Travel", travel)
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

function TrainingService:Start()
	if ServerRole.isTraining() then
		MatchService:SetMode("FreeFlight")
	end
end

return TrainingService
