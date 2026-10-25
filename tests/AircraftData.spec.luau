--!strict
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AircraftData = require(ctx.Shared.AircraftData)

	describe("registry", function()
		it("loads the starter jets", function()
			expect(AircraftData.get("F5E") ~= nil).toBe(true)
			expect(AircraftData.get("MiG21bis") ~= nil).toBe(true)
		end)
		it("airframes are frozen (no accidental runtime edits)", function()
			local f5 = AircraftData.get("F5E") :: any
			expect(table.isfrozen(f5)).toBe(true)
		end)
		it("byTier lists tier-1 jets in a stable order", function()
			local tier1 = AircraftData.byTier(1)
			expect(#tier1 >= 2).toBe(true)
			for i = 2, #tier1 do
				expect(tier1[i - 1].Id < tier1[i].Id).toBe(true)
			end
		end)
	end)

	describe("validate", function()
		local function goodCopy(): any
			return table.clone(AircraftData.get("F5E") :: any)
		end

		it("accepts a valid airframe", function()
			expect(#AircraftData.validate("F5E", goodCopy())).toBe(0)
		end)
		it("names the airframe and field when one is missing", function()
			local data = goodCopy()
			data.WingArea = nil
			local problems = AircraftData.validate("F5E", data)
			expect(problems[1]).toBe("F5E: missing WingArea")
		end)
		it("rejects out-of-range numbers, bad enums and NaN", function()
			local data = goodCopy()
			data.MaxG = 40
			data.Branch = "Mars"
			data.CD0 = 0 / 0
			local problems = AircraftData.validate("F5E", data)
			expect(#problems).toBe(3)
		end)
		it("rejects an Id that doesn't match the module name", function()
			local problems = AircraftData.validate("Other", goodCopy())
			expect(#problems).toBe(1)
		end)
		it("rejects afterburner burn lower than dry burn", function()
			local data = goodCopy()
			data.FuelBurnAB = data.FuelBurnDry / 2
			expect(#AircraftData.validate("F5E", data)).toBe(1)
		end)
	end)

	describe("boot behaviour", function()
		it("a broken airframe module stops loading with a clear error naming it", function()
			local folder = Instance.new("Folder")
			ctx.Shared.AircraftData.F5E:Clone().Parent = folder
			local bad = Instance.new("ModuleScript")
			bad.Name = "Broken"
			bad.Source = "return { Id = 'Broken' }"
			bad.Parent = folder
			local ok, err = pcall(AircraftData.load, folder)
			folder:Destroy()
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "Broken: missing WingArea", 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(err), "F5E", 1, true) == nil).toBe(true) -- the good one isn't blamed
		end)
	end)
end
