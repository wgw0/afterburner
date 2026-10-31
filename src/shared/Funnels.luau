--!strict
-- The analytics funnels' steps (DEVELOPMENT.md §30.3). Roblox's funnel charts treat a logged step as having
-- completed every step before it, so a step is only logged once all the steps before it have been reached.

local Funnels = {}

-- The one-time onboarding funnel (AnalyticsService:LogOnboardingFunnelStepEvent), in order. Training is
-- optional (a new pilot can skip it), so its lessons have a funnel of their own.
Funnels.ONBOARDING = table.freeze({ "Joined", "Onboarded", "FirstMatch", "FirstKill", "FirstResearch" })

-- The training funnel (LogFunnelStepEvent "Training"): arriving on a training server, then lessons 1–6.
Funnels.TRAINING_NAME = "Training"
Funnels.TRAINING = table.freeze({ "Arrived", "Flight", "Energy", "Guns", "Missiles", "Defend", "Fight" })

local function reachedPrefix(steps: { string }, reached: { [string]: any }): number
	local n = 0
	while steps[n + 1] and reached[steps[n + 1]] do
		n += 1
	end
	return n
end

-- Marks step `name` reached in `reached` (the save's data.Onboarding) and returns the step numbers to log
-- now: those whose earlier steps are all reached and that weren't logged before. A step reached early
-- (a kill before the first match is over) waits for the steps before it.
function Funnels.reach(reached: { [string]: any }, name: string): { number }
	local steps = Funnels.ONBOARDING :: { string }
	if not table.find(steps, name) or reached[name] then
		return {}
	end
	local before = reachedPrefix(steps, reached)
	reached[name] = true
	local log = {}
	for step = before + 1, reachedPrefix(steps, reached) do
		table.insert(log, step)
	end
	return log
end

return Funnels
