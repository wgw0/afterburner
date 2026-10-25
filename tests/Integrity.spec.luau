--!strict
-- Catches broken modules and bad declarations before they turn into startup errors.

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Shared = ctx.Shared
	local Validate = require(Shared.Util.Validate)

	describe("every shared module", function()
		for _, module in Shared:GetDescendants() do
			if module:IsA("ModuleScript") then
				it(`loads: {module:GetFullName()}`, function()
					local ok, err = pcall(require, module)
					if not ok then
						error(err, 0)
					end
				end)
			end
		end
	end)

	describe("Net definitions", function()
		local Definitions = require(Shared.Net.Definitions)
		local directions = { ClientToServer = true, ServerToClient = true, Function = true }

		for name, def in Definitions do
			it(`{name} is well formed`, function()
				expect(directions[def.direction]).toBe(true)
				expect(type(def.args)).toBe("table")
				for i, spec in def.args do
					if not Validate.isKnownSpec(spec) then
						error(`argument {i} has unknown spec "{spec}"`, 0)
					end
				end
				if def.direction == "Function" then
					expect(def.reliable == false).toBe(false) -- RemoteFunctions can't be unreliable
				end
				if def.rate then
					expect(def.rate.burst >= 1).toBe(true)
					expect(def.rate.perSecond > 0).toBe(true)
				end
				if def.direction == "ServerToClient" then
					expect(def.rate).toBe(nil) -- rate limits only apply to client calls
				end
			end)
		end
	end)

	describe("config", function()
		it("Scale values are positive and frozen", function()
			local Scale = require(Shared.Config.Scale)
			for key, value in Scale do
				if type(value) == "number" and not (value > 0) then
					error(`{key} must be positive`, 0)
				end
			end
			expect(table.isfrozen(Scale)).toBe(true)
		end)

		it("Environment resolves to a known value", function()
			local Environment = require(Shared.Config.Environment)
			expect(Environment.get() == "Test" or Environment.get() == "Prod").toBe(true)
			local role = Environment.placeRole()
			expect(role == "Single" or role == "Lobby" or role == "Battle").toBe(true)
		end)
	end)
end
