--!strict
-- Missiles, loadouts and countermeasures, server-authoritative (DEVELOPMENT.md §13 and §15).
--   Loadout: each jet carries its airframe's missiles, flares and chaff; the pilot picks a missile type.
--   IR lock: the server tracks what each IR missile's seeker would see from the shooter and how long
--     it's been held (LockTime). Radar missiles need the shooter's radar lock (SensorService).
--   Flight: every missile is simulated here with Guidance. IR seekers can be decoyed by flares (one
--     roll per flare); radar missiles go dumb if the lock is lost, or can be decoyed by chaff.
--   Detonation: proximity fuse or ground impact. Damage falls off with distance.
--   Clients get spawn/detonate events reliably and positions ~15 Hz, packed, unreliable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Countermeasures = require(Shared.Countermeasures)
local Environment = require(Shared.Config.Environment)
local Guidance = require(Shared.Guidance)
local Net = require(Shared.Net)
local Pack = require(Shared.Net.Pack)
local Signature = require(Shared.Signature)
local Units = require(Shared.Units)
local WeaponData = require(Shared.WeaponData)

local AircraftService = require(script.Parent.AircraftService)
local CombatService = require(script.Parent.CombatService)
local SensorService = require(script.Parent.SensorService)

type Jet = AircraftService.Jet

local LAUNCH_COOLDOWN = 0.6
local STATE_INTERVAL = 1 / 15
local BLAST_MULTIPLIER = 3 -- blast radius = proximity fuse × this
local EJECT_SPEED = 6 -- m/s downward off the rail
local FLARE_RANGE = 4000 -- real metres: flares further than this from a missile are ignored

type Slot = { weapon: WeaponData.Missile, id: string, count: number }

type Loadout = {
	jet: Jet,
	slots: { Slot },
	selected: number,
	flares: number,
	chaff: number,
	irTarget: number?,
	irSince: number,
	lastLaunch: number,
	nextHardpoint: number,
	hardpoints: { Attachment },
}

type Missile = {
	id: number,
	weaponId: string,
	spec: WeaponData.Missile,
	owner: Jet?,
	ownerPlayer: Player?,
	targetId: number?,
	state: Guidance.MissileState,
	seeker: Guidance.IRSeeker?,
	guiding: boolean,
	-- Radar missiles: where the illuminating radar is. Real shooter, or a virtual one (debug launches).
	virtualRadar: { position: Vector3, velocity: Vector3 }?,
	lostTrack: boolean,
}

local MissileService = {
	Priority = 34,
}

local loadouts: { [number]: Loadout } = {}
local missiles: { [number]: Missile } = {}
local flares: { Countermeasures.Flare } = {}
local nextMissileId = 0
local nextFlareId = 0
local worldParams: RaycastParams

local function setAttributes(loadout: Loadout)
	local model = loadout.jet.model
	local slot = loadout.slots[loadout.selected]
	model:SetAttribute("SelectedMissile", if slot then slot.id else "")
	for _, s in loadout.slots do
		model:SetAttribute(`Msl_{s.id}`, s.count)
	end
	model:SetAttribute("Flares", loadout.flares)
	model:SetAttribute("Chaff", loadout.chaff)
end

local function onJetSpawned(jet: Jet)
	local airframe = AircraftData.get(jet.airframeId) :: any
	if not airframe then
		return
	end
	local slots = {}
	for _, entry in airframe.Missiles or {} do
		local weapon = WeaponData.getMissile(entry.Weapon)
		if weapon then
			table.insert(slots, { weapon = weapon, id = entry.Weapon, count = entry.Count })
		end
	end
	local hardpoints = {}
	for i = 1, 12 do
		local a = jet.root:FindFirstChild(`Hardpoint{i}`)
		if a and a:IsA("Attachment") then
			table.insert(hardpoints, a)
		end
	end
	local cm = airframe.Countermeasures or { Flares = 0, Chaff = 0 }
	local loadout: Loadout = {
		jet = jet,
		slots = slots,
		selected = 1,
		flares = cm.Flares,
		chaff = cm.Chaff,
		irTarget = nil,
		irSince = 0,
		lastLaunch = 0,
		nextHardpoint = 1,
		hardpoints = hardpoints,
	}
	loadouts[jet.id] = loadout
	setAttributes(loadout)
end

local function throttleOf(jet: Jet): (number, boolean)
	return (jet.model:GetAttribute("Throttle") :: number?) or 0.85, jet.model:GetAttribute("Afterburner") == true
end

-- Best IR target for a shooter's selected IR missile (closest to the nose), or nil.
local function bestIRTarget(shooter: Jet, spec: WeaponData.Missile): number?
	local bestId, bestDot = nil, -2
	for id, other in AircraftService:GetJets() do
		if id ~= shooter.id then
			local throttle, afterburner = throttleOf(other)
			if Guidance.irLockable(spec, shooter.root.CFrame, other.root.CFrame, throttle, afterburner) then
				local dot = shooter.root.CFrame.LookVector:Dot((other.root.Position - shooter.root.Position).Unit)
				if dot > bestDot then
					bestId, bestDot = id, dot
				end
			end
		end
	end
	return bestId
end

local function updateIRTracking()
	local now = os.clock()
	for _, loadout in loadouts do
		local slot = loadout.slots[loadout.selected]
		local target = if slot and WeaponData.isIR(slot.weapon) then bestIRTarget(loadout.jet, slot.weapon) else nil
		if target ~= loadout.irTarget then
			loadout.irTarget = target
			loadout.irSince = now
		end
	end
end

local function spawnMissile(
	spec: WeaponData.Missile,
	weaponId: string,
	position: Vector3,
	velocity: Vector3,
	owner: Jet?,
	targetId: number?
): Missile
	nextMissileId += 1
	local id = nextMissileId
	local missile: Missile = {
		id = id,
		weaponId = weaponId,
		spec = spec,
		owner = owner,
		ownerPlayer = owner and owner.pilot,
		targetId = targetId,
		state = Guidance.launch(position, velocity),
		seeker = if WeaponData.isIR(spec) then Guidance.newIRSeeker(targetId, id * 7 + 13) else nil,
		guiding = false,
		virtualRadar = nil,
		lostTrack = targetId == nil,
	}
	missiles[id] = missile
	Net.Server.fireAll("MissileSpawned", id, weaponId, if owner then owner.id else 0, position, velocity)
	return missile
end

local function onMissileFire(player: Player, targetId: number)
	local jet = AircraftService:GetJet(player)
	local loadout = jet and loadouts[jet.id]
	if not (jet and loadout) then
		return
	end
	local slot = loadout.slots[loadout.selected]
	local now = os.clock()
	if not slot or slot.count <= 0 or now - loadout.lastLaunch < LAUNCH_COOLDOWN then
		return
	end
	local spec = slot.weapon
	local target: number? = nil
	if WeaponData.isIR(spec) then
		-- Only a target the server agrees the seeker has held for the lock time.
		if targetId ~= 0 and loadout.irTarget == targetId and now - loadout.irSince >= spec.LockTime * 0.8 then
			target = targetId
		end
	else
		-- Radar missiles need the radar locked on that target; no lock, no launch.
		if targetId == 0 or SensorService:GetLock(jet.id) ~= targetId then
			return
		end
		target = targetId
	end

	slot.count -= 1
	loadout.lastLaunch = now
	local hardpoint = loadout.hardpoints[loadout.nextHardpoint]
	loadout.nextHardpoint = loadout.nextHardpoint % math.max(#loadout.hardpoints, 1) + 1
	local position = if hardpoint then hardpoint.WorldPosition else jet.root.Position
	local velocity = Units.velocityFromStuds(jet.root.AssemblyLinearVelocity) - jet.root.CFrame.UpVector * EJECT_SPEED
	spawnMissile(spec, slot.id, position, velocity, jet, target)
	setAttributes(loadout)
end

local function onCountermeasure(player: Player, kind: string)
	local jet = AircraftService:GetJet(player)
	local loadout = jet and loadouts[jet.id]
	if not (jet and loadout) or (kind ~= "Flare" and kind ~= "Chaff") then
		return
	end
	local dispenser =
		jet.root:FindFirstChild(if kind == "Flare" then "FlareDispenser" else "ChaffDispenser") :: Attachment?
	local dispenserCF = if dispenser then dispenser.WorldCFrame else jet.root.CFrame
	local velocity = Units.velocityFromStuds(jet.root.AssemblyLinearVelocity)
	if kind == "Flare" then
		if loadout.flares <= 0 then
			return
		end
		loadout.flares -= 1
		nextFlareId += 1
		local flare = Countermeasures.newFlare(nextFlareId, dispenserCF, velocity)
		table.insert(flares, flare)
		Net.Server.fireAll("CountermeasureFx", jet.id, "Flare", flare.position, flare.velocity)
	else
		if loadout.chaff <= 0 then
			return
		end
		loadout.chaff -= 1
		nextFlareId += 1
		local seed = nextFlareId
		Net.Server.fireAll("CountermeasureFx", jet.id, "Chaff", dispenserCF.Position, velocity * 0.5)
		-- Each radar missile guiding on this jet gets one roll against this bundle.
		for _, missile in missiles do
			if missile.targetId == jet.id and WeaponData.isRadar(missile.spec) and not missile.lostTrack then
				local radarPosition = if missile.owner
					then missile.owner.root.Position
					elseif missile.virtualRadar then missile.virtualRadar.position
					else missile.state.position
				local notching = SensorService:IsNotching(radarPosition, jet)
				if
					Countermeasures.roll(seed, missile.id)
					< Countermeasures.chaffDecoyChance(missile.spec.ChaffResistance, notching)
				then
					missile.lostTrack = true
				end
			end
		end
		SensorService:OnChaff(jet, seed)
	end
	setAttributes(loadout)
end

local function detonate(missile: Missile, position: Vector3, hitJet: Jet?)
	missiles[missile.id] = nil
	Net.Server.fireAll("MissileDetonated", missile.id, position, if hitJet then hitJet.id else 0)
	local blast = missile.spec.ProximityFuse * BLAST_MULTIPLIER
	for _, jet in AircraftService:GetJets() do
		if missile.owner and jet == missile.owner and missile.state.travelled < 200 then
			continue -- no self-damage right off the rail
		end
		local distance = Units.toMetres((jet.root.Position - position).Magnitude)
		if distance <= blast then
			local falloff = math.clamp(1 - distance / blast, 0.3, 1)
			local damage = missile.spec.Damage * falloff
			-- The nearest part takes the blast, and the airframe half as much again: a good hit from a full
			-- warhead kills a fighter; a small warhead (R-60) usually cripples it.
			local nearest, nearestDistance = "Fuselage", math.huge
			local hitboxes = jet.model:FindFirstChild("Hitboxes")
			if hitboxes then
				for _, box in hitboxes:GetChildren() do
					if box:IsA("BasePart") then
						local d = (box.Position - position).Magnitude
						if d < nearestDistance then
							nearest, nearestDistance = box.Name, d
						end
					end
				end
			end
			CombatService:ApplyDamage(jet, nearest, damage, missile.ownerPlayer, missile.spec.DisplayName)
			CombatService:ApplyDamage(jet, "Fuselage", damage * 0.5, missile.ownerPlayer, missile.spec.DisplayName)
		end
	end
end

-- What the missile is steering at this tick (position, velocity) or nil.
local function trackFor(missile: Missile): (Vector3?, Vector3?)
	local target = if missile.targetId then AircraftService:GetJetById(missile.targetId) else nil
	if missile.seeker then
		local sources: { Guidance.HeatSource } = {}
		if target then
			local throttle, afterburner = throttleOf(target)
			table.insert(sources, {
				id = target.id,
				position = target.root.Position,
				velocity = Units.velocityFromStuds(target.root.AssemblyLinearVelocity),
				heat = Signature.ir(
					target.root.CFrame,
					throttle,
					afterburner,
					missile.state.position,
					missile.spec.Class == "IR_Rear"
				),
			})
		end
		for _, flare in flares do
			if Units.toMetres((flare.position - missile.state.position).Magnitude) <= FLARE_RANGE then
				table.insert(sources, {
					id = `flare:{flare.id}`,
					position = flare.position,
					velocity = flare.velocity,
					heat = Countermeasures.flareHeat(flare),
				})
			end
		end
		local tracked = Guidance.updateIRSeeker(missile.seeker, missile.state, missile.spec, sources)
		if tracked then
			return tracked.position, tracked.velocity
		end
		return nil, nil
	end

	-- Radar missiles: need a live target, no chaff decoy, and continuous illumination.
	if not target or missile.lostTrack then
		return nil, nil
	end
	local illuminated
	if missile.owner then
		illuminated = AircraftService:GetJetById(missile.owner.id) ~= nil
			and SensorService:GetLock(missile.owner.id) == target.id
	else
		illuminated = missile.virtualRadar ~= nil
	end
	if not illuminated then
		missile.lostTrack = true -- SARH: lock lost = missile goes dumb for good
		return nil, nil
	end
	return target.root.Position, Units.velocityFromStuds(target.root.AssemblyLinearVelocity)
end

local function stepMissiles(dt: number)
	for i = #flares, 1, -1 do
		local flare = Countermeasures.stepFlare(flares[i], dt)
		if flare.age >= Countermeasures.FLARE_BURN then
			table.remove(flares, i)
		else
			flares[i] = flare
		end
	end

	for _, missile in missiles do
		if missile.virtualRadar then
			missile.virtualRadar.position += Units.velocityToStuds(missile.virtualRadar.velocity) * dt
		end
		local trackPosition, trackVelocity = trackFor(missile)
		local from = missile.state.position
		local nextState, guiding = Guidance.step(missile.state, missile.spec, dt, trackPosition, trackVelocity)
		missile.guiding = guiding
		local to = nextState.position

		-- Proximity fuse against every jet (armed after MinRange)
		if nextState.travelled >= missile.spec.MinRange then
			for _, jet in AircraftService:GetJets() do
				if missile.owner and jet == missile.owner then
					continue
				end
				local velocity = jet.root.AssemblyLinearVelocity
				local miss = Guidance.closestApproach(from, to, jet.root.Position - velocity * dt, jet.root.Position)
				if miss <= missile.spec.ProximityFuse then
					missile.state = nextState
					detonate(missile, to, jet)
					break
				end
			end
		end
		if missiles[missile.id] == nil then
			continue
		end
		local hit = workspace:Raycast(from, to - from, worldParams)
		if hit then
			detonate(missile, hit.Position, nil)
			continue
		end
		missile.state = nextState
		local spent = nextState.age > missile.spec.MotorBurnTime
			and nextState.velocity.Magnitude < missile.spec.MinSpeed * 0.6
		if nextState.age >= missile.spec.Lifetime or spent then
			detonate(missile, to, nil)
		end
	end
end

local function sendState()
	local list = {}
	for _, missile in missiles do
		table.insert(list, {
			id = missile.id,
			position = missile.state.position,
			velocity = missile.state.velocity,
			burning = missile.state.age < missile.spec.MotorBurnTime,
		})
	end
	for start = 1, #list, Pack.MAX_PER_PACKET do
		local chunk = table.move(list, start, math.min(start + Pack.MAX_PER_PACKET - 1, #list), 1, {})
		Net.Server.fireAll("MissileState", Pack.missiles(chunk))
	end
end

-- RWR launch warnings: radar missiles always (the RWR hears the guidance signal); IR missiles only if
-- the target jet has a missile-approach warner.
local function launchThreats(): { [number]: { SensorService.Threat } }
	local out: { [number]: { SensorService.Threat } } = {}
	for _, missile in missiles do
		local target = if missile.targetId then AircraftService:GetJetById(missile.targetId) else nil
		if target and not missile.lostTrack then
			local airframe = AircraftData.get(target.airframeId) :: any
			local warns = WeaponData.isRadar(missile.spec) or (airframe and airframe.RWR and airframe.RWR.LaunchWarning)
			if warns then
				out[target.id] = out[target.id] or {}
				table.insert(out[target.id], { id = -missile.id, kind = "Launch", position = missile.state.position })
			end
		end
	end
	return out
end

local function onDebugLaunch(player: Player, weaponId: string)
	local jet = AircraftService:GetJet(player)
	local spec = WeaponData.getMissile(weaponId)
	if not (jet and spec) then
		return
	end
	local behind = -jet.root.CFrame.LookVector
	local flatBehind = Vector3.new(behind.X, 0, behind.Z)
	flatBehind = if flatBehind.Magnitude > 1e-3 then flatBehind.Unit else Vector3.new(0, 0, 1)
	local position = jet.root.Position + flatBehind * Units.toStuds(1800) + Vector3.new(0, Units.toStuds(100), 0)
	local jetVelocity = Units.velocityFromStuds(jet.root.AssemblyLinearVelocity)
	local velocity = (jet.root.Position - position).Unit * math.max(jetVelocity.Magnitude, 220)
	local missile = spawnMissile(spec, weaponId, position, velocity, nil, jet.id)
	if WeaponData.isRadar(spec) then
		missile.virtualRadar = { position = position, velocity = jetVelocity }
	end
end

function MissileService:Init()
	worldParams = RaycastParams.new()
	worldParams.FilterType = Enum.RaycastFilterType.Exclude
	worldParams.FilterDescendantsInstances = { workspace:WaitForChild("Jets") }

	AircraftService.JetSpawned:Connect(onJetSpawned)
	AircraftService.JetDestroyed:Connect(function(jet)
		loadouts[jet.id] = nil
	end)
	SensorService:SetLaunchThreatProvider(launchThreats)

	Net.Server.on("SelectWeapon", function(player: Player, index: number)
		local jet = AircraftService:GetJet(player)
		local loadout = jet and loadouts[jet.id]
		if loadout and loadout.slots[index] then
			loadout.selected = index
			setAttributes(loadout)
		end
	end)
	Net.Server.on("MissileFire", onMissileFire)
	Net.Server.on("CountermeasureDeploy", onCountermeasure)
	if Environment.isTest() then
		Net.Server.on("DebugLaunchAtMe", onDebugLaunch)
	end
end

function MissileService:Start()
	local stateTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		debug.profilebegin("MissileService.tick")
		updateIRTracking()
		stepMissiles(dt)
		stateTimer += dt
		if stateTimer >= STATE_INTERVAL then
			stateTimer = 0
			sendState()
		end
		debug.profileend()
	end)
end

return MissileService
