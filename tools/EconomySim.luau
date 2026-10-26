--!strict
-- Economy pacing simulation (DEVELOPMENT.md §23.6, PRG-06). A typical free player plays average
-- matches with the real reward code (Progression.matchRewards / applyRewards) and spends greedily with
-- the real rules (research, buy, modules). Reports when each milestone is reached, to check DESIGN §7.3:
--   first new jet 20–30 min · Tier II 2–3 h · Tier III 8–10 h.
-- Re-run whenever an economy value changes:
--   print(require(game.ServerStorage.Tools.EconomySim).report())
-- tests/Economy.spec runs it too and checks the targets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomySim = {}

-- An average 10-minute free-for-all, as a repeating cycle of 10 matches: totals per cycle.
-- (1.5 kills a match, mostly on AI; one assist; half the missiles defended; survive half; win 1 in 10;
-- one first-win-of-the-day per cycle, i.e. about two hours of play a day.)
EconomySim.CYCLE = table.freeze({
	matches = 10,
	humanKills = 3,
	aiKills = 12,
	assists = 10,
	missilesDefeated = 5,
	survived = 5,
	wins = 1,
})
EconomySim.MATCH_MINUTES = 11 -- 10 minutes of flying plus results and countdown
EconomySim.BUYS_MODULES = true -- spends spare RP on modules for the jet it flies

type Milestones = { [string]: number } -- name -> minutes

-- Runs the simulation for `hours` of play (default 12). shared: the Shared folder to use.
function EconomySim.run(hours: number?, shared: Instance?): (Milestones, { string })
	local Shared = shared or ReplicatedStorage:WaitForChild("Shared")
	local AircraftData = require(Shared:FindFirstChild("AircraftData") :: any) :: any
	local Economy = require(Shared:FindFirstChild("Config"):FindFirstChild("Economy") :: any) :: any
	local PlayerData = require(Shared:FindFirstChild("PlayerData") :: any) :: any
	local Progression = require(Shared:FindFirstChild("Progression") :: any) :: any
	local TechTree = require(Shared:FindFirstChild("TechTree") :: any) :: any

	local data = PlayerData.template()
	local milestones: Milestones = {}
	local log: { string } = {}
	local minutes = 0
	local cycle = EconomySim.CYCLE
	local maxMatches = math.floor((hours or 12) * 60 / EconomySim.MATCH_MINUTES)

	local function best(): string
		local top, topTier = "F5E", 0
		for id, entry in data.Aircraft do
			local airframe = AircraftData.get(id)
			if entry.Owned and airframe and airframe.Tier > topTier then
				top, topTier = id, airframe.Tier
			end
		end
		return top
	end

	local function note(name: string)
		if milestones[name] == nil then
			milestones[name] = minutes
			table.insert(log, string.format("%6.1f h  %s", minutes / 60, name))
		end
	end

	local function spend(flying: string)
		-- Research and buy: the cheapest node it can research, then anything researched it can afford
		local progress = true
		while progress do
			progress = false
			local candidate, cost = nil, math.huge
			for _, node in TechTree.NODES do
				local plan = Progression.researchPlan(data, node.Id)
				if plan and node.RP < cost then
					candidate, cost = node, node.RP
				end
			end
			if candidate and Progression.research(data, candidate.Id) then
				note(`researched {candidate.Id}`)
				progress = true
			end
			for _, node in TechTree.NODES do
				if Progression.buy(data, node.Id) then
					note(`bought {node.Id} (Tier {node.Tier})`)
					progress = true
				end
			end
		end
		-- Modules with spare RP, keeping enough for the next research
		if EconomySim.BUYS_MODULES then
			for _, def in Economy.MODULES do
				local rp = Progression.moduleCost(flying, def)
				local entry = data.Aircraft[flying]
				if entry and entry.RP > rp * 4 and Progression.buyModule(data, flying, def.Id) then
					note(`fitted {def.Id} on {flying}`)
				end
			end
		end
	end

	for match = 1, maxMatches do
		local flying = best()
		local index = (match - 1) % cycle.matches + 1
		-- Spread the cycle's totals over its matches
		local function share(total: number): number
			return math.floor(total * index / cycle.matches) - math.floor(total * (index - 1) / cycle.matches)
		end
		local events = {}
		for k = 1, share(cycle.humanKills) do
			table.insert(events, { Kind = "Kill", Airframe = flying, Victim = `p{match}:{k}`, VictimAI = false })
		end
		for k = 1, share(cycle.aiKills) do
			table.insert(events, { Kind = "Kill", Airframe = flying, Victim = `ai{match}:{k}`, VictimAI = true })
		end
		for _ = 1, share(cycle.assists) do
			table.insert(events, { Kind = "Assist", Airframe = flying })
		end
		for _ = 1, share(cycle.missilesDefeated) do
			table.insert(events, { Kind = "MissileDefeated", Airframe = flying })
		end
		local won = share(cycle.wins) > 0
		local summary = {
			Events = events,
			LastAirframe = flying,
			Survived = share(cycle.survived) > 0,
			Won = won,
			Afk = false,
			Day = match // cycle.matches, -- a new day every cycle
		}
		local rewards = Progression.matchRewards(summary, data.LastWinDay)
		local levels = Progression.applyRewards(data, rewards, summary)
		minutes += EconomySim.MATCH_MINUTES
		if levels > 0 and data.PilotLevel >= 5 then
			note("pilot level 5 (second lineup slot)")
		end
		spend(flying)
		local tier = (AircraftData.get(best()) :: any).Tier
		for id, entry in data.Aircraft do
			if entry.Owned and not table.find(Economy.STARTERS, id) then
				note("first new jet")
			end
		end
		if tier >= 2 then
			note("Tier II")
		end
		if tier >= 3 then
			note("Tier III")
		end
	end
	return milestones, log
end

-- A printable timeline.
function EconomySim.report(hours: number?): string
	local _, log = EconomySim.run(hours)
	return "Economy simulation (average free player):\n" .. table.concat(log, "\n")
end

return EconomySim
