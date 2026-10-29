--!strict
-- Key and button bindings (INP-05).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Bindings = require(ctx.Shared.Config.Bindings)
	local Settings = require(ctx.Shared.Config.Settings)

	describe("defaults", function()
		it("every action has a unique id and a known group", function()
			local seen = {}
			for _, action in Bindings.ACTIONS do
				expect(seen[action.id]).toBe(nil)
				seen[action.id] = true
				expect(table.find(Bindings.GROUPS, action.group) ~= nil).toBe(true)
			end
		end)

		it("default keys are valid and no two flight actions share one", function()
			local keys, pads = {}, {}
			for _, action in Bindings.ACTIONS do
				if action.keyboard then
					expect(Bindings.validKeyboard(action.keyboard)).toBe(true)
				end
				if action.gamepad then
					expect(Bindings.validGamepad(action.gamepad)).toBe(true)
				end
				if action.id ~= "FlyAgain" then -- menu only, may share with a flight key
					if action.keyboard then
						expect(keys[action.keyboard]).toBe(nil)
						keys[action.keyboard] = true
					end
					if action.gamepad then
						expect(pads[action.gamepad]).toBe(nil)
						pads[action.gamepad] = true
					end
				end
			end
		end)

		it("with no overrides, an action resolves to its default", function()
			expect(Bindings.resolve({}, "FireMissile", "keyboard")).toBe("Space")
			expect(Bindings.resolve({}, "FireMissile", "gamepad")).toBe("ButtonX")
			expect(Bindings.resolve({}, "ThrottleUp", "gamepad")).toBe(nil)
		end)
	end)

	describe("what may be bound", function()
		it("keyboard: keys and mouse buttons, not gamepad buttons or reserved keys", function()
			expect(Bindings.validKeyboard("G")).toBe(true)
			expect(Bindings.validKeyboard("MouseButton2")).toBe(true)
			expect(Bindings.validKeyboard("None")).toBe(true)
			expect(Bindings.validKeyboard("ButtonA")).toBe(false)
			expect(Bindings.validKeyboard("Escape")).toBe(false)
			expect(Bindings.validKeyboard("Up")).toBe(false)
			expect(Bindings.validKeyboard("NotAKey")).toBe(false)
			expect(Bindings.validKeyboard(5)).toBe(false)
		end)

		it("gamepad: buttons only, not sticks or triggers", function()
			expect(Bindings.validGamepad("ButtonY")).toBe(true)
			expect(Bindings.validGamepad("DPadRight")).toBe(true)
			expect(Bindings.validGamepad("ButtonR2")).toBe(false)
			expect(Bindings.validGamepad("Thumbstick1")).toBe(false)
			expect(Bindings.validGamepad("Space")).toBe(false)
		end)

		it("a saved Bindings value with unknown actions or fields is rejected", function()
			expect(Bindings.valid({ FireMissile = { keyboard = "G" } })).toBe(true)
			expect(Bindings.valid({ Teleport = { keyboard = "G" } })).toBe(false)
			expect(Bindings.valid({ FireMissile = { mouse = "G" } })).toBe(false)
			expect(Bindings.valid({ FireMissile = { gamepad = "Space" } })).toBe(false)
			expect(Bindings.valid("Space")).toBe(false)
			-- and the settings layer uses it
			expect(Settings.valid("Bindings", { Flares = { keyboard = "G" } })).toBe(true)
			expect(Settings.valid("Bindings", { Flares = { keyboard = "Escape" } })).toBe(false)
			expect(next(Settings.defaults().Bindings)).toBe(nil)
		end)
	end)

	describe("assigning", function()
		it("binds a free key", function()
			local result, swapped = Bindings.assign({}, "FireMissile", "keyboard", "G")
			expect(Bindings.resolve(result, "FireMissile", "keyboard")).toBe("G")
			expect(swapped).toBe(nil)
		end)

		it("a key already in use swaps with the other action", function()
			-- Flares (F) onto C, which Chaff has: Chaff gets F
			local result, swapped = Bindings.assign({}, "Flares", "keyboard", "C")
			expect(swapped).toBe("Chaff")
			expect(Bindings.resolve(result, "Flares", "keyboard")).toBe("C")
			expect(Bindings.resolve(result, "Chaff", "keyboard")).toBe("F")
			expect(Bindings.valid(result)).toBe(true)
		end)

		it("setting a key back to its default drops the override", function()
			local result = Bindings.assign({}, "FireMissile", "keyboard", "G")
			result = Bindings.assign(result, "FireMissile", "keyboard", "Space")
			expect(next(result)).toBe(nil)
		end)

		it("swapping twice puts everything back", function()
			local result = Bindings.assign({}, "Flares", "keyboard", "C")
			result = Bindings.assign(result, "Flares", "keyboard", "F")
			expect(next(result)).toBe(nil)
		end)

		it("the menu's fly-again key may share with a flight key", function()
			local result, swapped = Bindings.assign({}, "FlyAgain", "keyboard", "Space")
			expect(swapped).toBe(nil)
			expect(Bindings.resolve(result, "FireMissile", "keyboard")).toBe("Space")
		end)

		it("gamepad buttons swap the same way", function()
			local result, swapped = Bindings.assign({}, "Flares", "gamepad", "ButtonY")
			expect(swapped).toBe("RadarLock")
			expect(Bindings.resolve(result, "RadarLock", "gamepad")).toBe("ButtonB")
		end)

		it("labels read well", function()
			expect(Bindings.label("MouseButton1")).toBe("LMB")
			expect(Bindings.label("ButtonX")).toBe("X")
			expect(Bindings.label("G")).toBe("G")
			expect(Bindings.label(nil)).toBe("—")
		end)
	end)
end
