--!strict
-- What kind of server this is (DEVELOPMENT.md §26, MMK-02): read anywhere from the ServerRole attribute on
-- ReplicatedStorage, which the server's TrainingService sets at boot.
--   Multiplayer: a public server running the match rotation (the default).
--   Training:    a private (reserved) server made for one player: lessons, Vs AI and free flight, with any
--                jet and no rewards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerRole = {}

function ServerRole.get(): string
	local role = ReplicatedStorage:GetAttribute("ServerRole")
	return if role == "Training" then "Training" else "Multiplayer"
end

function ServerRole.isTraining(): boolean
	return ServerRole.get() == "Training"
end

return ServerRole
