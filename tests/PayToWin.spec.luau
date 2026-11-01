--!strict
-- SHP-06: never pay-to-win (DESIGN §8.1, §8.3; DEVELOPMENT.md §27.4). Premium jets copy a free jet's stats
-- and can't change them, and nothing sold grants modules, performance or a top-tier jet.
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AircraftData = require(ctx.Shared.AircraftData)
	local Catalogue = require(ctx.Shared.Config.Cosmetics)
	local Products = require(ctx.Shared.Config.Products)
	local TechTree = require(ctx.Shared.TechTree)

	local function premium(fields: { [string]: any }): { [string]: any }
		local data = { Id = "F4ENightOwl", DisplayName = "F-4E Night Owl", StatsFrom = "F4E", ModelName = "F4E" }
		for k, v in fields do
			data[k] = v
		end
		return data
	end

	describe("premium jets", function()
		it("get every stat, the tier and the BR from their free jet", function()
			local base = AircraftData.get("F4E") :: any
			local full, problems = AircraftData.resolvePremium("F4ENightOwl", premium({}), base)
			expect(#problems).toBe(0)
			for field, value in base do
				if field ~= "Id" and field ~= "DisplayName" then
					expect(full[field]).toBe(value)
				end
			end
			expect(full.DisplayName).toBe("F-4E Night Owl")
			expect(#AircraftData.validate("F4ENightOwl", full)).toBe(0)
		end)

		it("can't set a stat, the tier or the BR of their own", function()
			local base = AircraftData.get("F4E")
			for _, field in { "MaxThrust", "MaxG", "Tier", "BattleRating", "Missiles", "Radar" } do
				local full, problems = AircraftData.resolvePremium("F4ENightOwl", premium({ [field] = 1 }), base)
				expect(full).toBe(nil)
				expect(#problems).toBe(1)
			end
		end)

		it("must name a free airframe that exists", function()
			local _, missing = AircraftData.resolvePremium("X", premium({ StatsFrom = "F99" }), nil)
			expect(#missing).toBe(1)
			local _, chained = AircraftData.resolvePremium("X", premium({ StatsFrom = "F4ENightOwl" }), premium({}))
			expect(#chained).toBe(1)
		end)

		it("a broken premium jet stops loading with a clear error", function()
			local folder = Instance.new("Folder")
			ctx.Shared.AircraftData.F4E:Clone().Parent = folder
			local module = Instance.new("ModuleScript")
			module.Name = "F4ENightOwl"
			module.Source = 'return { Id = "F4ENightOwl", DisplayName = "Night Owl", StatsFrom = "F4E", MaxG = 12 }'
			module.Parent = folder
			local ok, err = pcall(AircraftData.load, folder)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "F4ENightOwl", 1, true) ~= nil).toBe(true)
		end)

		it("aren't in the tech tree (they're never researched or bought with Credits)", function()
			for id, airframe in AircraftData.getAll() do
				if (airframe :: any).StatsFrom then
					expect(TechTree.get(id)).toBe(nil)
				end
			end
		end)
	end)

	describe("nothing sold is power", function()
		it(
			"products grant only Wings, boosters, Tier Unlocks up to Tier V, the season pass or the starter bundle",
			function()
				local allowed = { Wings = true, Booster = true, TierUnlock = true, SeasonPass = true, Starter = true }
				for _, product in Products.LIST do
					expect(allowed[product.Kind]).toBe(true)
					if product.Kind == "TierUnlock" then
						expect((product.Tier :: number) <= Products.MAX_UNLOCK_TIER).toBe(true)
					end
				end
			end
		)

		it("cosmetics carry only looks: no field that could change a jet", function()
			local looks = {
				Kind = true,
				DisplayName = true,
				Wings = true,
				Pass = true,
				Season = true,
				Colours = true,
				Glyph = true,
				Colour = true,
				Images = true,
				Skin = true,
				Order = true,
			}
			for id, item in Catalogue.LIST do
				for field in item :: any do
					if not looks[field] then
						error(`{id} has {field}, which isn't a look`)
					end
				end
			end
		end)
	end)
end
