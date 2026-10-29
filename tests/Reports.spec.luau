--!strict
-- Reporting a cheater (CMP-03).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Reports = require(ctx.Shared.Reports)

	local ME, THEM, NOW = 100, 200, 1000000

	describe("validate", function()
		it("allows a first report with a known reason", function()
			expect((Reports.validate(ME, THEM, "Movement", NOW, nil, {}))).toBe(true)
		end)

		it("refuses yourself, AI pilots and unknown reasons", function()
			expect((Reports.validate(ME, ME, "Movement", NOW, nil, {}))).toBe(false)
			expect((Reports.validate(ME, 0, "Movement", NOW, nil, {}))).toBe(false)
			expect((Reports.validate(ME, -3, "Movement", NOW, nil, {}))).toBe(false)
			expect((Reports.validate(ME, THEM, "Rude", NOW, nil, {}))).toBe(false)
		end)

		it("one report per pilot, and a cooldown between reports", function()
			expect((Reports.validate(ME, THEM, "Weapons", NOW, nil, { [THEM] = true }))).toBe(false)
			local ok, err = Reports.validate(ME, 300, "Weapons", NOW, NOW - 10, {})
			expect(ok).toBe(false)
			expect((err :: string):find("20 s") ~= nil).toBe(true)
			expect((Reports.validate(ME, 300, "Weapons", NOW, NOW - Reports.COOLDOWN, {}))).toBe(true)
		end)
	end)

	describe("add", function()
		it("counts reports and distinct reporters, keeping the newest", function()
			local record = nil
			for i = 1, Reports.KEPT + 5 do
				record = Reports.add(record, { reporter = if i % 2 == 0 then 1 else 2, at = i })
			end
			expect(record.count).toBe(Reports.KEPT + 5)
			expect(record.reporters).toBe(2)
			expect(#record.entries).toBe(Reports.KEPT)
			expect(record.entries[#record.entries].at).toBe(Reports.KEPT + 5)
			expect(record.entries[1].at).toBe(6)
		end)
	end)
end
