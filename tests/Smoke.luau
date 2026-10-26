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
	task.wait(2) -- let loops run for a moment so runtime errors show up
	local failures = ReplicatedStorage:GetAttribute("ServerBootFailures")
	local runtime = ReplicatedStorage:GetAttribute("ServerRuntimeErrors")
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local ok = ready and failures == 0 and runtime == 0 and remotes ~= nil
	return ok,
		`server ready={ready} startFailures={failures} runtimeErrors={runtime} remotes={remotes and #remotes:GetChildren() or "missing"}`
end

-- Paste-able client check (clients can't require from ServerStorage).
Smoke.clientSource = [[
local RS = game:GetService("ReplicatedStorage")
local deadline = os.clock() + 15
while RS:GetAttribute("ClientReady") == nil and os.clock() < deadline do task.wait(0.1) end
task.wait(1)
task.wait(2)
local ready, failures, runtime = RS:GetAttribute("ClientReady") == true, RS:GetAttribute("ClientBootFailures"), RS:GetAttribute("ClientRuntimeErrors")
return (ready and failures == 0 and runtime == 0) and "PASS" or "FAIL", ("client ready=%s startFailures=%s runtimeErrors=%s"):format(tostring(ready), tostring(failures), tostring(runtime))
]]

return Smoke
