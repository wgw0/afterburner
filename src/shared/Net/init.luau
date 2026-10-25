--!strict
-- Typed remote wrapper (DEVELOPMENT.md §4).
-- The server creates every remote from Definitions at Init. Incoming client calls are type-checked
-- and rate-limited before any handler runs; bad calls are dropped and reported through Net.Server.Dropped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Definitions = require(script.Definitions)
local Signal = require(script.Parent.Util.Signal)
local Validate = require(script.Parent.Util.Validate)

local FOLDER_NAME = "Remotes"
local DEFAULT_RATE = { burst = 10, perSecond = 5 }

local Net = {}

local function getDefinition(name: string): Definitions.Definition
	local definition = Definitions[name]
	assert(definition, `Remote "{name}" is not declared in Net/Definitions`)
	return definition
end

---------------------------------------------------------------------------
-- Server
---------------------------------------------------------------------------

local Server = {}
Net.Server = Server

-- Fires (player, remoteName, reason) whenever a client call is rejected.
Server.Dropped = Signal.new()

local remotes: { [string]: Instance } = {}
local buckets: { [Player]: { [string]: { tokens: number, last: number } } } = {}

local function takeToken(player: Player, name: string, rate: { burst: number, perSecond: number }): boolean
	local playerBuckets = buckets[player]
	if not playerBuckets then
		playerBuckets = {}
		buckets[player] = playerBuckets
	end
	local now = os.clock()
	local bucket = playerBuckets[name]
	if not bucket then
		bucket = { tokens = rate.burst, last = now }
		playerBuckets[name] = bucket
	end
	bucket.tokens = math.min(rate.burst, bucket.tokens + (now - bucket.last) * rate.perSecond)
	bucket.last = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

-- Runs the shared checks for a client -> server call. Returns true if the handler may run.
local function admit(player: Player, name: string, definition: Definitions.Definition, ...: any): boolean
	if not takeToken(player, name, definition.rate or DEFAULT_RATE) then
		Server.Dropped:Fire(player, name, "rate limited")
		return false
	end
	local ok, reason = Validate.args(definition.args, select("#", ...), ...)
	if not ok then
		Server.Dropped:Fire(player, name, reason)
		return false
	end
	return true
end

function Server.init()
	assert(RunService:IsServer(), "Net.Server.init must run on the server")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:Destroy() -- stale folder from a previous run in the same session
	end
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME

	for name, definition in Definitions do
		local className = if definition.direction == "Function"
			then "RemoteFunction"
			elseif definition.reliable == false then "UnreliableRemoteEvent"
			else "RemoteEvent"
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
		remotes[name] = remote
	end
	folder.Parent = ReplicatedStorage

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)
end

local function serverRemote(name: string): any
	local remote = remotes[name]
	assert(remote, `Net.Server.init has not created "{name}"`)
	return remote
end

function Server.on(name: string, handler: (Player, ...any) -> ())
	local definition = getDefinition(name)
	assert(definition.direction == "ClientToServer", `"{name}" is not a ClientToServer remote`)
	serverRemote(name).OnServerEvent:Connect(function(player: Player, ...)
		if admit(player, name, definition, ...) then
			handler(player, ...)
		end
	end)
end

function Server.handle(name: string, handler: (Player, ...any) -> ...any)
	local definition = getDefinition(name)
	assert(definition.direction == "Function", `"{name}" is not a Function remote`)
	serverRemote(name).OnServerInvoke = function(player: Player, ...)
		if not admit(player, name, definition, ...) then
			return nil
		end
		return handler(player, ...)
	end
end

local function checkOutgoing(name: string, ...: any)
	local definition = getDefinition(name)
	assert(definition.direction == "ServerToClient", `"{name}" is not a ServerToClient remote`)
	local ok, reason = Validate.args(definition.args, select("#", ...), ...)
	assert(ok, `Net: bad outgoing "{name}": {reason}`)
end

function Server.fire(name: string, player: Player, ...: any)
	checkOutgoing(name, ...)
	serverRemote(name):FireClient(player, ...)
end

function Server.fireAll(name: string, ...: any)
	checkOutgoing(name, ...)
	serverRemote(name):FireAllClients(...)
end

function Server.fireList(name: string, players: { Player }, ...: any)
	checkOutgoing(name, ...)
	local remote = serverRemote(name)
	for _, player in players do
		remote:FireClient(player, ...)
	end
end

---------------------------------------------------------------------------
-- Client
---------------------------------------------------------------------------

local Client = {}
Net.Client = Client

local function clientRemote(name: string): any
	getDefinition(name)
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name)
end

local function checkClientOutgoing(name: string, direction: string, ...: any)
	local definition = getDefinition(name)
	assert(definition.direction == direction, `"{name}" is not a {direction} remote`)
	local ok, reason = Validate.args(definition.args, select("#", ...), ...)
	assert(ok, `Net: bad outgoing "{name}": {reason}`)
end

function Client.on(name: string, handler: (...any) -> ())
	assert(getDefinition(name).direction == "ServerToClient", `"{name}" is not a ServerToClient remote`)
	clientRemote(name).OnClientEvent:Connect(handler)
end

function Client.fire(name: string, ...: any)
	checkClientOutgoing(name, "ClientToServer", ...)
	clientRemote(name):FireServer(...)
end

function Client.invoke(name: string, ...: any): ...any
	checkClientOutgoing(name, "Function", ...)
	return clientRemote(name):InvokeServer(...)
end

return Net
