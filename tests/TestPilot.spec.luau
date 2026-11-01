--!strict
-- LIV-07: the Test Pilot trials and the Tempest unlock (Shared/TestPilot).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local PlayerData = require(ctx.Shared.PlayerData)
	local Progression = require(ctx.Shared.Progression)
	local TechTree = require(ctx.Shared.TechTree)
	local TestPilot = require(ctx.Shared.TestPilot)

	local function tierSeven(): { string }
		local ids = {}
		for _, node in TechTree.NODES do
			if node.Tier == 7 then
				table.insert(ids, node.Id)
			end
		end
		table.sort(ids)
		return ids
	end

	local function pilot(researched: number)
		local data = PlayerData.template()
		for i, id in tierSeven() do
			if i <= researched then
				data.Aircraft[id] = PlayerData.newAircraft(true)
				data.Aircraft[id].RP = 10 ^ 7
			end
		end
		data.FreeRP = 10 ^ 7
		return data
	end

	local function finishAll(data)
		for _, step in TestPilot.STEPS do
			for _ = 1, step.target do
				TestPilot.record(data, { kind = step.event, tier = 7, survived = true })
			end
		end
	end

	it("there are at least two Tier VII jets and the Tempest needs one", function()
		expect(#tierSeven() >= TestPilot.JETS_NEEDED).toBe(true)
		local tempest = TechTree.get(TestPilot.JET) :: any
		expect(tempest ~= nil and #tempest.Requires > 0).toBe(true)
	end)

	it("the trials open only with two Tier VII jets researched", function()
		expect(TestPilot.open(pilot(1))).toBe(false)
		expect(TestPilot.open(pilot(2))).toBe(true)
		local early = pilot(1)
		expect(TestPilot.record(early, { kind = "MatchFinished", tier = 7 })).toBe(nil)
		expect(early.TestPilot.Progress).toBe(0)
	end)

	it("counts only Tier VII jets, and only the current step's event", function()
		local data = pilot(2)
		TestPilot.record(data, { kind = "MatchFinished", tier = 6 })
		TestPilot.record(data, { kind = "Kill", tier = 7 })
		expect(data.TestPilot.Progress).toBe(0)
		TestPilot.record(data, { kind = "MatchFinished", tier = 7 })
		expect(data.TestPilot.Progress).toBe(1)
	end)

	it("runs the steps in order and finishes", function()
		local data = pilot(2)
		local first = TestPilot.STEPS[1]
		for i = 1, first.target - 1 do
			expect(TestPilot.record(data, { kind = first.event, tier = 7 })).toBe(nil)
		end
		expect(TestPilot.record(data, { kind = first.event, tier = 7 })).toBe(first)
		expect(data.TestPilot.Step).toBe(2)
		finishAll(data)
		expect(TestPilot.done(data)).toBe(true)
	end)

	it("the last step needs a match without being shot down", function()
		local data = pilot(2)
		data.TestPilot.Step = #TestPilot.STEPS
		TestPilot.record(data, { kind = "MatchFinished", tier = 7, survived = false })
		expect(TestPilot.done(data)).toBe(false)
		TestPilot.record(data, { kind = "MatchFinished", tier = 7, survived = true })
		expect(TestPilot.done(data)).toBe(true)
	end)

	it("the Tempest can't be researched until the trials are done (full access can)", function()
		local data = pilot(2)
		expect((Progression.researchPlan(data, TestPilot.JET))).toBe(nil)
		finishAll(data)
		expect(Progression.researchPlan(data, TestPilot.JET) ~= nil).toBe(true)
		local admin = pilot(1)
		admin.Flags.AllUnlocked = true
		expect(Progression.researchPlan(admin, TestPilot.JET) ~= nil).toBe(true)
	end)
end
