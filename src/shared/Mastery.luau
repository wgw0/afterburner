--!strict
-- Aircraft mastery (DESIGN §7.5, DEVELOPMENT.md §23.8, PRG-07). Each jet earns up to 5 stars from kills made
-- in it during scored matches (data.Aircraft[id].Mastery holds the count). Each star pays Credits; from 2 stars
-- the jet carries kill markers under the canopy (KillMarkers), and 5 stars gives the "<jet> Ace" title.
-- A mastery camo and a cockpit trinket come later with art (Will, November 2026). Pure.

local AircraftData = require(script.Parent.AircraftData)
local Economy = require(script.Parent.Config.Economy)

local Mastery = {}

Mastery.STARS = table.freeze({ 5, 15, 40, 80, 150 }) -- kills for each star
Mastery.CREDITS = table.freeze({ 2000, 4000, 8000, 12000, 20000 }) -- paid on reaching each star
Mastery.MARKERS_FROM = 2 -- stars before the jet shows kill markers
Mastery.TITLE_PREFIX = "Mastery:" -- title ids are "Mastery:<airframe id>"

-- What the 5-star title calls each jet; others fall back to "<DisplayName> Ace".
local TITLE_NAMES: { [string]: string } = {
	F14A = "Tomcat",
	F15C = "Eagle",
	F15E = "Strike Eagle",
	F16A = "F-16A",
	F16C = "F-16C",
	F22A = "Raptor",
	F35A = "Lightning",
	F4E = "Phantom",
	F5E = "Tiger",
	FA18C = "Hornet",
	FA18E = "Super Hornet",
	GripenC = "Gripen",
	MiG21bis = "MiG-21",
	MiG23MLD = "MiG-23",
	MiG29A = "MiG-29A",
	MiG29SMT = "MiG-29SMT",
	Mirage2000C = "Mirage 2000",
	MirageF1 = "Mirage F1",
	MirageIII = "Mirage III",
	RafaleC = "Rafale",
	Su27S = "Su-27",
	Su30SM = "Su-30",
	Su35S = "Su-35",
	Su57 = "Su-57",
	Tempest = "Tempest",
	TornadoF3 = "Tornado",
	Typhoon = "Typhoon",
}

-- Stars for a kill count (0–5).
function Mastery.stars(kills: number): number
	local stars = 0
	for i, needed in Mastery.STARS do
		if kills >= needed then
			stars = i
		end
	end
	return stars
end

-- Progress to the next star: (kills into it, kills it needs), or nil at 5 stars.
function Mastery.progress(kills: number): (number?, number?)
	local stars = Mastery.stars(kills)
	local nextAt = Mastery.STARS[stars + 1]
	if not nextAt then
		return nil, nil
	end
	local from = Mastery.STARS[stars] or 0
	return kills - from, nextAt - from
end

-- "★★★☆☆"
function Mastery.starText(stars: number): string
	return string.rep("★", stars) .. string.rep("☆", #Mastery.STARS - stars)
end

function Mastery.titleId(airframeId: string): string
	return Mastery.TITLE_PREFIX .. airframeId
end

-- The title's name for a mastery title id ("Tomcat Ace"), or nil if it isn't one.
function Mastery.titleName(titleId: string): string?
	if string.sub(titleId, 1, #Mastery.TITLE_PREFIX) ~= Mastery.TITLE_PREFIX then
		return nil
	end
	local airframeId = string.sub(titleId, #Mastery.TITLE_PREFIX + 1)
	local airframe = AircraftData.get(airframeId) :: any
	if not airframe then
		return nil
	end
	return `{TITLE_NAMES[airframeId] or airframe.DisplayName} Ace`
end

-- Kills per jet that count towards mastery from a match's events: the same victim counts only as often as
-- it pays full rewards (Economy.SAME_VICTIM_FULL_KILLS), so farming one pilot doesn't earn stars.
function Mastery.countKills(events: { any }): { [string]: number }
	local perJet: { [string]: number } = {}
	local perVictim: { [string]: number } = {}
	for _, event in events do
		if event.Kind == "Kill" and event.Airframe then
			local victim = event.Victim
			local counted = true
			if victim then
				perVictim[victim] = (perVictim[victim] or 0) + 1
				counted = perVictim[victim] <= Economy.SAME_VICTIM_FULL_KILLS
			end
			if counted then
				perJet[event.Airframe] = (perJet[event.Airframe] or 0) + 1
			end
		end
	end
	return perJet
end

export type Gain = { Airframe: string, Stars: number, Credits: number, Title: string? }

-- Adds a match's kills to the save's mastery and pays each star reached: Credits, and the title at 5.
-- Returns the stars gained, in order.
function Mastery.record(data: { [string]: any }, events: { any }): { Gain }
	local gains: { Gain } = {}
	local ids = {}
	local perJet = Mastery.countKills(events)
	for airframeId in perJet do
		table.insert(ids, airframeId)
	end
	table.sort(ids)
	for _, airframeId in ids do
		local entry = data.Aircraft[airframeId]
		if entry then
			local before = Mastery.stars(entry.Mastery or 0)
			entry.Mastery = (entry.Mastery or 0) + perJet[airframeId]
			for star = before + 1, Mastery.stars(entry.Mastery) do
				local credits = Mastery.CREDITS[star]
				data.Credits += credits
				local gain: Gain = { Airframe = airframeId, Stars = star, Credits = credits }
				if star == #Mastery.STARS then
					gain.Title = Mastery.titleId(airframeId)
					data.Titles[gain.Title] = true
				end
				table.insert(gains, gain)
			end
		end
	end
	return gains
end

return Mastery
