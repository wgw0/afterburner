--!strict
-- Flare programmes (CMS-04).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Countermeasures = require(ctx.Shared.Countermeasures)
	local AircraftData = require(ctx.Shared.AircraftData)
	local Settings = require(ctx.Shared.Config.Settings)

	describe("programme", function()
		it("from Tier V only", function()
			expect(Countermeasures.hasProgramme(4)).toBe(false)
			expect(Countermeasures.hasProgramme(5)).toBe(true)
			expect(Countermeasures.hasProgramme(8)).toBe(true)
		end)

		it("is a short burst: every Tier V+ jet gets several defences from its flares", function()
			local p = Countermeasures.PROGRAMME
			local perProgramme = p.salvos * p.perSalvo
			expect(perProgramme <= 6).toBe(true)
			expect((p.salvos - 1) * p.interval <= 1).toBe(true)
			for id, airframe in AircraftData.getAll() do
				local a = airframe :: any
				if Countermeasures.hasProgramme(a.Tier) then
					local flares = a.Countermeasures and a.Countermeasures.Flares or 0
					if flares // perProgramme < 5 then
						error(`{id} carries only {flares} flares: {flares // perProgramme} programmes`)
					end
				end
			end
		end)
	end)

	describe("automatic", function()
		it("fires about AUTO_TIME before a closing missile arrives, never for one going away", function()
			expect(Countermeasures.autoDue(3000, 800)).toBe(false) -- 3.75 s out
			expect(Countermeasures.autoDue(1500, 800)).toBe(true) -- 1.9 s out
			expect(Countermeasures.autoDue(500, -50)).toBe(false) -- falling behind
			expect(Countermeasures.autoDue(500, 0)).toBe(false)
		end)

		it("is a setting, on by default", function()
			expect(Settings.defaults().AutoFlares).toBe(true)
		end)
	end)
end
