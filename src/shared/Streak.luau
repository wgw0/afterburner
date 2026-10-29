--!strict
-- Daily login rewards (DESIGN §10, LIV-03). Pure: ChallengeService claims, the menu shows the week.
--   Each UTC day you open the game you can claim the next day of your streak. The rewards run in weeks of 7
--   (WEEK); day 7 of every week is the big one. Reaching day 7 the first time unlocks the title Regular, and
--   day 30 unlocks Devoted with a bonus.
--   Never harsh on a missed day: missing one day is forgiven (the streak carries on); missing more takes you
--   back to the first day of the week you were in, not to day 1.
-- Saved per player as data.Streak = { Day = UTC day of the last claim (0 = never), Count, Best }.

local Streak = {}

export type State = { Day: number, Count: number, Best: number }
export type Reward = { credits: number, freeRP: number, title: string? }

Streak.WEEK = table.freeze({
	{ credits = 250, freeRP = 0 },
	{ credits = 350, freeRP = 0 },
	{ credits = 450, freeRP = 0 },
	{ credits = 600, freeRP = 0 },
	{ credits = 750, freeRP = 0 },
	{ credits = 1000, freeRP = 0 },
	{ credits = 1500, freeRP = 500 },
})
-- Milestones (once, the first time the streak reaches them): a title, and Credits on top
Streak.MILESTONES = table.freeze({
	[7] = { title = "Regular", credits = 0 },
	[30] = { title = "Devoted", credits = 5000 },
})
Streak.GRACE_DAYS = 1 -- missed days that don't break the streak

function Streak.newState(): State
	return { Day = 0, Count = 0, Best = 0 }
end

-- Where a streak count sits in its week (1..7).
function Streak.weekDay(count: number): number
	return (math.max(count, 1) - 1) % #Streak.WEEK + 1
end

-- Whether today's reward is still to claim.
function Streak.canClaim(state: State, today: number): boolean
	return state.Day < today
end

-- The streak count today's claim would make.
function Streak.nextCount(state: State, today: number): number
	if state.Day == 0 or state.Count <= 0 then
		return 1
	end
	local gap = today - state.Day -- 1 = claimed yesterday
	if gap <= 1 + Streak.GRACE_DAYS then
		return state.Count + 1
	end
	-- A longer break: back to the first day of the week you were in (never below day 1)
	return state.Count - Streak.weekDay(state.Count) + 1
end

-- The reward for reaching `count`, given the best streak before this claim (milestones pay once).
function Streak.reward(count: number, best: number): Reward
	local day = Streak.WEEK[Streak.weekDay(count)]
	local reward: Reward = { credits = day.credits, freeRP = day.freeRP, title = nil }
	local milestone = Streak.MILESTONES[count]
	if milestone and best < count then
		reward.credits += milestone.credits
		reward.title = milestone.title
	end
	return reward
end

-- Claims today: moves the streak on and returns the reward, or nil if today's is already claimed.
function Streak.claim(state: State, today: number): (Reward?, number)
	if not Streak.canClaim(state, today) then
		return nil, state.Count
	end
	local count = Streak.nextCount(state, today)
	local reward = Streak.reward(count, state.Best)
	state.Day = today
	state.Count = count
	state.Best = math.max(state.Best, count)
	return reward, count
end

return Streak
