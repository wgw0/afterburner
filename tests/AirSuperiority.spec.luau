--!strict
-- Air Superiority zones and tickets (MCH-06).
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AirSuperiority = require(ctx.Shared.AirSuperiority)

	local function zone(state: any, id: string): any
		for _, z in state.zones do
			if z.id == id then
				return z
			end
		end
		return nil
	end

	-- Runs `seconds` of capture with this presence, in 0.5 s steps; returns every capture event.
	local function run(state: any, presence: any, seconds: number): { any }
		local events = {}
		for _ = 1, seconds * 2 do
			for _, event in AirSuperiority.step(state, presence, 0.5) do
				table.insert(events, event)
			end
		end
		return events
	end

	describe("Air Superiority", function()
		it("three zones on the centre line, both teams on full tickets", function()
			local state = AirSuperiority.newState({ "West", "East" })
			expect(#state.zones).toBe(3)
			for _, z in state.zones do
				expect(z.position.X).toBe(0)
				expect(z.owner).toBe(nil)
			end
			expect(state.tickets.West).toBe(AirSuperiority.TICKETS)
			expect(AirSuperiority.contains(zone(state, "B"), Vector3.new(300, 500, -300))).toBe(true)
			expect(AirSuperiority.contains(zone(state, "B"), Vector3.new(0, 4000, 0))).toBe(false) -- above the top
		end)

		it("one jet takes a neutral zone in CAPTURE_SECONDS; three take it three times faster", function()
			local state = AirSuperiority.newState({ "West", "East" })
			local events = run(state, { A = { West = 1 } }, AirSuperiority.CAPTURE_SECONDS - 1)
			expect(#events).toBe(0)
			events = run(state, { A = { West = 1 } }, 1)
			expect(zone(state, "A").owner).toBe("West")
			expect(events[1].team).toBe("West")
			local fast = AirSuperiority.newState({ "West", "East" })
			run(fast, { C = { East = 5 } }, 3.5) -- three capturers count (CAPTURE_SECONDS / 3 = 3.3 s)
			expect(zone(fast, "C").owner).toBe("East")
		end)

		it("equal numbers stall a capture; an owned zone must go back to neutral first", function()
			local state = AirSuperiority.newState({ "West", "East" })
			run(state, { B = { West = 2, East = 2 } }, 30)
			expect(zone(state, "B").progress).toBe(0)
			run(state, { B = { West = 1 } }, AirSuperiority.CAPTURE_SECONDS)
			expect(zone(state, "B").owner).toBe("West")
			run(state, { B = { East = 1 } }, AirSuperiority.CAPTURE_SECONDS / 2)
			expect(zone(state, "B").owner).toBe("West") -- still West's, halfway back
			run(state, { B = { East = 1 } }, AirSuperiority.CAPTURE_SECONDS / 2 + 0.5)
			expect(zone(state, "B").owner).toBe(nil) -- neutral
			run(state, { B = { East = 1 } }, AirSuperiority.CAPTURE_SECONDS)
			expect(zone(state, "B").owner).toBe("East")
		end)

		it("holding more zones bleeds the other team; losses cost tickets; zero tickets ends it", function()
			local state = AirSuperiority.newState({ "West", "East" })
			run(state, { A = { West = 3 }, B = { West = 3 } }, AirSuperiority.CAPTURE_SECONDS)
			local before = state.tickets.East
			run(state, {}, 10)
			expect(state.tickets.East).toBe(before - 2 * AirSuperiority.BLEED_PER_ZONE * 10)
			expect(state.tickets.West).toBe(AirSuperiority.TICKETS)
			AirSuperiority.jetLost(state, "West")
			expect(state.tickets.West).toBe(AirSuperiority.TICKETS - AirSuperiority.KILL_COST)
			expect((AirSuperiority.checkEnd(state))).toBe(false)
			state.tickets.East = 1
			run(state, {}, 1)
			local ended, winner = AirSuperiority.checkEnd(state)
			expect(ended).toBe(true)
			expect(winner).toBe("West")
		end)
	end)
end
