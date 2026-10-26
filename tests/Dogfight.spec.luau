--!strict
-- AI dogfight simulator (AI-02/03 acceptance): two pilots on the real flight model and real gun ballistics.
-- Proves the AI can kill, that better pilots beat worse ones, that it defends missiles, and that it never
-- flies into the ground.
return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AIBrain = require(ctx.Shared.AIBrain)
	local AircraftData = require(ctx.Shared.AircraftData)
	local Ballistics = require(ctx.Shared.Ballistics)
	local DamageModel = require(ctx.Shared.DamageModel)
	local FlightModel = require(ctx.Shared.FlightModel)
	local Instructor = require(ctx.Shared.Instructor)
	local Units = require(ctx.Shared.Units)
	local WeaponData = require(ctx.Shared.WeaponData)

	local F5E = AircraftData.get("F5E") :: any
	local GUN = WeaponData.get("M39A2_Twin") :: any
	local DT = 1 / 30
	local HITBOX = Vector3.new(26, 7, 48) -- studs, rough F-5E

	type Pilot = {
		state: any,
		memory: any,
		profile: any,
		health: any,
		rounds: { any },
		fireTimer: number,
		shot: number,
		passive: boolean,
		crashed: boolean,
	}

	local function newPilot(cf: CFrame, profile: any, seed: number, passive: boolean): Pilot
		return {
			state = FlightModel.newState(cf, 230, F5E),
			memory = AIBrain.newMemory(seed),
			profile = profile,
			health = DamageModel.maxHealth(F5E),
			rounds = {},
			fireTimer = 0,
			shot = 0,
			passive = passive,
			crashed = false,
		}
	end

	local function context(me: Pilot, other: Pilot, now: number): any
		return {
			now = now,
			me = {
				cframe = me.state.cframe,
				velocity = me.state.velocity,
				speed = me.state.speed,
				altitude = me.state.altitude,
				groundClearance = me.state.altitude, -- flat ground at sea level
				damaged = false,
				aoa = me.state.aoa,
			},
			target = { id = 1, cframe = other.state.cframe, velocity = other.state.velocity },
			missile = nil,
			gun = GUN,
			mapHalfExtent = 20000,
			ceiling = 20000,
			maxG = F5E.MaxG,
			cornerSpeed = FlightModel.cornerSpeed(F5E, me.state.altitude),
		}
	end

	-- Returns "A", "B" or "draw".
	local function duel(profileA: any, profileB: any, seed: number, passiveB: boolean, seconds: number): string
		local altitude = Units.toStuds(3000)
		local a =
			newPilot(CFrame.lookAt(Vector3.new(0, altitude, 0), Vector3.new(0, altitude, -1)), profileA, seed, false)
		local startB = if passiveB
			then CFrame.lookAt(
				Vector3.new(60, altitude, -Units.toStuds(1200)),
				Vector3.new(60, altitude, -Units.toStuds(5000))
			)
			else CFrame.lookAt(Vector3.new(0, altitude, -Units.toStuds(3500)), Vector3.new(0, altitude, 0))
		local b = newPilot(startB, profileB, seed + 1000, passiveB)
		local pilots = { a, b }
		local now = 0
		for _ = 1, math.floor(seconds / DT) do
			now += DT
			for i, me in pilots do
				local other = pilots[3 - i]
				local decision
				if me.passive then
					-- Hold a level heading (aiming at its own nose would make the Instructor climb forever).
					local look = me.state.cframe.LookVector
					local level = Vector3.new(look.X, 0, look.Z).Unit
					decision = { aim = level, throttle = 0.8, afterburner = false, overG = false, fire = false }
				else
					decision = AIBrain.decide(me.memory, me.profile, context(me, other, now))
				end
				local input = Instructor.compute(me.state, decision.aim, F5E, {
					allowOverG = decision.overG,
					gLimit = decision.gLimit,
					pointNose = decision.pointNose,
					throttle = decision.throttle,
					afterburner = decision.afterburner,
				})
				me.state = FlightModel.step(me.state, input, F5E, DT)
				if me.state.altitude <= 0 then
					me.crashed = true
				end
				if decision.fire then
					me.fireTimer += DT
					local interval = Ballistics.interval(GUN)
					while me.fireTimer >= interval do
						me.fireTimer -= interval
						me.shot += 1
						table.insert(me.rounds, Ballistics.fire(me.state.cframe, me.state.velocity, GUN, seed, me.shot))
					end
				else
					me.fireTimer = 0
				end
			end
			-- Rounds vs the other jet
			for i, me in pilots do
				local other = pilots[3 - i]
				local survivors = {}
				for _, round in me.rounds do
					local nextRound = Ballistics.step(round, DT, GUN.Drag)
					local t = Ballistics.segmentBox(round.position, nextRound.position, other.state.cframe, HITBOX)
					if t then
						other.health = DamageModel.applyDamage(other.health, "Fuselage", GUN.Damage)
					elseif nextRound.age < GUN.Lifetime then
						table.insert(survivors, nextRound)
					end
				end
				me.rounds = survivors
			end
			local aDead = a.crashed or DamageModel.isDestroyed(a.health)
			local bDead = b.crashed or DamageModel.isDestroyed(b.health)
			if aDead or bDead then
				return if aDead and bDead then "draw" elseif bDead then "A" else "B"
			end
		end
		return "draw"
	end

	local RUNS = 10

	describe("AI dogfights", function()
		it("a Normal pilot shoots down a straight-flying target ahead of it", function()
			local kills = 0
			for seed = 1, RUNS do
				if duel(AIBrain.PROFILES.Normal, AIBrain.PROFILES.Normal, seed, true, 60) == "A" then
					kills += 1
				end
			end
			print(`[Dogfight] Normal vs passive target: {kills}/{RUNS} kills`)
			expect(kills >= 8).toBe(true)
		end)

		it("an Ace beats an Easy pilot in most head-on merges", function()
			local wins, losses = 0, 0
			for seed = 1, RUNS do
				local result = duel(AIBrain.PROFILES.Ace, AIBrain.PROFILES.Easy, seed, false, 120)
				if result == "A" then
					wins += 1
				elseif result == "B" then
					losses += 1
				end
			end
			print(`[Dogfight] Ace vs Easy: {wins} wins, {losses} losses, {RUNS - wins - losses} draws`)
			expect(wins > losses).toBe(true)
			expect(wins >= 5).toBe(true)
		end)
	end)

	describe("AI safety and defence", function()
		local function ctxWith(fields: { [string]: any }): any
			local base = {
				now = 10,
				me = {
					cframe = CFrame.lookAt(
						Vector3.new(0, Units.toStuds(3000), 0),
						Vector3.new(0, Units.toStuds(3000), -1)
					),
					velocity = Vector3.new(0, 0, -230),
					speed = 230,
					altitude = 3000,
					groundClearance = 3000,
					damaged = false,
				},
				target = nil,
				missile = nil,
				gun = GUN,
				mapHalfExtent = 20000,
				ceiling = 20000,
			}
			for k, v in fields do
				base[k] = v
			end
			return base
		end

		it("pulls up when diving at the ground", function()
			local c = ctxWith({})
			c.me.velocity = Vector3.new(0, -120, -200)
			c.me.groundClearance = 400
			local d = AIBrain.decide(AIBrain.newMemory(1), AIBrain.PROFILES.Normal, c)
			expect(d.state).toBe("AvoidGround")
			expect(d.aim.Y).toBeGreaterThan(0.3)
		end)

		it("defends a heat-seeker after its reaction time: break, idle, flares", function()
			local memory = AIBrain.newMemory(3)
			local profile = AIBrain.PROFILES.Ace
			local missile = {
				position = Vector3.new(0, Units.toStuds(3000), Units.toStuds(1500)),
				velocity = Vector3.new(0, 0, -800),
				kind = "IR",
			}
			local first = AIBrain.decide(memory, profile, ctxWith({ now = 10, missile = missile }))
			expect(first.state ~= "Defend").toBe(true) -- hasn't reacted yet
			local later = AIBrain.decide(memory, profile, ctxWith({ now = 10.5, missile = missile }))
			expect(later.state).toBe("Defend")
			expect(later.throttle).toBe(0)
			expect(later.flare).toBe(true)
			expect(math.abs(later.aim.Z)).toBeLessThan(0.3) -- turned to put the missile on the beam
		end)

		it("notches a radar missile and drops chaff", function()
			local memory = AIBrain.newMemory(4)
			local missile = {
				position = Vector3.new(0, Units.toStuds(3000), Units.toStuds(5000)),
				velocity = Vector3.new(0, 0, -900),
				kind = "Radar",
			}
			AIBrain.decide(memory, AIBrain.PROFILES.Ace, ctxWith({ now = 10, missile = missile }))
			local d = AIBrain.decide(memory, AIBrain.PROFILES.Ace, ctxWith({ now = 11, missile = missile }))
			expect(d.state).toBe("Defend")
			expect(d.chaff).toBe(true)
			expect(math.abs(d.aim.Z)).toBeLessThan(0.3)
			expect(d.aim.Y).toBeLessThan(0)
		end)

		it("extends to rebuild energy when slow", function()
			local c = ctxWith({})
			c.me.speed = 110
			local d = AIBrain.decide(AIBrain.newMemory(5), AIBrain.PROFILES.Normal, c)
			expect(d.state).toBe("Extend")
			expect(d.afterburner).toBe(true)
		end)

		it("heads back inside the map when patrolling near the edge", function()
			local c = ctxWith({})
			c.me.cframe =
				CFrame.lookAt(Vector3.new(19000, Units.toStuds(3000), 0), Vector3.new(21000, Units.toStuds(3000), 0))
			local d = AIBrain.decide(AIBrain.newMemory(6), AIBrain.PROFILES.Normal, c)
			expect(d.aim.X).toBeLessThan(0.5)
		end)
	end)
	describe("AI missile choice (AI-04)", function()
		local normal = AIBrain.PROFILES.Normal
		local ir = { index = 1, class = "IR", count = 2, minRange = 500, maxRange = 6000, irLockable = true }
		local radar = { index = 2, class = "Radar", count = 2, minRange = 1000, maxRange = 25000 }

		it("fires a heat-seeker when its seeker sees the target in range", function()
			local choice, needsLock = AIBrain.chooseMissile(normal, { ir, radar }, 2500, true)
			expect(choice and choice.index).toBe(1)
			expect(needsLock).toBe(false)
		end)

		it("uses the radar missile (after a lock) when the heat-seeker can't see the target", function()
			local blind = table.clone(ir)
			blind.irLockable = false
			local choice, needsLock = AIBrain.chooseMissile(normal, { blind, radar }, 9000, true)
			expect(choice and choice.index).toBe(2)
			expect(needsLock).toBe(true)
		end)

		it(
			"never fires inside minimum range, beyond its range share, empty, or a radar missile without a radar",
			function()
				expect((AIBrain.chooseMissile(normal, { ir }, 400, true))).toBe(nil)
				expect((AIBrain.chooseMissile(normal, { ir }, 5900, true))).toBe(nil) -- beyond 60% of 6 km
				local empty = table.clone(ir)
				empty.count = 0
				expect((AIBrain.chooseMissile(normal, { empty }, 2500, true))).toBe(nil)
				expect((AIBrain.chooseMissile(normal, { radar }, 9000, false))).toBe(nil)
			end
		)

		it("better pilots fire from further and more often", function()
			local easy, ace = AIBrain.PROFILES.Easy, AIBrain.PROFILES.Ace
			expect(ace.MissileRange > easy.MissileRange).toBe(true)
			expect(ace.MissileInterval < easy.MissileInterval).toBe(true)
		end)
	end)
end
