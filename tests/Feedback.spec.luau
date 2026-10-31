--!strict
-- Report a bug: the rules for a report and the device info sent with it (Shared/Feedback).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Feedback = require(ctx.Shared.Feedback)

	describe("Feedback.validate", function()
		it("accepts a report and trims it", function()
			local text, why = Feedback.validate("Bug", "  my wings vanished  ", 1000, nil, 0)
			expect(text).toBe("my wings vanished")
			expect(why).toBe(nil)
		end)

		it("needs a known type and a few words", function()
			expect((Feedback.validate("Rant", "something broke", 1000, nil, 0))).toBe(nil)
			expect((Feedback.validate(nil, "something broke", 1000, nil, 0))).toBe(nil)
			expect((Feedback.validate("Lag", "  a ", 1000, nil, 0))).toBe(nil)
			expect((Feedback.validate("Idea", 42, 1000, nil, 0))).toBe(nil)
		end)

		it("waits between reports and stops at the daily limit", function()
			local text, why = Feedback.validate("Bug", "it broke", 1000, 1000 - Feedback.COOLDOWN + 30, 0)
			expect(text).toBe(nil)
			expect(string.find(why :: string, "30 s") ~= nil).toBe(true)
			expect((Feedback.validate("Bug", "it broke", 1000, 1000 - Feedback.COOLDOWN, 0))).toBe("it broke")
			expect((Feedback.validate("Bug", "it broke", 1000, nil, Feedback.PER_DAY))).toBe(nil)
		end)

		it("cuts a long report to the limit", function()
			local text = Feedback.validate("Other", string.rep("é", Feedback.MAX_LENGTH + 40), 1000, nil, 0)
			expect(utf8.len(text :: string)).toBe(Feedback.MAX_LENGTH)
		end)

		it("refuses text that isn't readable", function()
			expect((Feedback.validate("Bug", "bad \255\254 bytes", 1000, nil, 0))).toBe(nil)
		end)
	end)

	describe("Feedback.cleanInfo", function()
		it("clamps numbers and tidies words", function()
			local info = Feedback.cleanInfo({
				fps = 59.94,
				memory = -5,
				graphics = 99,
				ping = 0 / 0,
				input = "Keyboard<script>",
				screen = "1920x1080",
				jet = string.rep("F", 80),
			})
			expect(info.fps).toBe(59.9)
			expect(info.memory).toBe(0)
			expect(info.graphics).toBe(21)
			expect(info.ping).toBe(nil)
			expect(info.input).toBe("Keyboardscript")
			expect(info.screen).toBe("1920x1080")
			expect(#(info.jet :: string)).toBe(30)
		end)

		it("ignores anything that isn't a table, and fields of the wrong type", function()
			expect(next(Feedback.cleanInfo("lots of info"))).toBe(nil)
			expect(Feedback.cleanInfo({ fps = "60" }).fps).toBe(nil)
		end)
	end)
end
