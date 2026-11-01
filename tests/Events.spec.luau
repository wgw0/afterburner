--!strict
-- OPS-03: scheduled events (Shared/Events) and how LiveConfig applies the running one.
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local Events = require(ctx.Shared.Events)
	local LiveConfig = require(ctx.Shared.LiveConfig)

	local SAT = 1794679200 -- Saturday 14 November 2026, 18:00 UTC
	local NOW = SAT - 86400

	local function make(args: { [string]: any }, schedule: { any }?): (any, string?)
		return Events.make(args, schedule or {}, NOW, "e1")
	end

	describe("times", function()
		it("reads a UTC date with or without a time, or a unix time", function()
			expect(Events.parseTime("2026-11-14 18:00")).toBe(SAT)
			expect(Events.parseTime("2026-11-14")).toBe(SAT - 18 * 3600)
			expect(Events.parseTime("2026-11-14T18:00")).toBe(SAT)
			expect(Events.parseTime(SAT)).toBe(SAT)
			expect(Events.parseTime("next saturday")).toBe(nil)
			expect(Events.parseTime("2026-13-01")).toBe(nil)
		end)
	end)

	describe("scheduling", function()
		it("a weekend of double XP", function()
			local event = make({ name = "Double XP weekend", start = "2026-11-14 18:00", hours = 48, xp = 2 })
			expect(event.start).toBe(SAT)
			expect(event.finish).toBe(SAT + 48 * 3600)
			expect(event.xp).toBe(2)
			expect(event.credits).toBe(1)
		end)

		it("refuses what doesn't make sense", function()
			expect((make({ start = "2026-11-14", hours = 2 }))).toBe(nil) -- no name
			expect((make({ name = "X", start = "soon", hours = 2 }))).toBe(nil)
			expect((make({ name = "X", start = "2026-11-14" }))).toBe(nil) -- no end
			expect((make({ name = "X", start = "2026-11-14", hours = 24 * 15 }))).toBe(nil) -- too long
			expect((make({ name = "X", start = "2026-11-14", hours = 2, xp = 5 }))).toBe(nil)
			expect((make({ name = "X", start = "2026-11-14", hours = 2, xp = 0.5 }))).toBe(nil) -- never a penalty
			expect((make({ name = "X", start = "2026-11-01", hours = 2 }))).toBe(nil) -- already over
		end)

		it("doesn't overlap another event", function()
			local first = make({ name = "A", start = "2026-11-14 18:00", hours = 48 })
			expect((make({ name = "B", start = "2026-11-15 12:00", hours = 2 }, { first }))).toBe(nil)
			expect(make({ name = "B", start = "2026-11-16 18:00", hours = 2 }, { first }) ~= nil).toBe(true)
		end)

		it("runs only between its start and finish", function()
			local event = make({ name = "A", start = SAT, hours = 2 })
			expect(Events.active({ event }, SAT - 1)).toBe(nil)
			expect(Events.active({ event }, SAT)).toBe(event)
			expect(Events.active({ event }, SAT + 2 * 3600)).toBe(nil)
		end)

		it("keeps the schedule short by dropping ended events first", function()
			local list = {}
			for i = 1, Events.KEEP + 5 do
				table.insert(
					list,
					{ id = tostring(i), name = "E", start = i * 10, finish = i * 10 + 5, xp = 1, credits = 1, rp = 1 }
				)
			end
			local trimmed = Events.trim(list, (Events.KEEP + 2) * 10)
			expect(#trimmed).toBe(Events.KEEP)
			expect(trimmed[#trimmed].id).toBe(tostring(Events.KEEP + 5)) -- the upcoming ones stay
		end)

		it("leaves out anything malformed in a stored schedule", function()
			local clean = Events.clean({ { id = "a", name = "A", start = 2, finish = 3 }, { name = "no id" }, 5 })
			expect(#clean).toBe(1)
			expect(clean[1].xp).toBe(1)
		end)
	end)

	describe("live config", function()
		it("a running event raises the multipliers and names itself, and stops on time", function()
			ctx.engineOnly() -- needs HttpService's JSON
			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local now = os.time()
			local schedule = {
				{
					id = "t",
					name = "Test weekend",
					start = now - 60,
					finish = now + 3600,
					xp = 2,
					credits = 1.5,
					rp = 1,
				},
			}
			ReplicatedStorage:SetAttribute(
				LiveConfig.EVENTS_ATTRIBUTE,
				game:GetService("HttpService"):JSONEncode(schedule)
			)
			local ok, err = pcall(function()
				expect(LiveConfig.get("economy.xp")).toBe(2)
				expect(LiveConfig.get("economy.credits")).toBe(1.5)
				expect(LiveConfig.get("economy.rp")).toBe(1)
				expect(LiveConfig.get("event")).toBe("Test weekend")
				expect(LiveConfig.activeEvent(now + 7200)).toBe(nil)
			end)
			ReplicatedStorage:SetAttribute(LiveConfig.EVENTS_ATTRIBUTE, nil)
			if not ok then
				error(err)
			end
			expect(LiveConfig.get("economy.xp")).toBe(1)
			expect(LiveConfig.get("event")).toBe("")
		end)
	end)
end
