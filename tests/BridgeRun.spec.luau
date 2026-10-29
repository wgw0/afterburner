--!strict
-- Flying under a bridge (the Threading the Needle bonus).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local BridgeRun = require(ctx.Shared.BridgeRun)

	local function pass(y: number, z: number): boolean
		return BridgeRun.passedUnder(Vector3.new(-30, y, z), Vector3.new(30, y, z))
	end

	describe("the deck", function()
		it("is highest at midspan and lowest at the ends", function()
			expect(BridgeRun.clearance(0)).toBe(BridgeRun.ROAD_MID - BridgeRun.GIRDER)
			expect(BridgeRun.clearance(BridgeRun.END_Z)).toBe(BridgeRun.ROAD_END - BridgeRun.GIRDER)
			expect(BridgeRun.clearance(300) > BridgeRun.clearance(600)).toBe(true)
		end)
	end)

	describe("passing under", function()
		it("under the main span counts", function()
			expect(pass(20, 0)).toBe(true)
			expect(pass(20, 300)).toBe(true)
			expect(pass(20, -300)).toBe(true)
		end)

		it("over the deck doesn't", function()
			expect(pass(60, 0)).toBe(false)
			expect(pass(BridgeRun.clearance(300) + 1, 300)).toBe(false)
		end)

		it("under a side span counts, but not at a tower or past the anchorages", function()
			expect(pass(10, 650)).toBe(true)
			expect(pass(10, BridgeRun.TOWER_Z)).toBe(false)
			expect(pass(10, BridgeRun.ANCHOR_Z + 20)).toBe(false)
		end)

		it("it has to cross the bridge's line", function()
			expect(BridgeRun.passedUnder(Vector3.new(-60, 20, 0), Vector3.new(-5, 20, 0))).toBe(false)
			-- either way across
			expect(BridgeRun.passedUnder(Vector3.new(40, 20, 100), Vector3.new(-40, 20, 100))).toBe(true)
		end)

		it("the crossing point is what counts, not either end", function()
			-- Diving across: high on one side, low on the other; under the deck where it crosses
			expect(BridgeRun.passedUnder(Vector3.new(-40, 80, 0), Vector3.new(40, 0, 0))).toBe(true)
			-- Climbing across over the deck
			expect(BridgeRun.passedUnder(Vector3.new(-40, 60, 0), Vector3.new(40, 120, 0))).toBe(false)
		end)
	end)
end
