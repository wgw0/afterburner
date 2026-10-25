--!strict
-- Test-environment diagnostics: answers DebugPing/DebugEcho and logs every dropped remote call,
-- so the Net layer's validation and rate limiting can be checked end to end.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Environment = require(Shared.Config.Environment)
local Net = require(Shared.Net)

local SUMMARY_INTERVAL = 5

local DiagnosticsService = {
	Priority = 10,
	accepted = 0,
	dropped = 0,
}

-- Dropped calls are summarised every few seconds, so a client spamming bad calls can't flood the log.
local pending: { [string]: number } = {}

local function flushDropped()
	for key, count in pending do
		warn(`[Net] Dropped {key} x{count}`)
	end
	table.clear(pending)
end

function DiagnosticsService:Init()
	Net.Server.Dropped:Connect(function(player: Player, name: string, reason: string?)
		self.dropped += 1
		local key = `{name} from {player.Name} ({player.UserId}): {reason}`
		pending[key] = (pending[key] or 0) + 1
	end)

	if not Environment.isTest() then
		return
	end

	Net.Server.on("DebugPing", function(player: Player, sequence: number)
		self.accepted += 1
		Net.Server.fire("DebugPong", player, sequence, workspace:GetServerTimeNow())
	end)

	Net.Server.handle("DebugEcho", function(_player: Player, text: string)
		return string.upper(text)
	end)
end

function DiagnosticsService:Start()
	while true do
		task.wait(SUMMARY_INTERVAL)
		flushDropped()
	end
end

return DiagnosticsService
