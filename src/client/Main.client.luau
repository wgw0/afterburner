--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not ReplicatedStorage:GetAttribute("ServerReady") then
	ReplicatedStorage:GetAttributeChangedSignal("ServerReady"):Wait()
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boot = require(Shared.Boot)

-- Client-local attributes (they don't replicate); read by the startup smoke test (tests/Smoke.luau).
ReplicatedStorage:SetAttribute("ClientBootFailures", 0)

Boot.run(script.Parent:WaitForChild("Controllers"), "Controller", function()
	ReplicatedStorage:SetAttribute("ClientBootFailures", Boot.startFailures)
end)

ReplicatedStorage:SetAttribute("ClientReady", true)
print("[Boot] Client ready")
