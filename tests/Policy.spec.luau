--!strict
-- CMP-02: reading Roblox's policy answer (Shared/Policy).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Policy = require(ctx.Shared.Policy)

	describe("Policy.read", function()
		it("allows only what Roblox explicitly allows", function()
			local rules = Policy.read({
				ArePaidRandomItemsRestricted = false,
				AllowedExternalLinkReferences = { "Discord", "YouTube" },
				IsPaidItemTradingAllowed = true,
			})
			expect(rules.PaidRandomItems).toBe(true)
			expect(rules.PaidTrading).toBe(true)
			expect(Policy.linkAllowed(rules, "Discord")).toBe(true)
			expect(Policy.linkAllowed(rules, "Twitter")).toBe(false)
		end)

		it("treats a missing or odd answer as strict", function()
			for _, info in { nil, "nope", {}, { ArePaidRandomItemsRestricted = "no" } } :: { any } do
				local rules = Policy.read(info)
				expect(rules.PaidRandomItems).toBe(false)
				expect(rules.PaidTrading).toBe(false)
				expect(#rules.Links).toBe(0)
			end
		end)
	end)

	describe("on a player", function()
		it("is strict until checked, then shows what was read", function()
			local player = Instance.new("Folder")
			expect(Policy.of(player).PaidRandomItems).toBe(false)
			Policy.show(player, Policy.read({ ArePaidRandomItemsRestricted = false }), false)
			expect(Policy.of(player).PaidRandomItems).toBe(false) -- not checked yet
			Policy.show(
				player,
				Policy.read({ ArePaidRandomItemsRestricted = false, AllowedExternalLinkReferences = { "Discord" } }),
				true
			)
			expect(Policy.of(player).PaidRandomItems).toBe(true)
			expect(Policy.linkAllowed(Policy.of(player), "Discord")).toBe(true)
		end)
	end)
end
