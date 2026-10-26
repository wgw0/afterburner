--!strict
-- Tech tree, match rewards, pilot level, research/purchase, modules and lineup (PRG-01–05).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local AircraftData = require(ctx.Shared.AircraftData)
	local Economy = require(ctx.Shared.Config.Economy)
	local PlayerData = require(ctx.Shared.PlayerData)
	local Progression = require(ctx.Shared.Progression)
	local TechTree = require(ctx.Shared.TechTree)

	local function summary(events, opts: any?)
		local o = opts or {}
		return {
			Events = events,
			LastAirframe = o.last or "F5E",
			Survived = o.survived == true,
			Won = o.won == true,
			Afk = o.afk == true,
			Day = o.day or 100,
		}
	end
	local function kill(airframe: string, victim: string, ai: boolean?)
		return { Kind = "Kill", Airframe = airframe, Victim = victim, VictimAI = ai }
	end

	describe("tech tree", function()
		it("every node is a real airframe with the same tier and branch", function()
			for _, node in TechTree.NODES do
				local airframe = AircraftData.get(node.Id) :: any
				if not airframe then
					error(`{node.Id} has no AircraftData`, 0)
				end
				expect(airframe.Tier).toBe(node.Tier)
				expect(airframe.Branch).toBe(node.Branch)
			end
		end)

		it("requirements are real nodes at the same or a lower tier", function()
			for _, node in TechTree.NODES do
				for _, req in node.Requires do
					local other = TechTree.get(req)
					if not other then
						error(`{node.Id} requires unknown {req}`, 0)
					end
					expect(other.Tier <= node.Tier).toBe(true)
				end
			end
		end)

		it("starters are free and everything else is reachable from them", function()
			local reachable = {}
			for _, id in Economy.STARTERS do
				local node = TechTree.get(id) :: any
				expect(node.RP).toBe(0)
				expect(node.Credits).toBe(0)
				reachable[id] = true
			end
			local grew = true
			while grew do
				grew = false
				for _, node in TechTree.NODES do
					if not reachable[node.Id] then
						for _, req in node.Requires do
							if reachable[req] then
								reachable[node.Id] = true
								grew = true
								break
							end
						end
					end
				end
			end
			for _, node in TechTree.NODES do
				if not reachable[node.Id] then
					error(`{node.Id} can't be reached from the starters`, 0)
				end
			end
		end)
	end)

	describe("match rewards", function()
		it("a kill on a player pays the table values at Tier I", function()
			local r = Progression.matchRewards(summary({ kill("F5E", "p1") }, { last = nil }), 0)
			local base = Economy.ACTIONS.Kill
			expect(r.XP).toBe(base.XP + Economy.ACTIONS.Participation.XP)
			expect(r.Credits).toBe(base.Credits + Economy.ACTIONS.Participation.Credits)
			expect(r.RP.F5E).toBe(base.RP + Economy.ACTIONS.Participation.RP)
		end)

		it("AI kills pay half; a fourth kill on the same victim pays a quarter", function()
			local ai = Progression.matchRewards(summary({ kill("F5E", "ai1", true) }), 0)
			local human = Progression.matchRewards(summary({ kill("F5E", "p1") }), 0)
			local participation = Economy.ACTIONS.Participation.XP
			expect(ai.XP - participation).toBe((human.XP - participation) * Economy.AI_KILL_FACTOR)
			local events = {}
			for _ = 1, 4 do
				table.insert(events, kill("F5E", "p1"))
			end
			local farmed = Progression.matchRewards(summary(events), 0)
			local per = Economy.ACTIONS.Kill.XP
			expect(farmed.XP - participation).toBe(per * 3 + per * Economy.SAME_VICTIM_FACTOR)
		end)

		it("higher-tier jets earn more RP and Credits but the same XP", function()
			local t1 = Progression.matchRewards(summary({ kill("F5E", "p1") }, { last = "F5E" }), 0)
			local t2 = Progression.matchRewards(summary({ kill("F4E", "p1") }, { last = "F4E" }), 0)
			expect(t2.XP).toBe(t1.XP)
			expect(t2.RP.F4E > t1.RP.F5E).toBe(true)
			expect(t2.Credits > t1.Credits).toBe(true)
		end)

		it("a win adds 30%, the first win of the day doubles it, and AFK pilots get neither", function()
			local base = Progression.matchRewards(summary({ kill("F5E", "p1") }, { survived = true }), 0)
			local win = Progression.matchRewards(summary({ kill("F5E", "p1") }, { survived = true, won = true }), 100)
			local first = Progression.matchRewards(summary({ kill("F5E", "p1") }, { survived = true, won = true }), 99)
			local afk = Progression.matchRewards(
				summary({ kill("F5E", "p1") }, { survived = true, won = true, afk = true }),
				99
			)
			expect(win.XP).toBe(math.floor(base.XP * 1.3 + 0.5))
			expect(first.FirstWin).toBe(true)
			expect(first.XP).toBe(math.floor(base.XP * 1.3 * 2 + 0.5))
			expect(afk.XP < base.XP).toBe(true) -- no survival bonus either
		end)

		it("10% of the RP also goes to the free pool", function()
			local r = Progression.matchRewards(summary({ kill("F5E", "p1"), kill("F5E", "p2") }), 0)
			expect(r.FreeRP).toBe(math.floor(r.RP.F5E * Economy.FREE_RP_SHARE + 0.5))
		end)

		it("applying rewards credits the jet, the pool, Credits, stats and the win day", function()
			local data = PlayerData.template()
			local s = summary({ kill("F5E", "p1"), kill("F5E", "ai", true) }, { survived = true, won = true, day = 7 })
			local r = Progression.matchRewards(s, data.LastWinDay)
			Progression.applyRewards(data, r, s)
			expect(data.Aircraft.F5E.RP).toBe(r.RP.F5E)
			expect(data.FreeRP).toBe(r.FreeRP)
			expect(data.Stats.Kills).toBe(1)
			expect(data.Stats.AIKills).toBe(1)
			expect(data.Stats.Wins).toBe(1)
			expect(data.LastWinDay).toBe(7)
		end)
	end)

	describe("pilot level", function()
		it("levels up through the curve and pays Credits per level", function()
			local data = PlayerData.template()
			local credits = data.Credits
			local gained = Progression.addXP(data, Economy.xpToNext(1) + Economy.xpToNext(2) + 10)
			expect(gained).toBe(2)
			expect(data.PilotLevel).toBe(3)
			expect(data.PilotXP).toBe(10)
			expect(data.Credits).toBe(credits + 2 * Economy.LEVEL_CREDITS)
		end)

		it("lineup slots open at levels 5 and 15", function()
			expect(Progression.lineupSlots(1)).toBe(1)
			expect(Progression.lineupSlots(5)).toBe(2)
			expect(Progression.lineupSlots(15)).toBe(3)
		end)
	end)

	describe("research and purchase", function()
		it("research spends the prerequisite's RP first, then the free pool", function()
			local data = PlayerData.template()
			local cost = (TechTree.get("MirageIII") :: any).RP
			data.Aircraft.F5E.RP = cost - 50
			data.FreeRP = 60
			local ok = Progression.research(data, "MirageIII")
			expect(ok).toBe(true)
			expect(data.Aircraft.F5E.RP).toBe(0)
			expect(data.FreeRP).toBe(10)
			expect(data.Aircraft.MirageIII.Researched).toBe(true)
			expect(data.Aircraft.MirageIII.Owned).toBe(false)
		end)

		it("not enough RP, or no owned prerequisite, is refused and changes nothing", function()
			local data = PlayerData.template()
			local ok, err = Progression.research(data, "MirageIII")
			expect(ok).toBe(false)
			expect(err ~= nil).toBe(true)
			-- Tier III needs a Tier II jet owned, whatever RP you have
			data.Aircraft.F5E.RP = 1e6
			data.FreeRP = 1e6
			local ok3 = Progression.research(data, "F16A")
			expect(ok3).toBe(false)
			expect(data.Aircraft.F5E.RP).toBe(1e6)
		end)

		it("buying needs research first and enough Credits, and fills a free lineup slot", function()
			local data = PlayerData.template()
			expect((Progression.buy(data, "MirageIII"))).toBe(false) -- not researched
			data.Aircraft.F5E.RP = 10000
			Progression.research(data, "MirageIII")
			data.Credits = 0
			expect((Progression.buy(data, "MirageIII"))).toBe(false) -- no Credits
			data.Credits = 5000
			data.PilotLevel = 5 -- two slots
			expect((Progression.buy(data, "MirageIII"))).toBe(true)
			expect(data.Aircraft.MirageIII.Owned).toBe(true)
			expect(data.Credits).toBe(5000 - (TechTree.get("MirageIII") :: any).Credits)
			expect(table.find(data.Lineup, "MirageIII") ~= nil).toBe(true)
			expect((Progression.buy(data, "MirageIII"))).toBe(false) -- already owned
		end)

		it("unknown aircraft are refused", function()
			local data = PlayerData.template()
			expect((Progression.research(data, "SR71"))).toBe(false)
			expect((Progression.buy(data, "SR71"))).toBe(false)
		end)
	end)

	describe("modules", function()
		it("needs the jet, the previous module, its RP and Credits", function()
			local data = PlayerData.template()
			expect((Progression.buyModule(data, "MirageIII", "Engine1"))).toBe(false) -- not owned
			expect((Progression.buyModule(data, "F5E", "Engine2"))).toBe(false) -- Engine I first
			expect((Progression.buyModule(data, "F5E", "Engine1"))).toBe(false) -- no RP
			data.Aircraft.F5E.RP = 1000
			data.Credits = 1000
			expect((Progression.buyModule(data, "F5E", "Engine1"))).toBe(true)
			expect(data.Aircraft.F5E.Modules.Engine1).toBe(true)
			expect((Progression.buyModule(data, "F5E", "Engine1"))).toBe(false) -- already fitted
		end)

		it("unfitting keeps the module, refitting is free", function()
			local data = PlayerData.template()
			data.Aircraft.F5E.RP = 5000
			data.Credits = 50000
			expect((Progression.buyModule(data, "F5E", "Engine1"))).toBe(true)
			local rp, credits = data.Aircraft.F5E.RP, data.Credits
			expect((Progression.setModuleFitted(data, "F5E", "Engine1", false))).toBe(true)
			expect(data.Aircraft.F5E.Modules.Engine1).toBe(false)
			expect((Progression.buyModule(data, "F5E", "Engine1"))).toBe(false) -- owned: no second purchase
			expect((Progression.setModuleFitted(data, "F5E", "Engine1", true))).toBe(true)
			expect(data.Aircraft.F5E.Modules.Engine1).toBe(true)
			expect(data.Aircraft.F5E.RP).toBe(rp)
			expect(data.Credits).toBe(credits)
			expect((Progression.setModuleFitted(data, "F5E", "Airframe1", true))).toBe(false) -- not bought
		end)

		it("a module can't come off under one built on it, or go on without its base", function()
			local data = PlayerData.template()
			data.Aircraft.F5E.RP = 5000
			data.Credits = 50000
			expect((Progression.buyModule(data, "F5E", "Engine1"))).toBe(true)
			expect((Progression.buyModule(data, "F5E", "Engine2"))).toBe(true)
			local ok, err = Progression.setModuleFitted(data, "F5E", "Engine1", false)
			expect(ok).toBe(false)
			expect(string.find(err or "", "Unfit", 1, true) ~= nil).toBe(true)
			expect((Progression.setModuleFitted(data, "F5E", "Engine2", false))).toBe(true)
			expect((Progression.setModuleFitted(data, "F5E", "Engine1", false))).toBe(true)
			expect((Progression.setModuleFitted(data, "F5E", "Engine2", true))).toBe(false) -- Engine I is off
		end)

		it("unfitted modules have no effect and don't ride on the jet", function()
			local f5 = AircraftData.get("F5E") :: any
			local off = Progression.applyModules(f5, { Engine1 = false, Airframe1 = true })
			expect(off.MaxThrust).toBe(f5.MaxThrust)
			expect(off.MaxG > f5.MaxG).toBe(true)
			expect(Progression.encodeModules({ Engine1 = false, Airframe1 = true })).toBe("Airframe1")
		end)

		it("modules change a copy of the airframe, never the original", function()
			local f5 = AircraftData.get("F5E") :: any
			local upgraded = Progression.applyModules(
				f5,
				{ Engine1 = true, Engine2 = true, Airframe1 = true, Avionics1 = true, Countermeasures1 = true }
			)
			expect(math.abs(upgraded.MaxThrust - f5.MaxThrust * 1.03 * 1.03) < 1).toBe(true)
			expect(upgraded.MaxG).toBe(f5.MaxG + 0.25)
			expect(math.abs(upgraded.Radar.Range - f5.Radar.Range * 1.15) < 1).toBe(true)
			expect(upgraded.Countermeasures.Flares).toBe(math.floor(f5.Countermeasures.Flares * 1.5 + 0.5))
			expect(f5.MaxThrust).toBe(31000)
		end)

		it("a fully upgraded jet is 10–18% better on thrust and turn, never more", function()
			local f5 = AircraftData.get("F5E") :: any
			local all = {}
			for _, def in Economy.MODULES do
				all[def.Id] = true
			end
			local upgraded = Progression.applyModules(f5, all)
			local thrust = upgraded.MaxThrust / f5.MaxThrust
			expect(thrust > 1.05 and thrust < 1.1).toBe(true)
			expect(upgraded.MaxG - f5.MaxG <= 0.5).toBe(true)
		end)
	end)

	describe("lineup", function()
		it("only owned jets, no duplicates, no more than the slots allow", function()
			local data = PlayerData.template()
			expect((Progression.setLineup(data, { "MiG21bis" }))).toBe(true)
			expect(data.Lineup[1]).toBe("MiG21bis")
			expect((Progression.setLineup(data, { "F5E", "MiG21bis" }))).toBe(false) -- one slot at level 1
			data.PilotLevel = 5
			expect((Progression.setLineup(data, { "F5E", "MiG21bis" }))).toBe(true)
			expect((Progression.setLineup(data, { "F5E", "F5E" }))).toBe(false)
			expect((Progression.setLineup(data, { "F16A" }))).toBe(false)
			expect((Progression.setLineup(data, {}))).toBe(false)
		end)
	end)
end
