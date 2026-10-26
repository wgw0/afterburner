--!strict
-- A short history of one jet's pose, for lag compensation (DEVELOPMENT.md §11.4).
-- The server records every jet each tick; when it checks a shooter's bullets it looks the targets up
-- where the shooter saw them (now minus the shooter's latency).

local RingBuffer = require(script.Parent.Util.RingBuffer)

export type Pose = { time: number, cframe: CFrame }

local PoseHistory = {}
PoseHistory.__index = PoseHistory

export type PoseHistory = typeof(setmetatable({} :: { buffer: RingBuffer.RingBuffer<Pose> }, PoseHistory))

function PoseHistory.new(capacity: number?): PoseHistory
	return setmetatable({ buffer = RingBuffer.new(capacity or 90) }, PoseHistory)
end

function PoseHistory.record(self: PoseHistory, time: number, cframe: CFrame)
	self.buffer:push({ time = time, cframe = cframe })
end

-- The interpolated pose at `time`, clamped to the oldest/newest recorded pose. nil if empty.
function PoseHistory.sample(self: PoseHistory, time: number): CFrame?
	local older, newer, alpha = self.buffer:findBracket(time)
	if not older then
		return nil
	end
	if older == newer then
		return older.cframe
	end
	return older.cframe:Lerp(newer.cframe, alpha)
end

function PoseHistory.newestTime(self: PoseHistory): number?
	local newest = self.buffer:at(1)
	return newest and newest.time
end

return PoseHistory
