--!strict
-- SNS-09: a stealth jet's radar cross-section by angle, and with its weapon bays open (Shared/Signature).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AircraftData = require(ctx.Shared.AircraftData)
	local Signature = require(ctx.Shared.Signature)
	local Units = require(ctx.Shared.Units)

	local F22 = AircraftData.get("F22A") :: any
	local target = CFrame.new(0, Units.toStuds(5000), 0) -- flying along -Z
	local ahead = target.Position + target.LookVector * 1000
	local beside = target.Position + target.RightVector * 1000
	local behind = target.Position - target.LookVector * 1000

	describe("radar cross-section", function()
		it("an ordinary jet is the same from every side", function()
			expect(Signature.rcs(nil, target, ahead)).toBe(1)
			expect(Signature.rcs(1, target, beside)).toBe(1)
		end)

		it("a stealth jet is smallest head-on, bigger from behind and biggest from the side", function()
			local front = Signature.rcs(F22.Stealth, target, ahead)
			local rear = Signature.rcs(F22.Stealth, target, behind)
			local side = Signature.rcs(F22.Stealth, target, beside)
			expect(math.abs(front - F22.Stealth) < 1e-9).toBe(true)
			expect(rear > front).toBe(true)
			expect(side > rear).toBe(true)
			expect(side <= 1).toBe(true)
		end)

		it("open weapon bays make it show up for a moment", function()
			local closed = Signature.rcs(F22.Stealth, target, ahead, false)
			local open = Signature.rcs(F22.Stealth, target, ahead, true)
			expect(open >= Signature.BAY_OPEN_RCS).toBe(true)
			expect(open > closed).toBe(true)
			local model = Instance.new("Model")
			model:SetAttribute(Signature.BAY_ATTRIBUTE, 100)
			expect(Signature.bayOpen(model, 99)).toBe(true)
			expect(Signature.bayOpen(model, 101)).toBe(false)
		end)
	end)

	describe("detection", function()
		local radar = { Range = 60000, Cone = 60, CanNotch = true }
		local function seen(stealthRcs: number, rangeMetres: number): boolean
			local radarCF =
				CFrame.lookAt(target.Position + target.LookVector * Units.toStuds(rangeMetres), target.Position)
			return (Signature.radarDetects(radar, radarCF, target.Position, target.LookVector * 250, stealthRcs))
		end

		it("a radar sees a stealth jet from much further when its bays are open", function()
			local head = Signature.rcs(F22.Stealth, target, ahead, false)
			local bays = Signature.rcs(F22.Stealth, target, ahead, true)
			expect(seen(head, 20000)).toBe(false)
			expect(seen(bays, 20000)).toBe(true)
		end)
	end)
end
