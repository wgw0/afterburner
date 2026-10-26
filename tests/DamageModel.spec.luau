--!strict
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local DamageModel = require(ctx.Shared.DamageModel)

	local function fresh()
		return DamageModel.maxHealth(nil)
	end

	describe("health", function()
		it("airframe overrides replace defaults", function()
			local h = DamageModel.maxHealth({ ComponentHealth = { Fuselage = 200 } })
			expect(h.Fuselage).toBe(200)
			expect(h.Cockpit).toBe(DamageModel.DEFAULT_HEALTH.Cockpit)
		end)
		it("damage reduces health to zero without mutating; a dead engine alone isn't fatal", function()
			local h0 = fresh()
			local h1, destroyed = DamageModel.applyDamage(h0, "Engine", DamageModel.DEFAULT_HEALTH.Engine + 0)
			expect(h1.Engine).toBe(0)
			expect(h0.Engine).toBe(DamageModel.DEFAULT_HEALTH.Engine)
			expect(destroyed).toBe(false) -- losing the engine alone doesn't destroy the jet
		end)
		it("cockpit, fuselage or a wing at zero destroys the jet", function()
			for _, component in { "Cockpit", "Fuselage", "WingL", "WingR" } do
				local _, destroyed = DamageModel.applyDamage(fresh(), component, 1000)
				expect(destroyed).toBe(true)
			end
			-- Destroying the tail exactly (no spill-over) leaves the jet flying
			local _, tailGone = DamageModel.applyDamage(fresh(), "Tail", DamageModel.DEFAULT_HEALTH.Tail)
			expect(tailGone).toBe(false)
		end)
		it("hits on a destroyed part spill into the fuselage, so tail shots can kill", function()
			local h = fresh()
			local destroyed = false
			local hits = 0
			while not destroyed and hits < 100 do
				h, destroyed = DamageModel.applyDamage(h, "Tail", 10)
				hits += 1
			end
			expect(destroyed).toBe(true)
			expect(hits).toBe(math.ceil((DamageModel.DEFAULT_HEALTH.Tail + DamageModel.DEFAULT_HEALTH.Fuselage) / 10))
		end)
		it("unknown hitboxes count as fuselage", function()
			local h = DamageModel.applyDamage(fresh(), "Pylon", 10)
			expect(h.Fuselage).toBe(DamageModel.DEFAULT_HEALTH.Fuselage - 10)
		end)
	end)

	describe("modifiers", function()
		it("an undamaged jet flies normally", function()
			local m = DamageModel.modifiers({ Engine = 1, Tail = 1, WingL = 1, WingR = 1 })
			expect(m.thrust).toBe(1)
			expect(m.lift).toBe(1)
			expect(m.rollBias).toBe(0)
		end)
		it("engine damage cuts thrust, a dead engine gives none", function()
			expect(DamageModel.modifiers({ Engine = 0.3 }).thrust).toBeLessThan(0.6)
			expect(DamageModel.modifiers({ Engine = 0 }).thrust).toBe(0)
		end)
		it("a damaged left wing rolls the jet left", function()
			expect(DamageModel.modifiers({ WingL = 0.3, WingR = 1 }).rollBias :: number).toBeLessThan(0)
			expect(DamageModel.modifiers({ WingL = 1, WingR = 0.3 }).rollBias :: number).toBeGreaterThan(0)
		end)
		it("tail damage reduces pitch and yaw authority", function()
			local m = DamageModel.modifiers({ Tail = 0 })
			expect(m.pitch).toBeCloseTo(0.3, 1e-9)
			expect(m.yaw).toBeCloseTo(0.3, 1e-9)
		end)
	end)

	describe("kill credit", function()
		it("the last damager within 15 s gets the kill; big contributors assist", function()
			local credit = DamageModel.resolveCredit({
				alice = { damage = 60, time = 95 },
				bob = { damage = 40, time = 99 },
			}, 100, "Shot")
			expect(credit.killer).toBe("bob")
			expect(#credit.assists).toBe(1)
			expect(credit.assists[1]).toBe("alice")
			expect(credit.forcedCrash).toBe(false)
		end)
		it("small contributors don't assist", function()
			local credit = DamageModel.resolveCredit({
				alice = { damage = 10, time = 95 },
				bob = { damage = 90, time = 99 },
			}, 100, "Shot")
			expect(#credit.assists).toBe(0)
		end)
		it("a crash soon after being shot is a forced-crash kill", function()
			local credit = DamageModel.resolveCredit({ alice = { damage = 30, time = 80 } }, 100, "Crash")
			expect(credit.killer).toBe("alice")
			expect(credit.forcedCrash).toBe(true)
		end)
		it("an old hit doesn't count", function()
			local credit = DamageModel.resolveCredit({ alice = { damage = 30, time = 10 } }, 100, "Crash")
			expect(credit.killer).toBe(nil)
		end)
		it("leaving the game while damaged still gives the attacker the kill (AIR-05)", function()
			local credit = DamageModel.resolveCredit({ alice = { damage = 50, time = 95 } }, 100, "PilotLeft")
			expect(credit.killer).toBe("alice")
		end)
		it("respawning to escape a fight still gives the attacker the kill", function()
			local credit = DamageModel.resolveCredit({ alice = { damage = 50, time = 95 } }, 100, "Respawn")
			expect(credit.killer).toBe("alice")
		end)
		it("a crash with no damage is nobody's kill", function()
			expect(DamageModel.resolveCredit({}, 100, "Crash").killer).toBe(nil)
		end)
	end)
end
