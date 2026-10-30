--!strict
-- Progression rules (DEVELOPMENT.md §23): match rewards, pilot level, research, purchase, modules and
-- lineup. Pure functions over a save table (PlayerData), so ProgressionService and the tests share one
-- source of truth. Every action validates first and only changes the data when it's allowed.

local AircraftData = require(script.Parent.AircraftData)
local Economy = require(script.Parent.Config.Economy)
local LevelRewards = require(script.Parent.Config.LevelRewards)
local PlayerData = require(script.Parent.PlayerData)
local Skins = require(script.Parent.Skins)
local TechTree = require(script.Parent.TechTree)

local Progression = {}

export type MatchEvent = {
	Kind: string, -- "Kill" | "Assist" | "MissileDefeated" | "ZoneCaptured"
	Airframe: string, -- the jet flown when it happened (earns the RP)
	Victim: string?, -- kills: a key for the victim (same-victim limit)
	VictimAI: boolean?,
}

export type MatchSummary = {
	Events: { MatchEvent },
	LastAirframe: string?, -- jet flown at the end (survival / participation RP)
	Survived: boolean,
	Won: boolean,
	Afk: boolean, -- no input for Economy.AFK_SECONDS: no survival or win bonus
	Day: number, -- os.time() // 86400, for first win of the day
	-- Live config multipliers (OPS-01), e.g. a double XP weekend; Label names the line on the results screen
	Boost: { XP: number, Credits: number, RP: number, Label: string }?,
}

export type RewardLine = { Label: string, XP: number, RP: number, Credits: number }
export type Rewards = {
	XP: number,
	Credits: number,
	RP: { [string]: number }, -- per airframe
	FreeRP: number,
	Lines: { RewardLine },
	FirstWin: boolean,
}

local function tierOf(airframeId: string): number
	local node = TechTree.get(airframeId)
	if node then
		return node.Tier
	end
	local airframe = AircraftData.get(airframeId) :: any
	return if airframe then airframe.Tier else 1
end

local function tierMultiplier(airframeId: string): number
	return Economy.TIER_MULTIPLIER[tierOf(airframeId)] or 1
end

-- Turns a match summary into rewards (nothing is changed; see applyRewards).
function Progression.matchRewards(summary: MatchSummary, lastWinDay: number): Rewards
	local rewards: Rewards = { XP = 0, Credits = 0, RP = {}, FreeRP = 0, Lines = {}, FirstWin = false }
	local lineIndex: { [string]: RewardLine } = {}
	local function add(label: string, airframe: string, action: string, factor: number)
		local base = Economy.ACTIONS[action]
		local tier = tierMultiplier(airframe)
		local xp = base.XP * factor
		local rp = base.RP * factor * tier
		local credits = base.Credits * factor * tier
		local line = lineIndex[label]
		if not line then
			line = { Label = label, XP = 0, RP = 0, Credits = 0 }
			lineIndex[label] = line
			table.insert(rewards.Lines, line)
		end
		line.XP += xp
		line.RP += rp
		line.Credits += credits
		rewards.XP += xp
		rewards.Credits += credits
		rewards.RP[airframe] = (rewards.RP[airframe] or 0) + rp
	end

	local killsOn: { [string]: number } = {}
	for _, event in summary.Events do
		if event.Kind == "Kill" then
			local factor = if event.VictimAI then Economy.AI_KILL_FACTOR else 1
			local victim = event.Victim or "?"
			killsOn[victim] = (killsOn[victim] or 0) + 1
			if killsOn[victim] > Economy.SAME_VICTIM_FULL_KILLS then
				factor *= Economy.SAME_VICTIM_FACTOR
			end
			add(if event.VictimAI then "Kills (AI)" else "Kills", event.Airframe, "Kill", factor)
		elseif Economy.ACTIONS[event.Kind] then
			local label = if event.Kind == "MissileDefeated"
				then "Missiles defeated"
				elseif event.Kind == "Assist" then "Assists"
				else event.Kind
			add(label, event.Airframe, event.Kind, 1)
		end
	end

	local last = summary.LastAirframe
	if last then
		add("Match completed", last, "Participation", 1)
		if summary.Survived and not summary.Afk then
			add("Survived", last, "Survived", 1)
		end
	end

	-- Bonuses multiply everything above
	local multiplier = 1
	if summary.Won and not summary.Afk then
		multiplier *= 1 + Economy.WIN_BONUS
		if summary.Day ~= lastWinDay then
			multiplier *= Economy.FIRST_WIN_OF_DAY
			rewards.FirstWin = true
		end
	end
	if multiplier ~= 1 then
		local extra = multiplier - 1
		local bonusLine = {
			Label = if rewards.FirstWin then "Win (first of the day)" else "Win",
			XP = rewards.XP * extra,
			RP = 0,
			Credits = rewards.Credits * extra,
		}
		for airframe, rp in rewards.RP do
			bonusLine.RP += rp * extra
			rewards.RP[airframe] = rp * multiplier
		end
		rewards.XP *= multiplier
		rewards.Credits *= multiplier
		table.insert(rewards.Lines, bonusLine)
	end

	-- A live event (LiveConfig economy.*): its own line with what it added
	local boost = summary.Boost
	if boost and (boost.XP ~= 1 or boost.Credits ~= 1 or boost.RP ~= 1) then
		local boostLine = {
			Label = boost.Label,
			XP = rewards.XP * (boost.XP - 1),
			RP = 0,
			Credits = rewards.Credits * (boost.Credits - 1),
		}
		for airframe, rp in rewards.RP do
			boostLine.RP += rp * (boost.RP - 1)
			rewards.RP[airframe] = rp * boost.RP
		end
		rewards.XP *= boost.XP
		rewards.Credits *= boost.Credits
		table.insert(rewards.Lines, boostLine)
	end

	-- Whole numbers only
	rewards.XP = math.floor(rewards.XP + 0.5)
	rewards.Credits = math.floor(rewards.Credits + 0.5)
	local totalRP = 0
	for airframe, rp in rewards.RP do
		rewards.RP[airframe] = math.floor(rp + 0.5)
		totalRP += rewards.RP[airframe]
	end
	rewards.FreeRP = math.floor(totalRP * Economy.FREE_RP_SHARE + 0.5)
	for _, line in rewards.Lines do
		line.XP, line.RP, line.Credits =
			math.floor(line.XP + 0.5), math.floor(line.RP + 0.5), math.floor(line.Credits + 0.5)
	end
	return rewards
end

-- Pilot level -----------------------------------------------------------------------------------

-- Pays the Credits and Free RP milestones (Config/LevelRewards) for every level reached and not yet paid,
-- once each. Run on levelling up and on joining (so levels reached before the milestones existed count).
-- Returns the milestones paid.
function Progression.claimLevelRewards(data: { [string]: any }): { LevelRewards.Milestone }
	local paid = {}
	local claimed = data.LevelRewardsClaimed or 0
	for _, milestone in LevelRewards.MILESTONES do
		if milestone.Level > claimed and milestone.Level <= data.PilotLevel then
			if milestone.Kind == "Credits" then
				data.Credits += milestone.Amount :: number
				table.insert(paid, milestone)
			elseif milestone.Kind == "FreeRP" then
				data.FreeRP += milestone.Amount :: number
				table.insert(paid, milestone)
			end
		end
	end
	data.LevelRewardsClaimed = math.max(claimed, data.PilotLevel)
	return paid
end

-- Adds XP, levelling up as needed (each level pays Economy.LEVEL_CREDITS, plus its milestones).
-- Returns levels gained.
function Progression.addXP(data: { [string]: any }, amount: number): number
	data.TotalXP += amount
	data.PilotXP += amount
	local gained = 0
	while data.PilotLevel < Economy.MAX_LEVEL and data.PilotXP >= Economy.xpToNext(data.PilotLevel) do
		data.PilotXP -= Economy.xpToNext(data.PilotLevel)
		data.PilotLevel += 1
		data.Credits += Economy.LEVEL_CREDITS
		gained += 1
	end
	if data.PilotLevel >= Economy.MAX_LEVEL then
		data.PilotXP = 0
	end
	if gained > 0 then
		Progression.claimLevelRewards(data)
	end
	return gained
end

function Progression.lineupSlots(level: number, allUnlocked: boolean?): number
	local slots = 1
	for _, step in Economy.LINEUP_SLOTS do
		if allUnlocked or level >= step.level then
			slots = math.max(slots, step.slots)
		end
	end
	return slots
end

-- Lineup slots for a save (all of them with full access, see unlockEverything).
function Progression.slotsFor(data: { [string]: any }): number
	return Progression.lineupSlots(data.PilotLevel, data.Flags and data.Flags.AllUnlocked == true)
end

-- Applies match rewards to a save. Returns levels gained.
function Progression.applyRewards(data: { [string]: any }, rewards: Rewards, summary: MatchSummary): number
	data.Credits += rewards.Credits
	data.FreeRP += rewards.FreeRP
	for airframe, rp in rewards.RP do
		local entry = data.Aircraft[airframe]
		if entry then
			entry.RP += rp
		end
	end
	local stats = data.Stats
	stats.Matches += 1
	for _, event in summary.Events do
		if event.Kind == "Kill" then
			if event.VictimAI then
				stats.AIKills += 1
			else
				stats.Kills += 1
			end
		end
	end
	if not summary.Survived then
		stats.Deaths += 1
	end
	if summary.Won and not summary.Afk then
		stats.Wins += 1
		data.LastWinDay = summary.Day
	end
	return Progression.addXP(data, rewards.XP)
end

-- Research and purchase -------------------------------------------------------------------------

export type ResearchPlan = { From: string?, FromJet: number, FromFree: number }

-- Whether a node can be researched now, and where the RP would come from: the owned prerequisite with
-- the most RP first, then the free pool.
function Progression.researchPlan(data: { [string]: any }, id: string): (ResearchPlan?, string?)
	local node = TechTree.get(id)
	if not node then
		return nil, "Unknown aircraft"
	end
	local entry = data.Aircraft[id]
	if entry and entry.Researched then
		return nil, "Already researched"
	end
	local best, bestRP = nil, -1
	for _, requirement in node.Requires do
		local owned = data.Aircraft[requirement]
		if owned and owned.Owned and owned.RP > bestRP then
			best, bestRP = requirement, owned.RP
		end
	end
	if not best then
		return nil, "Own a required jet first"
	end
	local fromJet = math.min(bestRP, node.RP)
	local fromFree = node.RP - fromJet
	if fromFree > data.FreeRP then
		return nil, `Needs {node.RP - bestRP - data.FreeRP} more RP`
	end
	return { From = best, FromJet = fromJet, FromFree = fromFree }, nil
end

function Progression.research(data: { [string]: any }, id: string): (boolean, string?)
	local plan, err = Progression.researchPlan(data, id)
	if not plan then
		return false, err
	end
	if plan.From then
		data.Aircraft[plan.From].RP -= plan.FromJet
	end
	data.FreeRP -= plan.FromFree
	local entry = data.Aircraft[id] or PlayerData.newAircraft(false)
	entry.Researched = true
	data.Aircraft[id] = entry
	return true, nil
end

function Progression.canBuy(data: { [string]: any }, id: string): (boolean, string?)
	local node = TechTree.get(id)
	if not node then
		return false, "Unknown aircraft"
	end
	local entry = data.Aircraft[id]
	if entry and entry.Owned then
		return false, "Already owned"
	end
	if not (entry and entry.Researched) then
		return false, "Research it first"
	end
	if data.Credits < node.Credits then
		return false, `Needs {node.Credits - data.Credits} more Credits`
	end
	return true, nil
end

function Progression.buy(data: { [string]: any }, id: string): (boolean, string?)
	local ok, err = Progression.canBuy(data, id)
	if not ok then
		return false, err
	end
	local node = TechTree.get(id) :: TechTree.Node
	data.Credits -= node.Credits
	data.Aircraft[id].Owned = true
	-- A new jet goes straight into a free lineup slot
	if #data.Lineup < Progression.slotsFor(data) then
		table.insert(data.Lineup, id)
	end
	return true, nil
end

-- Modules ----------------------------------------------------------------------------------------
-- Aircraft[id].Modules[moduleId] is true when the module is fitted, false when it's owned but taken
-- off. Buying fits it; fitting and unfitting an owned module afterwards is free.

function Progression.moduleDef(moduleId: string): Economy.ModuleDef?
	for _, def in Economy.MODULES do
		if def.Id == moduleId then
			return def
		end
	end
	return nil
end

-- RP and Credits for a module on a given jet (costs scale with its tier).
function Progression.moduleCost(airframeId: string, def: Economy.ModuleDef): (number, number)
	local tier = tierMultiplier(airframeId)
	return math.floor(def.RP * tier + 0.5), math.floor(def.Credits * tier + 0.5)
end

function Progression.canBuyModule(data: { [string]: any }, airframeId: string, moduleId: string): (boolean, string?)
	local entry = data.Aircraft[airframeId]
	if not (entry and entry.Owned) then
		return false, "You don't own this jet"
	end
	local def = Progression.moduleDef(moduleId)
	if not def then
		return false, "Unknown module"
	end
	if entry.Modules[moduleId] ~= nil then
		return false, if entry.Modules[moduleId] then "Already fitted" else "Already owned: fit it"
	end
	if def.Requires and not entry.Modules[def.Requires] then
		local required = Progression.moduleDef(def.Requires)
		return false, `Fit {if required then required.DisplayName else def.Requires} first`
	end
	local rp, credits = Progression.moduleCost(airframeId, def)
	if entry.RP < rp then
		return false, `Needs {rp - entry.RP} more RP on this jet`
	end
	if data.Credits < credits then
		return false, `Needs {credits - data.Credits} more Credits`
	end
	return true, nil
end

function Progression.buyModule(data: { [string]: any }, airframeId: string, moduleId: string): (boolean, string?)
	local ok, err = Progression.canBuyModule(data, airframeId, moduleId)
	if not ok then
		return false, err
	end
	local def = Progression.moduleDef(moduleId) :: Economy.ModuleDef
	local rp, credits = Progression.moduleCost(airframeId, def)
	local entry = data.Aircraft[airframeId]
	entry.RP -= rp
	data.Credits -= credits
	entry.Modules[moduleId] = true
	return true, nil
end

-- Whether an owned module can be fitted (fitted = true) or taken off. A module can't come off while a
-- module built on it (its Requires) is fitted, and goes back on only once its own Requires is fitted.
function Progression.canSetModuleFitted(
	data: { [string]: any },
	airframeId: string,
	moduleId: string,
	fitted: boolean
): (boolean, string?)
	local entry = data.Aircraft[airframeId]
	if not (entry and entry.Owned) then
		return false, "You don't own this jet"
	end
	local def = Progression.moduleDef(moduleId)
	if not def or type(fitted) ~= "boolean" then
		return false, "Unknown module"
	end
	local state = entry.Modules[moduleId]
	if state == nil then
		return false, "Buy this module first"
	end
	if state == fitted then
		return false, if fitted then "Already fitted" else "Not fitted"
	end
	if fitted then
		if def.Requires and not entry.Modules[def.Requires] then
			local required = Progression.moduleDef(def.Requires)
			return false, `Fit {if required then required.DisplayName else def.Requires} first`
		end
	else
		for _, other in Economy.MODULES do
			if other.Requires == moduleId and entry.Modules[other.Id] then
				return false, `Unfit {other.DisplayName} first`
			end
		end
	end
	return true, nil
end

function Progression.setModuleFitted(
	data: { [string]: any },
	airframeId: string,
	moduleId: string,
	fitted: boolean
): (boolean, string?)
	local ok, err = Progression.canSetModuleFitted(data, airframeId, moduleId, fitted)
	if ok then
		data.Aircraft[airframeId].Modules[moduleId] = fitted
	end
	return ok, err
end

-- The airframe with its fitted modules applied (a modified copy; the original is never changed).
function Progression.applyModules(airframe: { [string]: any }, modules: { [string]: boolean }?): { [string]: any }
	local result = table.clone(airframe)
	if not modules then
		return result
	end
	for moduleId, fitted in modules do
		local def = fitted and Progression.moduleDef(moduleId)
		if def then
			for effect, value in def.Effects do
				-- "<Field>X" multiplies, "<Field>Plus" adds
				local plus = string.match(effect, "^(.+)Plus$")
				local field = plus or string.match(effect, "^(.+)X$")
				local op = if plus then "Plus" else "X"
				if field == "RadarRange" and result.Radar then
					result.Radar = table.clone(result.Radar)
					result.Radar.Range *= value
				elseif (field == "Flares" or field == "Chaff") and result.Countermeasures then
					result.Countermeasures = table.clone(result.Countermeasures)
					result.Countermeasures[field] = math.floor(result.Countermeasures[field] * value + 0.5)
				elseif field and type(result[field]) == "number" then
					result[field] = if op == "X" then result[field] * value else result[field] + value
				end
			end
		end
	end
	return result
end

-- Fitted modules travel on the jet model as a comma list ("Engine1,Airframe1").
function Progression.encodeModules(modules: { [string]: boolean }?): string
	local ids = {}
	for id, fitted in modules or {} do
		if fitted and Progression.moduleDef(id) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

function Progression.decodeModules(text: string?): { [string]: boolean }
	local modules = {}
	for id in string.gmatch(text or "", "[^,]+") do
		modules[id] = true
	end
	return modules
end

-- The airframe a jet actually flies: its data with the modules on its model applied.
function Progression.airframeForModel(model: Instance): { [string]: any }?
	local airframe = AircraftData.get(model:GetAttribute("AirframeId") :: string)
	if not airframe then
		return nil
	end
	return Progression.applyModules(
		airframe :: any,
		Progression.decodeModules(model:GetAttribute("Modules") :: string?)
	)
end

-- Lineup -----------------------------------------------------------------------------------------

function Progression.setLineup(data: { [string]: any }, ids: { any }): (boolean, string?)
	if type(ids) ~= "table" or #ids == 0 then
		return false, "Pick at least one jet"
	end
	local slots = Progression.slotsFor(data)
	if #ids > slots then
		return false, `Only {slots} lineup slot{if slots == 1 then "" else "s"} at your level`
	end
	local seen = {}
	for _, id in ids do
		if type(id) ~= "string" then
			return false, "Bad lineup"
		end
		local entry = data.Aircraft[id]
		if not (entry and entry.Owned) then
			return false, "You don't own that jet"
		end
		if seen[id] then
			return false, "A jet can only be in the lineup once"
		end
		seen[id] = true
	end
	data.Lineup = table.clone(ids)
	return true, nil
end

-- Skins ------------------------------------------------------------------------------------------
-- Aircraft[id].Skins[skinId] = true for skins bought; the default skin is always owned. Aircraft[id].Camo
-- is the skin in use.

function Progression.ownsSkin(data: { [string]: any }, airframeId: string, skinId: string): boolean
	local entry = data.Aircraft[airframeId]
	if not (entry and entry.Owned and Skins.get(airframeId, skinId)) then
		return false
	end
	local skin = Skins.get(airframeId, skinId) :: any
	if skin.Level then
		return data.PilotLevel >= skin.Level or (data.Flags and data.Flags.AllUnlocked == true)
	end
	return skinId == Skins.default(airframeId) or (entry.Skins ~= nil and entry.Skins[skinId] == true)
end

-- The skin a player's jet spawns in: their choice if they own it, otherwise the default.
function Progression.skinFor(data: { [string]: any }, airframeId: string): string
	local entry = data.Aircraft[airframeId]
	local chosen = entry and entry.Camo
	if type(chosen) == "string" and Progression.ownsSkin(data, airframeId, chosen) then
		return chosen
	end
	return Skins.default(airframeId)
end

-- currency: "Credits" (the default) or "Wings" (SHP-04).
function Progression.canBuySkin(
	data: { [string]: any },
	airframeId: string,
	skinId: string,
	currency: string?
): (boolean, string?)
	local entry = data.Aircraft[airframeId]
	if not (entry and entry.Owned) then
		return false, "You don't own this jet"
	end
	local skin = Skins.get(airframeId, skinId)
	if not skin then
		return false, "Unknown skin"
	end
	if Progression.ownsSkin(data, airframeId, skinId) then
		return false, "Already owned"
	end
	if skin.Level then
		return false, `Unlocks at pilot level {skin.Level}`
	end
	if currency == "Wings" then
		local price = Skins.wingsPrice(skin)
		if not price then
			return false, "Not sold for Wings"
		end
		local wings = data.Wings or 0
		if wings < price then
			return false, `Needs {price - wings} more Wings`
		end
		return true, nil
	elseif currency ~= nil and currency ~= "Credits" then
		return false, "Unknown currency"
	end
	local price = skin.Credits or 0
	if data.Credits < price then
		return false, `Needs {price - data.Credits} more Credits`
	end
	return true, nil
end

-- Buys a skin and puts it on.
function Progression.buySkin(
	data: { [string]: any },
	airframeId: string,
	skinId: string,
	currency: string?
): (boolean, string?)
	local ok, err = Progression.canBuySkin(data, airframeId, skinId, currency)
	if not ok then
		return false, err
	end
	local entry = data.Aircraft[airframeId]
	local skin = Skins.get(airframeId, skinId) :: any
	if currency == "Wings" then
		data.Wings -= Skins.wingsPrice(skin) :: number
	else
		data.Credits -= skin.Credits or 0
	end
	entry.Skins = entry.Skins or {}
	entry.Skins[skinId] = true
	entry.Camo = skinId
	return true, nil
end

function Progression.setSkin(data: { [string]: any }, airframeId: string, skinId: string): (boolean, string?)
	if not Progression.ownsSkin(data, airframeId, skinId) then
		return false, "You don't own that skin"
	end
	data.Aircraft[airframeId].Camo = skinId
	return true, nil
end

-- Full access --------------------------------------------------------------------------------------
-- The game's owner (and admins) get every jet, module, skin and lineup slot, in test and live, without
-- touching currency. Applied on every join, so new content shows up for them straight away.

function Progression.unlockEverything(data: { [string]: any })
	local ids = {}
	for id in AircraftData.getAll() do
		ids[id] = true
	end
	for id in ids do
		local entry = data.Aircraft[id]
		if not entry then
			entry = PlayerData.newAircraft(true)
			data.Aircraft[id] = entry
		end
		entry.Owned = true
		entry.Researched = true
		for _, def in Economy.MODULES do
			if entry.Modules[def.Id] == nil then
				entry.Modules[def.Id] = false -- owned, not fitted
			end
		end
		entry.Skins = entry.Skins or {}
		for _, skin in Skins.list(id) do
			if not skin.Default then
				entry.Skins[skin.Id] = true
			end
		end
	end
	data.Flags.AllUnlocked = true
end

return Progression
