--!strict
-- Which environment and place role this server is running as.
--   Environment: "Test" in the test experience (TEST_UNIVERSES) and in Studio, "Prod" in any other experience
--     live, so publishing the place to production needs no switch (REL-04) and debug tools never leak live.
--     In Studio only, an `Environment` attribute on ReplicatedStorage overrides it (to try Prod behaviour).
--   PlaceRole: "Single" | "Lobby" | "Battle", from a `PlaceRole` attribute, else worked out from Config/Places.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type EnvironmentName = "Test" | "Prod"
export type PlaceRole = "Single" | "Lobby" | "Battle"

local Environment = {}

-- Experiences (universe ids, game.GameId) that are test environments.
Environment.TEST_UNIVERSES = table.freeze({
	10773135125, -- Afterburner (TEST)
})

-- The environment for a universe; pure, for tests. attribute: the Studio override, if any.
function Environment.resolve(gameId: number, isStudio: boolean, attribute: any): EnvironmentName
	if isStudio then
		return if attribute == "Prod" then "Prod" else "Test"
	end
	return if table.find(Environment.TEST_UNIVERSES, gameId) then "Test" else "Prod"
end

function Environment.get(): EnvironmentName
	return Environment.resolve(game.GameId, RunService:IsStudio(), ReplicatedStorage:GetAttribute("Environment"))
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
