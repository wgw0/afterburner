--!strict
-- Your save, as the server shares it (DEVELOPMENT.md §22.1, DAT-03): currencies, jets, lineup,
-- settings and stats. Kept up to date from PlayerDataUpdate deltas; the menus read from here and send
-- intents (Research, Buy, ...) that the server validates. Nothing here is trusted by the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)

local PlayerDataController = {
	Priority = 4,
	data = nil :: { [string]: any }?,
	Loaded = Signal.new(), -- (data) the first full replica arrived
	Changed = Signal.new(), -- (changedKeys: { [string]: true }, data)
	Rewards = Signal.new(), -- (payload) match rewards
	lastRewards = nil :: { [string]: any }?,
}

local function apply(changes: { [string]: any }, full: boolean)
	local self = PlayerDataController
	local first = self.data == nil
	if full or not self.data then
		self.data = changes
	else
		for key, value in changes do
			(self.data :: any)[key] = value
		end
	end
	local keys = {}
	for key in changes do
		keys[key] = true
	end
	if first then
		self.Loaded:Fire(self.data)
	end
	self.Changed:Fire(keys, self.data)
end

-- Waits (yields) until the save has arrived. Returns nil after the timeout.
function PlayerDataController:WaitForData(timeout: number?): { [string]: any }?
	local deadline = os.clock() + (timeout or 30)
	while not self.data and os.clock() < deadline do
		task.wait(0.1)
	end
	return self.data
end

function PlayerDataController:Owns(airframeId: string): boolean
	local data = self.data
	local entry = data and data.Aircraft[airframeId]
	return entry ~= nil and entry.Owned == true
end

-- Intents: each yields for the server's answer and returns (ok, error message).
local function ask(remote: string, ...: any): (boolean, string?)
	local ok, result, message = pcall(Net.Client.invoke, remote, ...)
	if not ok then
		return false, "No answer from the server"
	end
	return result == true, message
end

function PlayerDataController:Research(airframeId: string): (boolean, string?)
	return ask("ResearchAircraft", airframeId)
end

function PlayerDataController:Buy(airframeId: string): (boolean, string?)
	return ask("BuyAircraft", airframeId)
end

function PlayerDataController:BuyModule(airframeId: string, moduleId: string): (boolean, string?)
	return ask("BuyModule", airframeId, moduleId)
end

-- currency: "Credits" (default) or "Wings"
function PlayerDataController:BuySkin(airframeId: string, skinId: string, currency: string?): (boolean, string?)
	return ask("BuySkin", airframeId, skinId, currency)
end

function PlayerDataController:SetSkin(airframeId: string, skinId: string): (boolean, string?)
	return ask("SetSkin", airframeId, skinId)
end

function PlayerDataController:SetModuleFitted(airframeId: string, moduleId: string, fitted: boolean): (boolean, string?)
	return ask("SetModuleFitted", airframeId, moduleId, fitted)
end

function PlayerDataController:SetLineup(ids: { string }): (boolean, string?)
	return ask("SetLineup", ids)
end

function PlayerDataController:Init()
	Net.Client.on("PlayerDataUpdate", function(changes: { [string]: any }, full: boolean)
		apply(changes, full)
	end)
	Net.Client.on("MatchRewards", function(payload: { [string]: any })
		self.lastRewards = payload
		self.Rewards:Fire(payload)
	end)
end

function PlayerDataController:Start()
	-- The server's first push can arrive before this script runs, so ask for the full replica.
	task.spawn(function()
		for _ = 1, 30 do
			if self.data then
				return
			end
			local ok, replica = pcall(Net.Client.invoke, "GetPlayerData")
			if ok and type(replica) == "table" and not self.data then
				apply(replica, true)
				return
			end
			task.wait(1)
		end
	end)
end

return PlayerDataController
