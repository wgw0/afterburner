--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not ReplicatedStorage:GetAttribute("ServerReady") then
	ReplicatedStorage:GetAttributeChangedSignal("ServerReady"):Wait()
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boot = require(Shared.Boot)

Boot.run(script.Parent:WaitForChild("Controllers"), "Controller")
print("[Boot] Client ready")
