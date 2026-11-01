--!strict
-- The Test Pilot trials (LIV-07; DESIGN §6.2): the way to the Tempest. They open once a pilot has
-- researched two Tier VII jets, then run as five steps in order, each counted only in a Tier VII jet in
-- scored matches (the same events as the challenges, Challenges.matches). Each step pays its Credits and XP;
-- finishing the last makes the Tempest researchable (Progression.researchPlan). Saved as
-- data.TestPilot = { Step, Progress } (Step past the last = done). Full access skips all of it. Pure.

local Challenges = require(script.Parent.Challenges)
local TechTree = require(script.Parent.TechTree)

local TestPilot = {}

TestPilot.JET = "Tempest"
TestPilot.TIER = 7 -- the tier the trials are flown in
TestPilot.JETS_NEEDED = 2 -- Tier VII jets researched before the trials open

local SEVEN = { minTier = 7 }

TestPilot.STEPS = table.freeze({
	{
		id = "TP1",
		text = "Shakedown flights: finish 5 matches in a Tier VII jet",
		event = "MatchFinished",
		target = 5,
		credits = 10000,
		xp = 500,
		filter = SEVEN,
	},
	{
		id = "TP2",
		text = "Weapons trials: shoot down 10 jets in a Tier VII jet",
		event = "Kill",
		target = 10,
		credits = 15000,
		xp = 750,
		filter = SEVEN,
	},
	{
		id = "TP3",
		text = "Evasion trials: defeat 5 missiles in a Tier VII jet",
		event = "MissileDefeated",
		target = 5,
		credits = 15000,
		xp = 750,
		filter = SEVEN,
	},
	{
		id = "TP4",
		text = "Combat evaluation: win 3 matches in a Tier VII jet",
		event = "Win",
		target = 3,
		credits = 20000,
		xp = 1000,
		filter = SEVEN,
	},
	{
		id = "TP5",
		text = "Final sortie: finish a match in a Tier VII jet without being shot down",
		event = "MatchFinished",
		target = 1,
		credits = 25000,
		xp = 1500,
		filter = { minTier = 7, survived = true },
	},
}) :: { Challenges.Def }

function TestPilot.newState(): { [string]: any }
	return { Step = 1, Progress = 0 }
end

local function state(data: { [string]: any }): { [string]: any }
	if type(data.TestPilot) ~= "table" then
		data.TestPilot = TestPilot.newState()
	end
	return data.TestPilot
end

-- Tier VII jets the pilot has researched.
function TestPilot.jetsResearched(data: { [string]: any }): number
	local count = 0
	for _, node in TechTree.NODES do
		local entry = data.Aircraft and data.Aircraft[node.Id]
		if node.Tier == TestPilot.TIER and entry and entry.Researched then
			count += 1
		end
	end
	return count
end

-- Whether the trials have opened (two Tier VII jets researched).
function TestPilot.open(data: { [string]: any }): boolean
	return TestPilot.jetsResearched(data) >= TestPilot.JETS_NEEDED
end

function TestPilot.done(data: { [string]: any }): boolean
	local s = data.TestPilot
	return type(s) == "table" and type(s.Step) == "number" and s.Step > #TestPilot.STEPS
end

-- The step to fly now and its progress, or nil once done.
function TestPilot.current(data: { [string]: any }): (Challenges.Def?, number)
	local s = state(data)
	return TestPilot.STEPS[s.Step], s.Progress or 0
end

-- Counts a scored-match event toward the current step (only once the trials are open). Returns the step it
-- just finished, or nil.
function TestPilot.record(data: { [string]: any }, event: Challenges.Event): Challenges.Def?
	if not TestPilot.open(data) or TestPilot.done(data) then
		return nil
	end
	local s = state(data)
	local step = TestPilot.STEPS[s.Step]
	if not step or not Challenges.matches(step, event) then
		return nil
	end
	s.Progress = (s.Progress or 0) + 1
	if s.Progress < step.target then
		return nil
	end
	s.Step += 1
	s.Progress = 0
	return step
end

-- Whether the Tempest can be researched yet, and why not.
function TestPilot.canResearch(data: { [string]: any }): (boolean, string?)
	if data.Flags and data.Flags.AllUnlocked == true then
		return true, nil
	elseif not TestPilot.open(data) then
		return false, `Research {TestPilot.JETS_NEEDED} Tier VII jets to start the Test Pilot trials`
	elseif not TestPilot.done(data) then
		return false, "Finish the Test Pilot trials first"
	end
	return true, nil
end

return TestPilot
