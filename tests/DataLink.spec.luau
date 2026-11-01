--!strict
-- SNS-08: data link (Shared/Signature).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AircraftData = require(ctx.Shared.AircraftData)
	local Signature = require(ctx.Shared.Signature)

	describe("data link", function()
		it("Tier V and up with a radar have it; older jets don't", function()
			for _, airframe in AircraftData.getAll() do
				local a = airframe :: any
				expect(Signature.hasDataLink(a.Tier, a.Radar)).toBe(a.Tier >= 5 and a.Radar ~= nil)
			end
			expect(Signature.hasDataLink(6, nil)).toBe(false)
		end)

		it("the team sees what any of its data-link jets sees, once each", function()
			local sees = { a = { 10, 11 }, b = { 11, 12 } }
			local picture = Signature.dataLinkPicture({ "a", "b" }, { 10, 11, 12, 13 }, function(tracker, enemy)
				return table.find(sees[tracker], enemy) ~= nil
			end, function(enemy)
				return enemy
			end)
			expect(#picture).toBe(3)
			expect(table.find(picture, 13)).toBe(nil)
		end)

		it("with no data-link jet the team sees nothing", function()
			local picture = Signature.dataLinkPicture({}, { 1, 2 }, function()
				return true
			end, function(enemy)
				return enemy
			end)
			expect(#picture).toBe(0)
		end)
	end)
end
