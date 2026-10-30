--!strict
-- What the game passes and boosters give (DESIGN §8.2, SHP-03). Never power: more Credits / RP from matches,
-- an extra lineup slot, an extra challenge reroll. Pass ownership is mirrored into the save as data.Passes
-- by PassService (checked with Roblox on every join and purchase); boosters are data.Boosters, the unix time
-- each one runs out. Pure.

local Perks = {}

Perks.VIP_CREDITS = 1.25 -- VIP Pilot: +25% Credits
Perks.BOOSTER = 2 -- a booster doubles Credits or RP
Perks.CAP = 2 -- the most a player's own perks multiply rewards by (VIP and a booster don't stack past ×2)
Perks.BOOSTER_SECONDS = 60 * 60 -- an hour; buying another adds an hour

function Perks.owns(data: { [string]: any }, pass: string): boolean
	return data.Passes ~= nil and data.Passes[pass] == true
end

-- Seconds left on a booster ("Credits" or "RP"), 0 if it isn't running.
function Perks.boosterLeft(data: { [string]: any }, kind: string, now: number): number
	local untilTime = data.Boosters and data.Boosters[kind] or 0
	return math.max(untilTime - now, 0)
end

-- Starts a booster, or adds an hour to one already running.
function Perks.extendBooster(data: { [string]: any }, kind: string, now: number)
	data.Boosters = data.Boosters or {}
	data.Boosters[kind] = math.max(data.Boosters[kind] or 0, now) + Perks.BOOSTER_SECONDS
end

export type Boost = { Credits: number, RP: number, Label: string }

-- The player's own multipliers on match rewards right now, or nil if they have none.
function Perks.boost(data: { [string]: any }, now: number): Boost?
	local vip = Perks.owns(data, "VIP")
	local creditsBooster = Perks.boosterLeft(data, "Credits", now) > 0
	local rpBooster = Perks.boosterLeft(data, "RP", now) > 0
	if not (vip or creditsBooster or rpBooster) then
		return nil
	end
	local credits = (if vip then Perks.VIP_CREDITS else 1) * (if creditsBooster then Perks.BOOSTER else 1)
	local parts = {}
	if vip then
		table.insert(parts, "VIP")
	end
	if creditsBooster or rpBooster then
		table.insert(parts, "Booster")
	end
	return {
		Credits = math.min(credits, Perks.CAP),
		RP = math.min(if rpBooster then Perks.BOOSTER else 1, Perks.CAP),
		Label = table.concat(parts, " + "),
	}
end

-- Lineup slots a save gets on top of its level's (the Extra Lineup Slot pass).
function Perks.extraSlots(data: { [string]: any }): number
	return if Perks.owns(data, "ExtraLineupSlot") then 1 else 0
end

-- Daily challenge rerolls (VIP gets one more).
function Perks.rerolls(data: { [string]: any }, base: number): number
	return base + (if Perks.owns(data, "VIP") then 1 else 0)
end

return Perks
