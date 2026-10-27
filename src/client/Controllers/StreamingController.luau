--!strict
-- Reports this client's frame rate to the server once a second while the map warms up
-- (StreamingService), so the next area is only sent once the last one has been taken in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local REPORT_FOR = 600 -- seconds; the warm-up is long finished by then

local StreamingController = {
	Priority = 95,
}

function StreamingController:Start()
	local frames = 0
	local connection = RunService.RenderStepped:Connect(function()
		frames += 1
	end)
	task.spawn(function()
		local started = os.clock()
		local last = os.clock()
		while os.clock() - started < REPORT_FOR do
			task.wait(1)
			local now = os.clock()
			Net.Client.fire("StreamPace", math.round(frames / (now - last)))
			frames, last = 0, now
		end
		connection:Disconnect()
	end)
end

return StreamingController
