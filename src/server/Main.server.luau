--!strict
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boot = require(Shared.Boot)
local Environment = require(Shared.Config.Environment)
local Net = require(Shared.Net)

print(`[Boot] Afterburner server: environment={Environment.get()} role={Environment.placeRole()}`)

-- Read by the startup smoke test (tests/Smoke.luau).
ReplicatedStorage:SetAttribute("ServerBootFailures", 0)
ReplicatedStorage:SetAttribute("ServerRuntimeErrors", 0)
-- Any error raised by our own code after boot (e.g. in a Heartbeat loop) is counted too.
LogService.MessageOut:Connect(function(message, messageType)
	if
		messageType == Enum.MessageType.MessageError
		and (
			string.find(message, "ServerScriptService.Server", 1, true)
			or string.find(message, "ReplicatedStorage.Shared", 1, true)
		)
	then
		ReplicatedStorage:SetAttribute(
			"ServerRuntimeErrors",
			(ReplicatedStorage:GetAttribute("ServerRuntimeErrors") or 0) + 1
		)
	end
end)

Net.Server.init()
Boot.run(script.Parent:WaitForChild("Services"), "Service", function()
	ReplicatedStorage:SetAttribute("ServerBootFailures", Boot.startFailures)
end)

ReplicatedStorage:SetAttribute("ServerReady", true)
print("[Boot] Server ready")
