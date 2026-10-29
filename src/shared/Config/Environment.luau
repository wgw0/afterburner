--!strict
-- Which environment and place role this server is running as.
-- Set by attributes on ReplicatedStorage (so clients can read them too):
--   Environment = "Test" | "Prod"
--   PlaceRole   = "Single" | "Lobby" | "Battle" (else worked out from Config/Places)
-- Missing Environment defaults to "Test" in Studio and "Prod" on live servers, so debug tools never leak live.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type EnvironmentName = "Test" | "Prod"
export type PlaceRole = "Single" | "Lobby" | "Battle"

local Environment = {}

function Environment.get(): EnvironmentName
	local value = ReplicatedStorage:GetAttribute("Environment")
	if value == "Test" or value == "Prod" then
		return value
	end
	return if RunService:IsStudio() then "Test" else "Prod"
end

function Environment.isTest(): boolean
	return Environment.get() == "Test"
end

function Environment.placeRole(): PlaceRole
	local value = ReplicatedStorage:GetAttribute("PlaceRole")
	if value == "Lobby" or value == "Battle" then
		return value
	end
	return require(script.Parent.Places).kind() :: PlaceRole -- from the place ids (Config/Places)
end

return Environment
