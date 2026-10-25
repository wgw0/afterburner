--!strict
-- Every airframe must have a model in ReplicatedStorage.Assets.Aircraft that follows the contract.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AircraftData = require(ctx.Shared.AircraftData)
	local Contract = require(ctx.Shared.AircraftModelContract)

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Aircraft")

	describe("aircraft models", function()
		it("the Assets.Aircraft folder exists", function()
			expect(folder ~= nil).toBe(true)
		end)

		for id, airframe in AircraftData.getAll() do
			it(`{id} has a model that passes the contract`, function()
				local model = folder and folder:FindFirstChild(airframe.ModelName)
				if not model then
					error(`missing model {airframe.ModelName}`, 0)
				end
				local problems = Contract.validate(model)
				if #problems > 0 then
					error(table.concat(problems, "\n      "), 0)
				end
			end)
		end
	end)

	describe("contract validator", function()
		it("catches a broken model", function()
			local source = folder and folder:FindFirstChild("F5E")
			if not source then
				error("F5E model missing", 0)
			end
			local broken = source:Clone()
			broken.Hitboxes.Tail:Destroy()
			broken.Root.GunMuzzle:Destroy()
			Instance.new("Script").Parent = broken
			broken.WingL.CanCollide = true
			local problems = Contract.validate(broken)
			broken:Destroy()
			local text = table.concat(problems, "\n")
			expect(string.find(text, "missing hitbox Tail", 1, true) ~= nil).toBe(true)
			expect(string.find(text, "missing attachment GunMuzzle", 1, true) ~= nil).toBe(true)
			expect(string.find(text, "contains a script", 1, true) ~= nil).toBe(true)
			expect(string.find(text, "WingL must have CanCollide", 1, true) ~= nil).toBe(true)
		end)
	end)
end
