--!strict
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not ReplicatedStorage:GetAttribute("ServerReady") then
	ReplicatedStorage:GetAttributeChangedSignal("ServerReady"):Wait()
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boot = require(Shared.Boot)

-- Client-local attributes (they don't replicate); read by the startup smoke test (tests/Smoke.luau).
ReplicatedStorage:SetAttribute("ClientBootFailures", 0)
ReplicatedStorage:SetAttribute("ClientRuntimeErrors", 0)
-- Any error raised by our own client code after boot (e.g. in a RenderStepped loop) is counted too.
LogService.MessageOut:Connect(function(message, messageType)
	if
		messageType == Enum.MessageType.MessageError
		and (string.find(message, ".Client.", 1, true) or string.find(message, "ReplicatedStorage.Shared", 1, true))
	then
		ReplicatedStorage:SetAttribute(
			"ClientRuntimeErrors",
			(ReplicatedStorage:GetAttribute("ClientRuntimeErrors") or 0) + 1
		)
	end
end)

Boot.run(script.Parent:WaitForChild("Controllers"), "Controller", function()
	ReplicatedStorage:SetAttribute("ClientBootFailures", Boot.startFailures)
end)

ReplicatedStorage:SetAttribute("ClientReady", true)
print("[Boot] Client ready")
