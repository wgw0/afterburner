--!strict
-- The free spin (Shared/Spin): timing, odds, prizes the player can use, and no dead prizes.
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local PlayerData = require(ctx.Shared.PlayerData)
	local Spin = require(ctx.Shared.Spin)
	local Skins = require(ctx.Shared.Skins)

	local function fresh()
		return PlayerData.template()
	end

	describe("timing", function()
		it("a new account starts with one spin ready", function()
			expect(fresh().Spin.Banked).toBe(1)
		end)

		it("one spin per 20 minutes played, banked up to 3, and the clock stops while full", function()
			local state = { Banked = 0, Progress = 0 }
			expect(Spin.accrue(state, Spin.INTERVAL - 1)).toBe(false)
			expect(Spin.secondsToNext(state)).toBe(1)
			expect(Spin.accrue(state, 1)).toBe(true)
			expect(state.Banked).toBe(1)
			Spin.accrue(state, Spin.INTERVAL)
			Spin.accrue(state, Spin.INTERVAL)
			expect(state.Banked).toBe(Spin.BANK)
			expect(Spin.secondsToNext(state)).toBe(nil)
			expect(Spin.accrue(state, Spin.INTERVAL * 5)).toBe(false)
			expect(state.Banked).toBe(Spin.BANK)
		end)

		it("using a spin from a full bank starts the clock from zero", function()
			local data = fresh()
			data.Spin = { Banked = Spin.BANK, Progress = 0 }
			Spin.take(data, 0, 0)
			expect(data.Spin.Banked).toBe(Spin.BANK - 1)
			expect(Spin.secondsToNext(data.Spin)).toBe(Spin.INTERVAL)
		end)

		it("no spin without one banked", function()
			local data = fresh()
			data.Spin.Banked = 0
			local prize, why = Spin.take(data, 0, 0)
			expect(prize).toBe(nil)
			expect(why ~= nil).toBe(true)
		end)
	end)

	describe("odds", function()
		it("add up to 100%, rarest last, with CS:GO's case odds", function()
			local total, last = 0, math.huge
			for _, tier in Spin.TIERS do
				total += tier.Weight
				expect(tier.Weight < last).toBe(true)
				last = tier.Weight
			end
			expect(math.abs(total - 100) < 1e-9).toBe(true)
			expect(Spin.TIERS[1].Weight).toBe(79.92)
			expect(Spin.TIERS[5].Weight).toBe(0.26)
		end)

		it("rolls land on the right tiers", function()
			expect(Spin.tierFor(0)).toBe(1)
			expect(Spin.tierFor(0.7991)).toBe(1)
			expect(Spin.tierFor(0.80)).toBe(2)
			expect(Spin.tierFor(0.997)).toBe(4) -- Epic ends at 99.74%
			expect(Spin.tierFor(0.9999)).toBe(5)
		end)
	end)

	describe("prizes", function()
		local function tierOf(kind: string): number
			for i, tier in Spin.TIERS do
				if tier.Kind == kind then
					return i
				end
			end
			error(kind)
		end

		it("the Epic prize is half a skin's worth of Wings", function()
			expect(Spin.TIERS[tierOf("Wings")].Amount).toBe(Skins.WINGS_PRICE / 2)
		end)

		it("an upgrade goes on a jet you own, fitted, and is one you didn't have", function()
			local data = fresh()
			local prize = Spin.resolve(data, tierOf("Module"), 0)
			expect(prize.Kind).toBe("Module")
			local entry = data.Aircraft[prize.Airframe :: string]
			expect(entry.Owned).toBe(true)
			expect(entry.Modules[prize.Item :: string]).toBe(nil)
			Spin.apply(data, prize)
			expect(entry.Modules[prize.Item :: string]).toBe(true)
		end)

		it("a skin is a Credits skin (never a default or level skin) for a jet you own", function()
			local data = fresh()
			local prize = Spin.resolve(data, tierOf("Skin"), 0.5)
			expect(prize.Kind).toBe("Skin")
			local skin = Skins.get(prize.Airframe :: string, prize.Item :: string) :: any
			expect(skin.Credits ~= nil and not skin.Default and not skin.Level).toBe(true)
			expect(data.Aircraft[prize.Airframe :: string].Owned).toBe(true)
		end)

		it("no dead prizes: nothing left to give means Credits or Wings instead", function()
			local data = fresh()
			for id, entry in data.Aircraft do
				if entry.Owned then
					entry.Modules = { Engine1 = true, Engine2 = true, Airframe1 = true, Airframe2 = true }
					entry.Modules.Avionics1 = true
					entry.Modules.Countermeasures1 = true
					entry.Skins = {}
					for _, skin in Skins.list(id) do
						entry.Skins[skin.Id] = true
					end
				end
			end
			local upgrade = Spin.resolve(data, tierOf("Module"), 0)
			expect(upgrade.Kind).toBe(Spin.FALLBACK.Module.Kind)
			expect(upgrade.Amount).toBe(Spin.FALLBACK.Module.Amount)
			local skin = Spin.resolve(data, tierOf("Skin"), 0)
			expect(skin.Kind).toBe("Wings")
			expect(skin.Amount).toBe(Skins.WINGS_PRICE)
		end)

		it("a spin grants exactly its prize and uses one spin", function()
			local data = fresh()
			local credits = data.Credits
			local prize = Spin.take(data, 0, 0) :: Spin.Prize
			expect(prize.Kind).toBe("Credits")
			expect(data.Credits).toBe(credits + (prize.Amount :: number))
			expect(data.Spin.Banked).toBe(0)
			expect(prize.Label).toBe("250 Credits")
		end)
	end)
end
