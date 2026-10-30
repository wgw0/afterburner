--!strict
-- SHP-07: cosmetics bought with Wings (Shared/Cosmetics, Config/Cosmetics): buying, equipping, pass items,
-- and that the catalogue stays cosmetic and priced.
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Catalogue = require(ctx.Shared.Config.Cosmetics)
	local Cosmetics = require(ctx.Shared.Cosmetics)
	local PlayerData = require(ctx.Shared.PlayerData)

	local function fresh()
		local data = PlayerData.template()
		data.Wings = 1000
		return data
	end

	describe("buying", function()
		it("costs its Wings, owns it and equips it", function()
			local data = fresh()
			expect(Cosmetics.buy(data, "TrailRed")).toBe(true)
			expect(data.Wings).toBe(1000 - (Catalogue.LIST.TrailRed.Wings :: number))
			expect(Cosmetics.owns(data, "TrailRed")).toBe(true)
			expect(Cosmetics.equipped(data, "Trail")).toBe("TrailRed")
		end)

		it("won't buy twice, without the Wings, or something unknown", function()
			local data = fresh()
			Cosmetics.buy(data, "HUDGold")
			local ok, err = Cosmetics.buy(data, "HUDGold")
			expect(ok).toBe(false)
			expect(err).toBe("You already own that")
			data.Wings = 10
			expect((Cosmetics.buy(data, "NoseShark"))).toBe(false)
			expect(data.Wings).toBe(10)
			expect((Cosmetics.buy(data, "Nope"))).toBe(false)
		end)

		it("pass items can't be bought; they come with the pass", function()
			local data = fresh()
			expect((Cosmetics.buy(data, "TrailVIP"))).toBe(false)
			expect(Cosmetics.owns(data, "TrailVIP")).toBe(false)
			data.Passes.VIP = true
			expect(Cosmetics.owns(data, "TrailVIP")).toBe(true)
			expect(Cosmetics.equip(data, "Trail", "TrailVIP")).toBe(true)
			expect(Cosmetics.equipped(data, "Trail")).toBe("TrailVIP")
			-- the pass lapses: it stops showing
			data.Passes.VIP = nil
			expect(Cosmetics.equipped(data, "Trail")).toBe(nil)
		end)
	end)

	describe("equipping", function()
		it('only owned items, only in their own slot; "" takes it off', function()
			local data = fresh()
			expect((Cosmetics.equip(data, "Marker", "MarkerGold"))).toBe(false)
			Cosmetics.buy(data, "MarkerGold")
			expect((Cosmetics.equip(data, "HUD", "MarkerGold"))).toBe(false)
			expect((Cosmetics.equip(data, "Wheels", ""))).toBe(false)
			expect(Cosmetics.equip(data, "Marker", "")).toBe(true)
			expect(Cosmetics.equipped(data, "Marker")).toBe(nil)
			expect(Cosmetics.equip(data, "Marker", "MarkerGold")).toBe(true)
			expect(Cosmetics.equipped(data, "Marker")).toBe("MarkerGold")
		end)

		it("full access owns everything", function()
			local data = fresh()
			data.Flags.AllUnlocked = true
			for id in Catalogue.LIST do
				expect(Cosmetics.owns(data, id)).toBe(true)
			end
		end)

		it("an old save without the new fields loads with them", function()
			local data = fresh()
			data.Cosmetics = { Camos = {}, Trails = {}, KillMarkers = {} }
			PlayerData.reconcile(data)
			expect(type(data.Cosmetics.Owned)).toBe("table")
			expect(type(data.Cosmetics.Equipped)).toBe("table")
			expect(Cosmetics.buy(data, "TrailBlue")).toBe(true)
		end)
	end)

	describe("catalogue", function()
		it("every item has a kind, a price or a pass, and what its kind needs", function()
			for id, item in Catalogue.LIST do
				expect(table.find(Catalogue.KINDS, item.Kind) ~= nil).toBe(true)
				expect(item.Wings ~= nil or item.Pass ~= nil).toBe(true)
				if item.Wings then
					expect(item.Wings >= 100 and item.Wings <= 600).toBe(true)
				end
				if item.Kind == "Trail" or item.Kind == "HUD" then
					expect(item.Colours ~= nil and #item.Colours >= 1).toBe(true)
				elseif item.Kind == "Marker" then
					expect(item.Glyph ~= nil and item.Colour ~= nil).toBe(true)
				elseif item.Kind == "NoseArt" then
					expect(item.Images ~= nil and #item.Images == 2).toBe(true)
					expect(Cosmetics.ready(id)).toBe(true)
				end
			end
		end)

		it("cosmetics are replicated to their owner", function()
			expect(table.find(PlayerData.REPLICATED, "Cosmetics") ~= nil).toBe(true)
		end)
	end)
end
