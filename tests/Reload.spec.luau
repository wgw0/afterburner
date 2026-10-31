--!strict
-- Reloading: an empty store refills after a timer.

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Reload = require(ctx.Shared.Reload)

	describe("reloading", function()
		it("starts a timer only when a store runs dry", function()
			expect(Reload.step(5, 10, nil, 100, 8)).toBe(nil)
			local doneAt, refill = Reload.step(0, 10, nil, 100, 8)
			expect(doneAt).toBe(108)
			expect(refill).toBe(false)
		end)

		it("refills once the timer ends, not before", function()
			local doneAt, refill = Reload.step(0, 10, 108, 107.9, 8)
			expect(doneAt).toBe(108)
			expect(refill).toBe(false)
			doneAt, refill = Reload.step(0, 10, 108, 108, 8)
			expect(doneAt).toBe(nil)
			expect(refill).toBe(true)
		end)

		it("never reloads a store the jet didn't have (Guns Only missiles, no chaff)", function()
			local doneAt, refill = Reload.step(0, 0, nil, 100, 8)
			expect(doneAt).toBe(nil)
			expect(refill).toBe(false)
		end)

		it("reports progress for the HUD bar", function()
			expect(Reload.progress(108, 100, 8)).toBe(0)
			expect(Reload.progress(108, 104, 8)).toBe(0.5)
			expect(Reload.progress(108, 120, 8)).toBe(1)
			expect(Reload.secondsFor("Msl_AIM9P")).toBe(Reload.SECONDS.Missile)
			expect(Reload.secondsFor("Flares")).toBe(Reload.SECONDS.Flares)
		end)
	end)
end
