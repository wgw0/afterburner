--!strict
-- Effects quality (FX-05).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Graphics = require(ctx.Shared.Config.Graphics)
	local Settings = require(ctx.Shared.Config.Settings)

	local desktop = { touchOnly = false, robloxLevel = 0 }

	describe("level", function()
		it("a chosen level is used as it is", function()
			expect(Graphics.level("Low", desktop)).toBe("Low")
			expect(Graphics.level("High", { touchOnly = true, robloxLevel = 1 })).toBe("High")
		end)

		it("Auto: Low on phones and low Roblox levels, Medium in the middle, else High", function()
			expect(Graphics.level("Auto", { touchOnly = true, robloxLevel = 0 })).toBe("Low")
			expect(Graphics.level("Auto", { touchOnly = false, robloxLevel = 2 })).toBe("Low")
			expect(Graphics.level("Auto", { touchOnly = false, robloxLevel = 5 })).toBe("Medium")
			expect(Graphics.level("Auto", { touchOnly = false, robloxLevel = 9 })).toBe("High")
			expect(Graphics.level("Auto", desktop)).toBe("High")
		end)
	end)

	describe("profiles", function()
		it("get lighter from High to Low", function()
			local low, medium, high = Graphics.PROFILES.Low, Graphics.PROFILES.Medium, Graphics.PROFILES.High
			expect(low.particles < medium.particles and medium.particles < high.particles).toBe(true)
			expect(low.jetLights).toBe(false)
			expect(high.flareLights).toBe(true)
		end)

		it("count scales bursts but keeps at least one", function()
			expect(Graphics.count(Graphics.PROFILES.High, 40)).toBe(40)
			expect(Graphics.count(Graphics.PROFILES.Low, 40)).toBe(12)
			expect(Graphics.count(Graphics.PROFILES.Low, 1)).toBe(1)
			expect(Graphics.count(Graphics.PROFILES.Low, 0)).toBe(0)
		end)
	end)

	describe("settings", function()
		it("know the graphics settings and their defaults", function()
			local defaults = Settings.defaults()
			expect(defaults.EffectsQuality).toBe("Auto")
			expect(defaults.Contrails).toBe(true)
			expect(Settings.valid("EffectsQuality", "Ultra")).toBe(false)
			expect(Settings.valid("EffectsQuality", "Medium")).toBe(true)
		end)
	end)
end
