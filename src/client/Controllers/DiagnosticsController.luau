--!strict
-- Test-environment diagnostics: one round trip to the server at startup to prove the Net layer works.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Environment = require(Shared.Config.Environment)
local Net = require(Shared.Net)

local DiagnosticsController = {
	Priority = 10,
	pongs = 0,
}

function DiagnosticsController:Init()
	if not Environment.isTest() then
		return
	end
	Net.Client.on("DebugPong", function(_sequence: number, _serverTime: number)
		self.pongs += 1
	end)
end

function DiagnosticsController:Start()
	if not Environment.isTest() then
		return
	end
	local sentAt = os.clock()
	local reply = Net.Client.invoke("DebugEcho", "afterburner")
	print(`[Diagnostics] Echo "{reply}" in {math.round((os.clock() - sentAt) * 1000)} ms`)
	Net.Client.fire("DebugPing", 1)
end

return DiagnosticsController
