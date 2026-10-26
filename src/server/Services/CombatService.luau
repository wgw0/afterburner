--!strict
-- Guns and damage, server-authoritative (DEVELOPMENT.md §11–12).
--
-- The client only says "trigger down" / "trigger up" (with a spread seed). The server fires the rounds
-- itself at the gun's rate, flies them with Ballistics, and checks each round's path against the other
-- jets' hitboxes *where the shooter saw them* (rewound by the shooter's latency). Hits apply damage
-- through DamageModel; when a jet is destroyed, credit goes to the right players and everyone is told.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Ballistics = require(Shared.Ballistics)
local DamageModel = require(Shared.DamageModel)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Units = require(Shared.Units)
local WeaponData = require(Shared.WeaponData)

local AircraftService = require(script.Parent.AircraftService)
local HistoryService = require(script.Parent.HistoryService)

type Jet = AircraftService.Jet

local FIRE_TIME_TOLERANCE = 1 -- seconds: trigger messages stamped further from now are ignored
local JAM_CLEAR_HEAT = 0.4 -- an overheated gun works again once it cools to this
local BROADPHASE_MARGIN = 60 -- studs around a round's path to consider a target
local FIRE_CHANCE = 0.1 -- per engine hit once the engine is below half health (DMG-03)
local FIRE_DURATION = 8 -- seconds
local FIRE_DPS = 6 -- fuselage damage per second while burning
local SMOKE_BELOW = 0.6 -- engine health fraction that starts trailing smoke

type Hitbox = { name: string, offset: CFrame, size: Vector3 }

type Firing = { seed: number, index: number, timer: number }

type CombatState = {
	jet: Jet,
	gun: WeaponData.Gun?,
	health: DamageModel.Health,
	maxHealth: DamageModel.Health,
	ammo: number,
	heat: number,
	jammed: boolean,
	firing: Firing?,
	rounds: { Ballistics.Round },
	attackers: { [any]: DamageModel.DamageRecord },
	attackerWeapon: { [any]: string },
	hitboxes: { Hitbox },
	muzzle: Attachment?,
}

local CombatService = {
	Priority = 30,
	JetDamaged = Signal.new(), -- (jet, component, amount, attackerPlayer?)
	Kill = Signal.new(), -- (victimJet, credit, cause)
}

local states: { [number]: CombatState } = {}
local fires: { [number]: { untilTime: number, attacker: any? } } = {}
local worldParams: RaycastParams

local function otherPlayers(except: Player?): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player ~= except then
			table.insert(list, player)
		end
	end
	return list
end

local function readHitboxes(jet: Jet): { Hitbox }
	local boxes = {}
	local folder = jet.model:FindFirstChild("Hitboxes")
	if folder then
		for _, part in folder:GetChildren() do
			if part:IsA("BasePart") then
				table.insert(
					boxes,
					{ name = part.Name, offset = jet.root.CFrame:ToObjectSpace(part.CFrame), size = part.Size }
				)
			end
		end
	end
	return boxes
end

function CombatService:GetFractions(jetId: number): { [string]: number }?
	local state = states[jetId]
	return state and DamageModel.fractions(state.health, state.maxHealth)
end

local function sendDamageState(state: CombatState)
	local pilot = state.jet.pilot
	if pilot then
		Net.Server.fire("DamageState", pilot, DamageModel.fractions(state.health, state.maxHealth))
	end
end

-- Applies damage to a jet. attacker is a pilot identity (Player or AI record), or nil for environmental damage.
function CombatService:ApplyDamage(target: Jet, component: string, amount: number, attacker: any?, weapon: string)
	local state = states[target.id]
	if not state or AircraftService:GetJetById(target.id) == nil then
		return -- already destroyed (e.g. by an earlier round this tick)
	end
	local health, destroyed = DamageModel.applyDamage(state.health, component, amount)
	state.health = health
	if attacker then
		local record = state.attackers[attacker] or { damage = 0, time = 0 }
		record.damage += amount
		record.time = os.clock()
		state.attackers[attacker] = record
		state.attackerWeapon[attacker] = weapon
	end
	sendDamageState(state)
	self.JetDamaged:Fire(target, component, amount, attacker)

	-- Engine damage: smoke, and a chance of fire once it's badly hit (DMG-03)
	local engine = (state.health.Engine or 0) / (state.maxHealth.Engine or 1)
	target.model:SetAttribute("Smoking", engine < SMOKE_BELOW)
	if component == "Engine" and engine < 0.5 and not fires[target.id] and math.random() < FIRE_CHANCE then
		fires[target.id] = { untilTime = os.clock() + FIRE_DURATION, attacker = attacker }
		target.model:SetAttribute("OnFire", true)
	end
	if destroyed then
		AircraftService:Despawn(target, "Shot")
	end
end

local function stopFiring(state: CombatState)
	if state.firing then
		state.firing = nil
		Net.Server.fireList(
			"GunFireFx",
			otherPlayers(state.jet.pilot),
			state.jet.id,
			false,
			0,
			workspace:GetServerTimeNow()
		)
	end
end

-- Pulls or releases a jet's trigger (players via GunFire, AI pilots directly).
function CombatService:SetTrigger(jet: Jet, down: boolean, seed: number)
	local state = states[jet.id]
	if not (state and state.gun) then
		return
	end
	if not down then
		stopFiring(state)
		return
	end
	if state.firing or state.ammo <= 0 or state.jammed then
		return
	end
	state.firing = { seed = seed, index = 0, timer = 0 }
	Net.Server.fireList("GunFireFx", otherPlayers(jet.pilot), jet.id, true, seed, workspace:GetServerTimeNow())
end

local function onGunFire(player: Player, isStart: boolean, serverTime: number, seed: number)
	local jet = AircraftService:GetJet(player)
	if not jet or math.abs(workspace:GetServerTimeNow() - serverTime) > FIRE_TIME_TOLERANCE then
		return
	end
	CombatService:SetTrigger(jet, isStart, seed)
end

-- Fires due rounds for one jet this tick.
local function fireRounds(state: CombatState, dt: number)
	local gun = state.gun
	local firing = state.firing
	if not (gun and firing) then
		return
	end
	local interval = Ballistics.interval(gun)
	firing.timer += dt
	local muzzle = state.muzzle
	local muzzleCF = if muzzle then muzzle.WorldCFrame else state.jet.root.CFrame
	local shooterVelocity = Units.velocityFromStuds(state.jet.root.AssemblyLinearVelocity)
	while firing.timer >= interval do
		firing.timer -= interval
		if state.ammo <= 0 or state.jammed then
			stopFiring(state)
			return
		end
		table.insert(state.rounds, Ballistics.fire(muzzleCF, shooterVelocity, gun, firing.seed, firing.index))
		firing.index += 1
		state.ammo -= 1
		state.heat = math.min(1, state.heat + gun.HeatPerShot)
		if state.heat >= 1 then
			state.jammed = true
		end
	end
end

-- Moves one shooter's rounds and resolves hits.
local function flyRounds(state: CombatState, dt: number)
	local gun = state.gun
	if not gun or #state.rounds == 0 then
		return
	end
	local shooter = state.jet
	local rewind = HistoryService:RewindFor(shooter.pilot)

	-- Rewound poses of every possible target, computed once per tick.
	local targets = {}
	for id, other in states do
		if id ~= shooter.id then
			local pose = HistoryService:PoseAt(id, rewind)
			if pose then
				table.insert(targets, { state = other, pose = pose })
			end
		end
	end

	local survivors = {}
	for _, round in state.rounds do
		local nextRound = Ballistics.step(round, dt, gun.Drag)
		local from, to = round.position, nextRound.position
		local midpoint = (from + to) * 0.5
		local reach = (to - from).Magnitude * 0.5 + BROADPHASE_MARGIN
		local bestT, bestTarget, bestBox = math.huge, nil, nil

		for _, target in targets do
			if (target.pose.Position - midpoint).Magnitude <= reach then
				for _, box in target.state.hitboxes do
					local t = Ballistics.segmentBox(from, to, target.pose * box.offset, box.size)
					if t and t < bestT then
						bestT, bestTarget, bestBox = t, target, box
					end
				end
			end
		end

		if bestTarget and bestBox then
			local hitPosition = from:Lerp(to, bestT)
			local victim = bestTarget.state.jet
			if shooter.pilot then
				Net.Server.fire("HitConfirm", shooter.pilot, victim.id, bestBox.name)
			end
			Net.Server.fireAll("HitFx", victim.id, hitPosition)
			CombatService:ApplyDamage(victim, bestBox.name, gun.Damage, shooter.identity, gun.DisplayName)
		elseif nextRound.age < gun.Lifetime and not workspace:Raycast(from, to - from, worldParams) then
			table.insert(survivors, nextRound)
		end
	end
	state.rounds = survivors
end

local function tick(dt: number)
	for _, state in states do
		local gun = state.gun
		if gun then
			fireRounds(state, dt)
			-- Cooling, and clearing a jam once cool enough
			state.heat = math.max(0, state.heat - gun.CoolRate * dt)
			if state.jammed and state.heat <= JAM_CLEAR_HEAT then
				state.jammed = false
			end
		end
	end
	-- Fires burn the airframe, credited to whoever started them
	local now = os.clock()
	for jetId, fire in fires do
		local state = states[jetId]
		if not state then
			fires[jetId] = nil
		elseif now >= fire.untilTime then
			fires[jetId] = nil
			state.jet.model:SetAttribute("OnFire", false)
		else
			CombatService:ApplyDamage(state.jet, "Fuselage", FIRE_DPS * dt, fire.attacker, "Fire")
		end
	end
	-- Rounds are flown after every gun has fired, so all shooters see the same target poses.
	for _, state in states do
		flyRounds(state, dt)
	end
	for _, state in states do
		local model = state.jet.model
		if model:GetAttribute("Ammo") ~= state.ammo then
			model:SetAttribute("Ammo", state.ammo)
		end
		local heat = math.round(state.heat * 100) / 100
		if model:GetAttribute("GunHeat") ~= heat then
			model:SetAttribute("GunHeat", heat)
		end
		if model:GetAttribute("GunJammed") ~= state.jammed then
			model:SetAttribute("GunJammed", state.jammed)
		end
	end
end

local function onJetSpawned(jet: Jet)
	local airframe = AircraftData.get(jet.airframeId)
	local gun = airframe and WeaponData.get(airframe.Gun)
	local maxHealth = DamageModel.maxHealth(airframe)
	local state: CombatState = {
		jet = jet,
		gun = gun,
		health = table.clone(maxHealth),
		maxHealth = maxHealth,
		ammo = if gun then gun.Ammo else 0,
		heat = 0,
		jammed = false,
		firing = nil,
		rounds = {},
		attackers = {},
		attackerWeapon = {},
		hitboxes = readHitboxes(jet),
		muzzle = jet.root:FindFirstChild("GunMuzzle") :: Attachment?,
	}
	states[jet.id] = state
	sendDamageState(state)
end

local function onJetDestroyed(jet: Jet, cause: string, position: Vector3)
	local state = states[jet.id]
	states[jet.id] = nil
	if state and state.firing then
		stopFiring(state)
	end

	local credit = if state
		then DamageModel.resolveCredit(state.attackers, os.clock(), cause)
		else { killer = nil, assists = {}, forcedCrash = false }
	local killer: any? = credit.killer
	local killerUserId = if killer and typeof(killer) == "Instance" then (killer :: Player).UserId else 0
	Net.Server.fireAll("JetDestroyed", jet.id, killerUserId, cause, position)

	-- Quiet removals (respawning or leaving with nobody's damage on you) don't go in the kill feed.
	local quiet = killer == nil and (cause == "Respawn" or cause == "PilotLeft" or cause == "Despawn")
	if not quiet then
		local weapon = if killer and state and cause == "Shot" then state.attackerWeapon[killer] or "Gun" else cause
		local assistNames = {}
		for _, assist in credit.assists do
			table.insert(assistNames, assist.Name)
		end
		Net.Server.fireAll("KillFeed", if killer then killer.Name else "", jet.name, weapon, assistNames)
	end
	CombatService.Kill:Fire(jet, credit, cause)
end

function CombatService:Init()
	worldParams = RaycastParams.new()
	worldParams.FilterType = Enum.RaycastFilterType.Exclude
	worldParams.FilterDescendantsInstances = { workspace:WaitForChild("Jets") }

	AircraftService.JetSpawned:Connect(onJetSpawned)
	AircraftService.JetDestroyed:Connect(onJetDestroyed)
	Net.Server.on("GunFire", onGunFire)
end

function CombatService:Start()
	RunService.Heartbeat:Connect(function(dt)
		debug.profilebegin("CombatService.tick")
		tick(dt)
		debug.profileend()
	end)
end

return CombatService
