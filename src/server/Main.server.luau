--!strict
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

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

-- Server step cost (PRF-02): time spent in the services' Heartbeat handlers each frame. One handler is
-- connected before the services start and one after, so between them they bracket the services' work
-- whichever order Roblox fires connections in. Published as ServerStorage attributes once a second.
local edgeA: number?, edgeB: number? = nil, nil
local stepTotal, stepPeak, stepFrames, stepClock = 0, 0, 0, 0
local function recordStep(dt: number)
	if not (edgeA and edgeB) then
		return
	end
	local cost = math.abs(edgeB - edgeA) * 1000
	edgeA, edgeB = nil, nil
	stepTotal += cost
	stepPeak = math.max(stepPeak, cost)
	stepFrames += 1
	stepClock += dt
	if stepClock >= 1 then
		ServerStorage:SetAttribute("ServerStepMs", math.round(stepTotal / stepFrames * 100) / 100)
		ServerStorage:SetAttribute("ServerStepPeakMs", math.round(stepPeak * 100) / 100)
		ServerStorage:SetAttribute("ServerHz", math.round(stepFrames / stepClock * 10) / 10)
		stepTotal, stepPeak, stepFrames, stepClock = 0, 0, 0, 0
	end
end
RunService.PreSimulation:Connect(function()
	edgeA, edgeB = nil, nil
end)
RunService.Heartbeat:Connect(function(dt)
	edgeA = os.clock()
	recordStep(dt)
end)

Net.Server.init()
Boot.run(script.Parent:WaitForChild("Services"), "Service", function()
	ReplicatedStorage:SetAttribute("ServerBootFailures", Boot.startFailures)
end)

RunService.Heartbeat:Connect(function(dt)
	edgeB = os.clock()
	recordStep(dt)
end)

ReplicatedStorage:SetAttribute("ServerReady", true)
print("[Boot] Server ready")
