--!strict
-- Player data (DEVELOPMENT.md §22, DAT-01 / DAT-03). ProfileStore with session locking, so the same
-- account can't be loaded by two servers at once (no duplicated progress).
--   Store name includes the environment: PlayerData_Test_v1 / PlayerData_Prod_v1.
--   Loads on join and migrates (PlayerData.migrate). If loading fails, the player is kicked with a
--   friendly message: never play on a blank profile that could overwrite the real one.
--   All writes go through Update(player, fn); afterwards the changed replicated fields are pushed to
--   that player (PlayerDataUpdate, deltas). Other players' data is never sent.
--   Before a profile is released (leaving, shutdown), BeforeRelease fires so match rewards earned so far
--   can still be saved. ProfileStore ends every session on shutdown itself (BindToClose).
-- Without DataStore access (an unpublished place in Studio) ProfileStore runs on an in-memory mock:
-- everything works, but nothing persists between sessions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Environment = require(Shared.Config.Environment)
local Net = require(Shared.Net)
local PlayerData = require(Shared.PlayerData)
local Signal = require(Shared.Util.Signal)
local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)

local ProfileStore = require(ServerStorage:WaitForChild("ServerPackages"):WaitForChild("ProfileStore")) :: any

local DataService = {
	Priority = 5,
	ProfileLoaded = Signal.new(), -- (player, data)
	BeforeRelease = Signal.new(), -- (player, data): last chance to write before the session ends
	Changed = Signal.new(), -- (player, delta)
}

local store: any
local profiles: { [Player]: any } = {}
local replicas: { [Player]: { [string]: any } } = {}

function DataService:StoreName(): string
	return `PlayerData_{if Environment.isTest() then "Test" else "Prod"}_v{PlayerData.VERSION}`
end

-- True while running on ProfileStore's in-memory mock (no DataStore access).
function DataService:IsMock(): boolean
	return ProfileStore.DataStoreState ~= "Access"
end

-- The live save for a player (nil until loaded). Read it freely; write only through Update.
function DataService:GetData(player: Player): { [string]: any }?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

function DataService:IsLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

local function push(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local after = PlayerData.replica(profile.Data)
	local delta = PlayerData.delta(replicas[player] or {}, after)
	replicas[player] = after
	if delta then
		Net.Server.fire("PlayerDataUpdate", player, delta, false)
		DataService.Changed:Fire(player, delta)
	end
end

-- Runs fn on a player's save and pushes what changed. Returns whatever fn returns (or nil, "not
-- loaded" if the profile isn't loaded).
function DataService:Update(player: Player, fn: (data: { [string]: any }) -> ...any): ...any
	local profile = profiles[player]
	if not profile then
		return nil, "Your data isn't loaded yet"
	end
	local results = table.pack(fn(profile.Data))
	push(player)
	return table.unpack(results, 1, results.n)
end

local function load(player: Player)
	local profile = store:StartSessionAsync(`Player_{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if not profile then
		if player.Parent == Players then
			Telemetry.event("DataLoadFailed", 1, {}, player)
			player:Kick("Afterburner couldn't load your save. Please rejoin in a moment.")
		end
		return
	end
	profile:AddUserId(player.UserId)
	local _, applied = PlayerData.migrate(profile.Data)
	if #applied > 0 then
		Telemetry.event("DataMigrated", #applied, { to = PlayerData.VERSION }, player)
	end
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		replicas[player] = nil
		if player.Parent == Players then
			-- Another server took the session (the account joined somewhere else)
			player:Kick("Your save was opened on another server. Please rejoin.")
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession() -- left while loading
		return
	end
	profiles[player] = profile
	replicas[player] = PlayerData.replica(profile.Data)
	Net.Server.fire("PlayerDataUpdate", player, replicas[player], true)
	DataService.ProfileLoaded:Fire(player, profile.Data)
end

local function release(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	DataService.BeforeRelease:Fire(player, profile.Data)
	profiles[player] = nil
	replicas[player] = nil
	profile:EndSession()
end

function DataService:Init()
	store = ProfileStore.New(self:StoreName(), PlayerData.template())
	-- The client asks for its full replica when its own code starts (it may miss the first push).
	Net.Server.handle("GetPlayerData", function(player: Player)
		return replicas[player]
	end)
end

function DataService:Start()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	Players.PlayerRemoving:Connect(release)
	game:BindToClose(function()
		-- Rewards first; ProfileStore then ends the sessions and saves.
		for _, player in Players:GetPlayers() do
			release(player)
		end
	end)
end

return DataService
