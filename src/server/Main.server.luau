--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Boot = require(Shared.Boot)
local Environment = require(Shared.Config.Environment)
local Net = require(Shared.Net)

print(`[Boot] Afterburner server: environment={Environment.get()} role={Environment.placeRole()}`)

Net.Server.init()
Boot.run(script.Parent:WaitForChild("Services"), "Service")

ReplicatedStorage:SetAttribute("ServerReady", true)
print("[Boot] Server ready")
