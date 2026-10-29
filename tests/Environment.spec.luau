--!strict
-- Test or Prod from the experience (REL-04): publishing to production needs no switch.

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Environment = require(ctx.Shared.Config.Environment)
	local Version = require(ctx.Shared.Version)

	local TEST = Environment.TEST_UNIVERSES[1]
	local OTHER = 123456

	describe("resolve", function()
		it("live: the test experience is Test, any other is Prod, whatever the attribute says", function()
			expect(Environment.resolve(TEST, false, nil)).toBe("Test")
			expect(Environment.resolve(OTHER, false, nil)).toBe("Prod")
			expect(Environment.resolve(OTHER, false, "Test")).toBe("Prod")
			expect(Environment.resolve(TEST, false, "Prod")).toBe("Test")
		end)

		it("Studio is Test unless the attribute asks for Prod", function()
			expect(Environment.resolve(OTHER, true, nil)).toBe("Test")
			expect(Environment.resolve(TEST, true, "Test")).toBe("Test")
			expect(Environment.resolve(TEST, true, "Prod")).toBe("Prod")
		end)
	end)

	describe("version", function()
		it("is a plain semantic version, labelled with the environment off production", function()
			expect(Version.valid(Version.NUMBER)).toBe(true)
			expect(Version.valid("1.2")).toBe(false)
			expect(Version.label("Prod")).toBe(`v{Version.NUMBER}`)
			expect(Version.label("Test")).toBe(`v{Version.NUMBER} · Test`)
		end)
	end)
end
