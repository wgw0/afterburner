--!strict
-- What this server is for (DEVELOPMENT.md §25, MMK-02): read anywhere from the ServerRole attribute on
-- ReplicatedStorage, which MatchmakingService sets.
--   Lobby:    a public server: the hangar and the matchmaking queue. No flying (the Ground Roamer is fine).
--   Match:    a reserved server running one match for the players the matchmaker sent, then home.
--   Training: a reserved server made for one player: lessons, Vs AI and free flight, any jet, no rewards.
--   Pending:  a reserved server still reading its record (a second or two after it starts).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type Role = "Lobby" | "Match" | "Training" | "Pending"

local ServerRole = {}

function ServerRole.get(): Role
	local role = ReplicatedStorage:GetAttribute("ServerRole")
	if role == "Match" or role == "Training" or role == "Pending" then
		return role
	end
	return "Lobby"
end

function ServerRole.isTraining(): boolean
	return ServerRole.get() == "Training"
end

function ServerRole.isLobby(): boolean
	return ServerRole.get() == "Lobby"
end

function ServerRole.isMatch(): boolean
	return ServerRole.get() == "Match"
end

return ServerRole
