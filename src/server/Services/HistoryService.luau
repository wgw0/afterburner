--!strict
-- Records every jet's pose each server tick for lag compensation (DEVELOPMENT.md §11.4, GUN-04).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PoseHistory = require(Shared.PoseHistory)

local AircraftService = require(script.Parent.AircraftService)

local HISTORY_SECONDS = 1.5
local MAX_REWIND = 0.25 -- seconds: never rewind further than this (§11.4)

local HistoryService = {
	Priority = 25,
}

local histories: { [number]: PoseHistory.PoseHistory } = {}

-- A jet's pose `secondsAgo` in the past (clamped to MAX_REWIND), or its current pose if unknown.
function HistoryService:PoseAt(jetId: number, secondsAgo: number): CFrame?
	local history = histories[jetId]
	local jet = AircraftService:GetJetById(jetId)
	if not history then
		return jet and jet.root.CFrame
	end
	local rewind = math.clamp(secondsAgo, 0, MAX_REWIND)
	return history:sample(workspace:GetServerTimeNow() - rewind) or (jet and jet.root.CFrame)
end

-- How far back to look for a shooter: their latency plus a little interpolation delay.
function HistoryService:RewindFor(player: Player?): number
	if not player then
		return 0
	end
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	return math.clamp((if ok then ping else 0) + 0.05, 0, MAX_REWIND)
end

function HistoryService:Init()
	AircraftService.JetSpawned:Connect(function(jet)
		histories[jet.id] = PoseHistory.new(math.ceil(HISTORY_SECONDS * 60))
	end)
	AircraftService.JetDestroyed:Connect(function(jet)
		histories[jet.id] = nil
	end)
end

function HistoryService:Start()
	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		for id, jet in AircraftService:GetJets() do
			local history = histories[id]
			if history then
				history:record(now, jet.root.CFrame)
			end
		end
	end)
end

return HistoryService
