--!strict
-- Economy values (DESIGN §7, DEVELOPMENT.md §23). Shared so the menus can show costs; every rule that
-- grants or spends anything runs on the server. Starting points: tune them with tools/EconomySim.
-- Re-run the economy simulation (PRG-06) whenever a number here changes.

local Economy = {}

-- Per action in a match: XP to the account, RP to the jet flown, Credits.
Economy.ACTIONS = table.freeze({
	Kill = { XP = 100, RP = 100, Credits = 150 },
	Assist = { XP = 50, RP = 50, Credits = 75 },
	MissileDefeated = { XP = 15, RP = 15, Credits = 20 },
	ZoneCaptured = { XP = 75, RP = 75, Credits = 100 },
	Survived = { XP = 50, RP = 50, Credits = 50 },
	Participation = { XP = 20, RP = 20, Credits = 30 }, -- for finishing a match at all
})

Economy.WIN_BONUS = 0.3 -- +30% on everything
Economy.FIRST_WIN_OF_DAY = 2 -- ×2
Economy.BOOSTER_CAP = 2 -- every multiplier together never exceeds ×2 (VIP, boosters; Phase 7)

-- Higher tiers earn more RP and Credits per action (and cost more), XP is the same everywhere.
Economy.TIER_MULTIPLIER = table.freeze({ 1.0, 1.3, 1.6, 2.0, 2.4, 2.8, 3.2, 3.5 })

Economy.FREE_RP_SHARE = 0.1 -- of every RP award, also paid into a pool spendable on any jet

-- Anti-farming (PRG-05)
Economy.AI_KILL_FACTOR = 0.5 -- kills on AI pilots pay half
Economy.VS_AI_XP = 0.5 -- Vs AI on a training server pays pilot XP only, this share of a match's *(tune in playtests)*
Economy.SAME_VICTIM_FULL_KILLS = 3 -- after this many kills on one victim in a match...
Economy.SAME_VICTIM_FACTOR = 0.25 -- ...each further kill on them pays a quarter
Economy.AFK_SECONDS = 60 -- no input this long at the end: no survival or win bonus

-- Research (RP) and purchase (Credits) costs in TechTree are multiplied by this per tier (Will, November
-- 2026: Tier II in 20–30 minutes, then scaling up; DESIGN §7.3). Tune the pace here; tools/EconomySim checks it.
Economy.TECH_COST_SCALE = table.freeze({ 0.33, 0.1, 0.13, 0.21, 0.22, 0.26, 0.3, 0.15 })

Economy.STARTING_CREDITS = 500
Economy.STARTERS = table.freeze({ "F5E", "MiG21bis" }) -- owned by every new account

-- Pilot level (PRG-03)
function Economy.xpToNext(level: number): number
	return math.floor(500 + 150 * level ^ 1.35)
end
Economy.MAX_LEVEL = 100
Economy.LINEUP_SLOTS = table.freeze({ { level = 1, slots = 1 }, { level = 5, slots = 2 }, { level = 15, slots = 3 } })
Economy.LEVEL_CREDITS = 250 -- Credits for every level gained

-- Upgrade modules (PRG-04). Costs are for a Tier I jet and scale with the tier multiplier
-- and TECH_COST_SCALE (Progression.moduleCost). Effects are
-- applied to the airframe at spawn; stock is about 85–90% of fully upgraded (DESIGN §7.4).
export type ModuleDef = {
	Id: string,
	DisplayName: string,
	Requires: string?, -- another module that must be bought first
	RP: number,
	Credits: number,
	Effects: { [string]: number }, -- multipliers ("x") or additions ("+"), see Progression.applyModules
}

Economy.MODULES = table.freeze({
	{
		Id = "Engine1",
		DisplayName = "Engine I",
		RP = 150,
		Credits = 300,
		Effects = { MaxThrustX = 1.03 },
	},
	{
		Id = "Engine2",
		DisplayName = "Engine II",
		Requires = "Engine1",
		RP = 300,
		Credits = 600,
		Effects = { MaxThrustX = 1.03 },
	},
	{
		Id = "Airframe1",
		DisplayName = "Airframe I",
		RP = 150,
		Credits = 300,
		Effects = { MaxGPlus = 0.25, MaxRollRateX = 1.04 },
	},
	{
		Id = "Airframe2",
		DisplayName = "Airframe II",
		Requires = "Airframe1",
		RP = 300,
		Credits = 600,
		Effects = { MaxGPlus = 0.25, MaxRollRateX = 1.04 },
	},
	{
		Id = "Avionics1",
		DisplayName = "Avionics I",
		RP = 200,
		Credits = 400,
		Effects = { RadarRangeX = 1.15 },
	},
	{
		Id = "Countermeasures1",
		DisplayName = "Countermeasures I",
		RP = 120,
		Credits = 250,
		Effects = { FlaresX = 1.5, ChaffX = 1.5 },
	},
	-- The second wave (Will: more upgrades per jet). Smaller steps than the first six, so a stock jet stays
	-- close to a fully upgraded one *(tune in playtests)*.
	{
		Id = "Engine3",
		DisplayName = "Engine III",
		Requires = "Engine2",
		RP = 450,
		Credits = 900,
		Effects = { MaxThrustX = 1.02 },
	},
	{
		Id = "Afterburner",
		DisplayName = "Afterburner Tuning",
		Requires = "Engine1",
		RP = 250,
		Credits = 500,
		Effects = { AfterburnerMultX = 1.03 },
	},
	{
		Id = "FuelSystem",
		DisplayName = "Fuel System",
		RP = 150,
		Credits = 300,
		Effects = { FuelBurnDryX = 0.9, FuelBurnABX = 0.9 },
	},
	{
		Id = "ExtraFuel",
		DisplayName = "Extra Fuel",
		RP = 120,
		Credits = 250,
		Effects = { FuelX = 1.15 },
	},
	{
		Id = "Airframe3",
		DisplayName = "Airframe III",
		Requires = "Airframe2",
		RP = 450,
		Credits = 900,
		Effects = { MaxGPlus = 0.25, MaxRollRateX = 1.03 },
	},
	{
		Id = "Aero",
		DisplayName = "Aerodynamic Refinement",
		Requires = "Airframe1",
		RP = 300,
		Credits = 600,
		Effects = { CD0X = 0.96 },
	},
	{
		Id = "HighLift",
		DisplayName = "High-Lift Devices",
		RP = 250,
		Credits = 500,
		Effects = { CLMaxX = 1.04, CriticalAoAPlus = 1 },
	},
	{
		Id = "Lightweight",
		DisplayName = "Weight Reduction",
		Requires = "Airframe2",
		RP = 400,
		Credits = 800,
		Effects = { MassX = 0.97 },
	},
	{
		Id = "FlightControls",
		DisplayName = "Flight Controls",
		RP = 200,
		Credits = 400,
		Effects = { MaxPitchRateX = 1.04, MaxYawRateX = 1.08 },
	},
	{
		Id = "Avionics2",
		DisplayName = "Avionics II",
		Requires = "Avionics1",
		RP = 350,
		Credits = 700,
		Effects = { RadarRangeX = 1.1 },
	},
	{
		Id = "Countermeasures2",
		DisplayName = "Countermeasures II",
		Requires = "Countermeasures1",
		RP = 250,
		Credits = 500,
		Effects = { FlaresX = 1.33, ChaffX = 1.33 },
	},
	{
		Id = "AmmoBelt",
		DisplayName = "Ammunition Belt",
		RP = 150,
		Credits = 300,
		Effects = { GunAmmoX = 1.25 },
	},
} :: { ModuleDef })

return Economy
