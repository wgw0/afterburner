--!strict
-- Startup smoke test. Run during a play test (Studio Play, or via the MCP tools):
--   Server: require(game.ServerStorage.Tests.Smoke).server()  --> (ok, report)
--   Client: clients can't see ServerStorage, so run the code in Smoke.clientSource on the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Smoke = {}

local TIMEOUT = 15

local function waitForAttribute(name: string): any
	local deadline = os.clock() + TIMEOUT
	while ReplicatedStorage:GetAttribute(name) == nil and os.clock() < deadline do
		task.wait(0.1)
	end
	return ReplicatedStorage:GetAttribute(name)
end

function Smoke.server(): (boolean, string)
	local ready = waitForAttribute("ServerReady") == true
	task.wait(1) -- give Start functions a moment to fail if they're going to
	local failures = ReplicatedStorage:GetAttribute("ServerBootFailures")
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local ok = ready and failures == 0 and remotes ~= nil
	return ok, `server ready={ready} startFailures={failures} remotes={remotes and #remotes:GetChildren() or "missing"}`
end

-- Paste-able client check (clients can't require from ServerStorage).
Smoke.clientSource = [[
local RS = game:GetService("ReplicatedStorage")
local deadline = os.clock() + 15
while RS:GetAttribute("ClientReady") == nil and os.clock() < deadline do task.wait(0.1) end
task.wait(1)
local ready, failures = RS:GetAttribute("ClientReady") == true, RS:GetAttribute("ClientBootFailures")
return (ready and failures == 0) and "PASS" or "FAIL", ("client ready=%s startFailures=%s"):format(tostring(ready), tostring(failures))
]]

return Smoke
