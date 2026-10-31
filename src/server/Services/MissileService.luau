--!strict
-- Missiles, loadouts and countermeasures, server-authoritative (DEVELOPMENT.md §13 and §15).
--   Loadout: each jet carries its airframe's missiles, flares and chaff; the pilot picks a missile type.
--   In Guns Only (MatchRules) the racks are empty: every count is 0 and nothing can be selected.
--   IR lock: the server tracks what each IR missile's seeker would see from the shooter and how long
--     it's been held (LockTime). Radar missiles need the shooter's radar lock (SensorService).
--     Helmet cueing (MSL-09): with an advanced heat-seeker selected, the jet the pilot is looking at (sent
--     by the client) is the target if the missile could lock it anywhere in its gimbal.
--   Flight: every missile is simulated here with Guidance. IR seekers can be decoyed by flares (one
--     roll per flare; imaging seekers one roll per burst); radar missiles go dumb if the lock is lost, or
--     can be decoyed by chaff.
--   Detonation: proximity fuse or ground impact. Damage falls off with distance.
--   Clients get spawn/detonate events reliably and positions ~15 Hz, packed, unreliable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Progression = require(Shared.Progression)
local Countermeasures = require(Shared.Countermeasures)
local Environment = require(Shared.Config.Environment)
local Guidance = require(Shared.Guidance)
local MatchRules = require(Shared.MatchRules)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Pack = require(Shared.Net.Pack)
local Signature = require(Shared.Signature)
local Units = require(Shared.Units)
local WeaponData = require(Shared.WeaponData)

local AircraftService = require(script.Parent.AircraftService)
local CombatService = require(script.Parent.CombatService)
local DataService = require(script.Parent.DataService)
local SensorService = require(script.Parent.SensorService)
local Teams = require(ServerScriptService.Server.Lib.Teams)

type Jet = AircraftService.Jet

local LAUNCH_COOLDOWN = 0.6
local TWS_RECHECK = 0.2 -- seconds between checks that a TWS shot's launcher still sees its target
local STATE_INTERVAL = 1 / 15
local BLAST_MULTIPLIER = 3 -- blast radius = proximity fuse × this
local EJECT_SPEED = 6 -- m/s downward off the rail
local FLARE_RANGE = 4000 -- real metres: flares further than this from a missile are ignored

type Slot = { weapon: WeaponData.Missile, id: string, count: number }

type Loadout = {
	jet: Jet,
	slots: { Slot },
	selected: number, -- 0 = none (Guns Only)
	armed: boolean, -- false in Guns Only: nothing can be selected
	flares: number,
	chaff: number,
	irTarget: number?,
	irSince: number,
	cueId: number, -- the jet the pilot is looking at (helmet cueing), 0 = none
	lastLaunch: number,
	nextHardpoint: number,
	hardpoints: { Attachment },
}

type Missile = {
	id: number,
	weaponId: string,
	spec: WeaponData.Missile,
	owner: Jet?,
	ownerIdentity: any?, -- who gets credit (Player or AI record)
	targetId: number?,
	launchTargetId: number?, -- who it was fired at (for "missile defeated" rewards)
	launchTargetIdentity: any?, -- and who was flying it (for the balance numbers)
	state: Guidance.MissileState,
	seeker: Guidance.IRSeeker?,
	guiding: boolean,
	-- Radar missiles: where the illuminating radar is. Real shooter, or a virtual one (debug launches).
	virtualRadar: { position: Vector3, velocity: Vector3 }?,
	lostTrack: boolean,
	arh: Guidance.ARHState?, -- active radar missiles (MSL-07)
	autoFlared: boolean?, -- its target's automatic flare programme has fired for it (CMS-04)
	loftRange: number?, -- set when it lofts (MSL-08): the horizontal range at launch, real metres
	tws: boolean?, -- fired on a track-while-scan track, not a hard lock (SNS-07)
	twsSeen: boolean?, -- the launcher's radar still sees the target (re-checked 5× a second)
	twsChecked: number?,
}

local MissileService = {
	Priority = 34,
	-- A missile ended without damaging the jet it was fired at: (targetJet, ownerIdentity, weaponId)
	MissileDefeated = Signal.new(),
	-- For the balance numbers (ANL-04): a missile left the rail (jet, weaponId, targetIdentity), and how it
	-- ended (ownerIdentity, weaponId, hit: whether it damaged the jet it was fired at, targetIdentity).
	-- targetIdentity: who was flying the jet it was fired at, nil if fired without a target.
	MissileLaunched = Signal.new(),
	MissileEnded = Signal.new(),
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
	local airframe = Progression.airframeForModel(jet.model) :: any
	if not airframe then
		return
	end
	local armed = MatchRules.missiles(MatchRules.get(ReplicatedStorage:GetAttribute("GameMode")))
	local slots = {}
	for _, entry in airframe.Missiles or {} do
		local weapon = WeaponData.getMissile(entry.Weapon)
		if weapon then
			table.insert(slots, { weapon = weapon, id = entry.Weapon, count = if armed then entry.Count else 0 })
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
		selected = if armed then 1 else 0,
		armed = armed,
		flares = cm.Flares,
		chaff = cm.Chaff,
		irTarget = nil,
		irSince = 0,
		cueId = 0,
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

-- Best IR target for a shooter's selected IR missile: the jet the pilot is looking at if the missile is
-- helmet-cued and could lock it, else the one closest to the nose; or nil.
local function bestIRTarget(shooter: Jet, spec: WeaponData.Missile, cueId: number): number?
	local cued = cueId ~= 0 and AircraftService:GetJetById(cueId)
	if cued and cued.id ~= shooter.id and not Teams.areFriends(shooter.identity, cued.identity) then
		local throttle, afterburner = throttleOf(cued)
		if Guidance.irCueLockable(spec, shooter.root.CFrame, cued.root.CFrame, throttle, afterburner) then
			return cued.id
		end
	end
	local bestId, bestDot = nil, -2
	for id, other in AircraftService:GetJets() do
		if id ~= shooter.id and not Teams.areFriends(shooter.identity, other.identity) then
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
		local target = if slot and WeaponData.isIR(slot.weapon)
			then bestIRTarget(loadout.jet, slot.weapon, loadout.cueId)
			else nil
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
	local launchTarget = if targetId then AircraftService:GetJetById(targetId) :: any else nil
	local missile: Missile = {
		id = id,
		weaponId = weaponId,
		spec = spec,
		owner = owner,
		ownerIdentity = owner and owner.identity,
		targetId = targetId,
		launchTargetId = targetId,
		launchTargetIdentity = launchTarget and launchTarget.identity,
		state = Guidance.launch(position, velocity),
		seeker = if WeaponData.isIR(spec) then Guidance.newIRSeeker(targetId, id * 7 + 13) else nil,
		guiding = false,
		virtualRadar = nil,
		lostTrack = targetId == nil,
		arh = nil,
	}
	-- Long shots with a lofting missile climb first (MSL-08)
	local lofted = if targetId and spec.Loft then AircraftService:GetJetById(targetId) else nil
	if lofted then
		local flat = lofted.root.Position - position
		local range = Units.toMetres(Vector3.new(flat.X, 0, flat.Z).Magnitude)
		if Guidance.lofts(spec, range) then
			missile.loftRange = range
		end
	end
	if spec.Class == "ARH" then
		local target = if targetId then AircraftService:GetJetById(targetId) else nil
		missile.arh = Guidance.newARH(
			target and target.root.Position,
			target and Units.velocityFromStuds(target.root.AssemblyLinearVelocity),
			os.clock()
		)
	end
	missiles[id] = missile
	Net.Server.fireAll("MissileSpawned", id, weaponId, if owner then owner.id else 0, position, velocity)
	return missile
end

-- Fires the selected missile from a jet at a target (players through MissileFire, AI pilots
-- directly). The same checks for everyone: ammo, cooldown, the seeker's hold time (IR) or the server's
-- radar lock. Returns whether a missile left the rail.
local function launch(jet: Jet, targetId: number): boolean
	local loadout = loadouts[jet.id]
	if not loadout then
		return false
	end
	local slot = loadout.slots[loadout.selected]
	local now = os.clock()
	if not slot or slot.count <= 0 or now - loadout.lastLaunch < LAUNCH_COOLDOWN then
		return false
	end
	local spec = slot.weapon
	local target: number? = nil
	local tws = false
	if WeaponData.isIR(spec) then
		-- Only a target the server agrees the seeker has held for the lock time.
		if targetId ~= 0 and loadout.irTarget == targetId and now - loadout.irSince >= spec.LockTime * 0.8 then
			target = targetId
		end
	else
		-- Radar missiles need the radar locked on that target; no lock, no launch. Active radar missiles can
		-- also go on a track-while-scan track (SNS-07): the radar sees it, no hard lock needed.
		if targetId == 0 then
			return false
		end
		local targetJet = AircraftService:GetJetById(targetId)
		if targetJet and Teams.areFriends(jet.identity, targetJet.identity) then
			return false
		end
		if SensorService:GetLock(jet.id) ~= targetId then
			if not (spec.Class == "ARH" and targetJet and SensorService:CanTWS(jet, targetJet)) then
				return false
			end
			tws = true
		end
		target = targetId
	end

	slot.count -= 1
	loadout.lastLaunch = now
	local hardpoint = loadout.hardpoints[loadout.nextHardpoint]
	loadout.nextHardpoint = loadout.nextHardpoint % math.max(#loadout.hardpoints, 1) + 1
	local position = if hardpoint then hardpoint.WorldPosition else jet.root.Position
	local velocity = Units.velocityFromStuds(jet.root.AssemblyLinearVelocity) - jet.root.CFrame.UpVector * EJECT_SPEED
	local missile = spawnMissile(spec, slot.id, position, velocity, jet, target)
	if tws then
		missile.tws = true
		missile.twsSeen = true
		missile.twsChecked = now
	end
	MissileService.MissileLaunched:Fire(jet, slot.id, missile.launchTargetIdentity)
	setAttributes(loadout)
	return true
end

local function onMissileFire(player: Player, targetId: number)
	local jet = AircraftService:GetJet(player)
	if jet then
		launch(jet, targetId)
	end
end

-- AI pilots (AI-04): the missiles a jet carries, choosing one, and firing it.
function MissileService:Slots(jet: Jet): { { index: number, spec: WeaponData.Missile, count: number } }
	local loadout = loadouts[jet.id]
	local list = {}
	for i, slot in (loadout and loadout.slots) or {} do
		table.insert(list, { index = i, spec = slot.weapon, count = slot.count })
	end
	return list
end

function MissileService:SelectSlot(jet: Jet, index: number)
	local loadout = loadouts[jet.id]
	if loadout and loadout.armed and loadout.slots[index] and loadout.selected ~= index then
		loadout.selected = index
		setAttributes(loadout)
	end
end

-- Whether the selected heat-seeker has held this target long enough to fire.
function MissileService:SeekerReady(jet: Jet, targetId: number): boolean
	local loadout = loadouts[jet.id]
	local slot = loadout and loadout.slots[loadout.selected]
	return slot ~= nil and loadout.irTarget == targetId and os.clock() - loadout.irSince >= slot.weapon.LockTime * 0.8
end

function MissileService:FireFor(jet: Jet, targetId: number): boolean
	return launch(jet, targetId)
end

-- Drops a flare or chaff bundle from a jet (players via CountermeasureDeploy, AI pilots directly).
function MissileService:DeployCountermeasure(jet: Jet, kind: string)
	local loadout = loadouts[jet.id]
	if not loadout or (kind ~= "Flare" and kind ~= "Chaff") then
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
			local seeking = missile.arh == nil or missile.arh.active -- an ARH in midcourse ignores chaff
			if
				missile.targetId == jet.id
				and WeaponData.isRadar(missile.spec)
				and not missile.lostTrack
				and seeking
			then
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

-- Flare programmes (CMS-04): jets running one, so presses during it don't stack another
local programmes: { [number]: boolean } = {}

local function hasProgramme(jet: Jet): boolean
	local airframe = AircraftData.get(jet.airframeId) :: any
	return airframe ~= nil and Countermeasures.hasProgramme(airframe.Tier)
end

-- Fires a jet's flare programme: salvos of flares a short interval apart (Countermeasures.PROGRAMME).
local function runProgramme(jet: Jet)
	if programmes[jet.id] then
		return
	end
	programmes[jet.id] = true
	task.spawn(function()
		local programme = Countermeasures.PROGRAMME
		for salvo = 1, programme.salvos do
			if not AircraftService:GetJetById(jet.id) then
				break
			end
			for _ = 1, programme.perSalvo do
				MissileService:DeployCountermeasure(jet, "Flare")
			end
			if salvo < programme.salvos then
				task.wait(programme.interval)
			end
		end
		programmes[jet.id] = nil
	end)
end

-- Whether a jet's pilot has automatic flares on (players only; AI pilots dispense for themselves).
local function autoFlaresOn(jet: Jet): boolean
	local data = jet.pilot and DataService:GetData(jet.pilot)
	return data ~= nil and data.Settings ~= nil and data.Settings.AutoFlares ~= false
end

-- A heat-seeker guiding on a Tier V+ jet with auto flares on fires its programme once, about
-- Countermeasures.AUTO_TIME before it would arrive.
local function checkAutoFlares(missile: Missile)
	if missile.autoFlared or missile.lostTrack or not missile.guiding or not WeaponData.isIR(missile.spec) then
		return
	end
	local target = missile.targetId and AircraftService:GetJetById(missile.targetId)
	if not (target and target.pilot and hasProgramme(target)) then
		return
	end
	local offset = target.root.Position - missile.state.position
	local distance = Units.toMetres(offset.Magnitude)
	local closing = (missile.state.velocity - Units.velocityFromStuds(target.root.AssemblyLinearVelocity)):Dot(
		offset.Unit
	)
	if Countermeasures.autoDue(distance, closing) then
		missile.autoFlared = true
		if autoFlaresOn(target) then
			runProgramme(target)
		end
	end
end

local function onCountermeasure(player: Player, kind: string)
	local jet = AircraftService:GetJet(player)
	if not jet then
		return
	end
	if kind == "Flare" and hasProgramme(jet) then
		runProgramme(jet)
	else
		MissileService:DeployCountermeasure(jet, kind)
	end
end

-- The nearest missile guiding on a jet, for AI threat awareness: { position, velocity, kind }.
function MissileService:IncomingFor(jetId: number): { position: Vector3, velocity: Vector3, kind: string }?
	local jet = AircraftService:GetJetById(jetId)
	if not jet then
		return nil
	end
	local best, bestDistance = nil, math.huge
	for _, missile in missiles do
		local silent = missile.arh ~= nil and not missile.arh.active -- ARH midcourse
		if missile.targetId == jetId and not missile.lostTrack and missile.guiding and not silent then
			local distance = (missile.state.position - jet.root.Position).Magnitude
			if distance < bestDistance then
				best = {
					position = missile.state.position,
					velocity = missile.state.velocity,
					kind = if WeaponData.isIR(missile.spec) then "IR" else "Radar",
				}
				bestDistance = distance
			end
		end
	end
	return best
end

local function detonate(missile: Missile, position: Vector3, hitJet: Jet?)
	missiles[missile.id] = nil
	Net.Server.fireAll("MissileDetonated", missile.id, position, if hitJet then hitJet.id else 0)
	local blast = missile.spec.ProximityFuse * BLAST_MULTIPLIER
	local hitTarget = false
	for _, jet in AircraftService:GetJets() do
		if missile.owner and jet == missile.owner and missile.state.travelled < 200 then
			continue -- no self-damage right off the rail
		end
		local distance = Units.toMetres((jet.root.Position - position).Magnitude)
		if distance <= blast then
			if jet.id == missile.launchTargetId then
				hitTarget = true
			end
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
			CombatService:ApplyDamage(jet, nearest, damage, missile.ownerIdentity, missile.spec.DisplayName)
			CombatService:ApplyDamage(jet, "Fuselage", damage * 0.5, missile.ownerIdentity, missile.spec.DisplayName)
		end
	end
	local target = missile.launchTargetId and AircraftService:GetJetById(missile.launchTargetId)
	if target and not hitTarget then
		MissileService.MissileDefeated:Fire(target, missile.ownerIdentity, missile.weaponId)
	end
	MissileService.MissileEnded:Fire(missile.ownerIdentity, missile.weaponId, hitTarget, missile.launchTargetIdentity)
end

-- What the missile is steering at this tick (position, velocity) or nil.
local function trackFor(missile: Missile, dt: number): (Vector3?, Vector3?)
	local target = if missile.targetId then AircraftService:GetJetById(missile.targetId) else nil
	-- Active radar: data link in midcourse, its own seeker once active
	local arh = missile.arh
	if arh then
		if missile.lostTrack then
			return nil, nil
		end
		local owner = missile.owner and AircraftService:GetJetById(missile.owner.id)
		local linked = if missile.owner
			then owner ~= nil and SensorService:GetLock(missile.owner.id) == missile.targetId
			else missile.virtualRadar ~= nil
		-- A TWS shot (SNS-07) stays linked while the launcher's radar still sees the target
		if missile.tws and owner and target and not linked then
			if os.clock() - (missile.twsChecked or 0) >= TWS_RECHECK then
				missile.twsChecked = os.clock()
				missile.twsSeen = SensorService:CanTWS(owner, target)
			end
			linked = missile.twsSeen == true
		end
		local position, velocity = Guidance.arhTrack(
			arh,
			missile.state,
			missile.spec :: any,
			if target
				then {
					position = target.root.Position,
					velocity = Units.velocityFromStuds(target.root.AssemblyLinearVelocity),
				}
				else nil,
			linked,
			target ~= nil and arh.active and SensorService:IsNotching(missile.state.position, target),
			dt,
			os.clock()
		)
		if arh.lost then
			missile.lostTrack = true
		end
		return position, velocity
	end
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
		local trackPosition, trackVelocity = trackFor(missile, dt)
		local from = missile.state.position
		local aim = if missile.loftRange and trackPosition
			then Guidance.loftAim(missile.state, trackPosition, missile.loftRange)
			else nil
		local nextState, guiding = Guidance.step(missile.state, missile.spec, dt, trackPosition, trackVelocity, aim)
		missile.guiding = guiding
		local to = nextState.position

		-- Proximity fuse against every jet (armed after MinRange)
		if nextState.travelled >= missile.spec.MinRange then
			for _, jet in AircraftService:GetJets() do
				if missile.owner and jet == missile.owner then
					continue
				end
				if Teams.areFriends(missile.ownerIdentity, jet.identity) then
					continue -- the fuse ignores teammates
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
		checkAutoFlares(missile)
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

-- Warnings for the RWR: every missile guiding on a jet ("Launch"), and every heat-seeker that has
-- locked it ("Lock"). Real Tier I-II jets can't hear an IR missile at all, but the AI fly them with
-- heat-seekers, so players were shot at in silence (Will: "not getting the proper indication when an
-- enemy has locked onto me"). ARH missiles stay silent in midcourse, as they're meant to.
local function launchThreats(): { [number]: { SensorService.Threat } }
	local out: { [number]: { SensorService.Threat } } = {}
	local function add(targetId: number, threat: SensorService.Threat)
		out[targetId] = out[targetId] or {}
		table.insert(out[targetId], threat)
	end
	for _, missile in missiles do
		local target = if missile.targetId then AircraftService:GetJetById(missile.targetId) else nil
		local silent = missile.arh ~= nil and not missile.arh.active -- ARH midcourse
		if target and not missile.lostTrack and not silent then
			add(target.id, { id = -missile.id, kind = "Launch", position = missile.state.position })
		end
	end
	local now = os.clock()
	for _, loadout in loadouts do
		local slot = loadout.slots[loadout.selected]
		local target = loadout.irTarget and AircraftService:GetJetById(loadout.irTarget)
		if target and slot and now - loadout.irSince >= slot.weapon.LockTime * 0.8 then
			add(target.id, { id = loadout.jet.id, kind = "Lock", position = loadout.jet.root.Position })
		end
	end
	return out
end

-- A missile fired at you from behind: test servers, and Free Flight anywhere (the Defend lesson uses it).
local function onDebugLaunch(player: Player, weaponId: string)
	if not (Environment.isTest() or ReplicatedStorage:GetAttribute("GameMode") == "FreeFlight") then
		return
	end
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
		if loadout and loadout.armed and loadout.slots[index] then
			loadout.selected = index
			setAttributes(loadout)
		end
	end)
	Net.Server.on("IRCue", function(player: Player, targetId: number)
		local jet = AircraftService:GetJet(player)
		local loadout = jet and loadouts[jet.id]
		if loadout then
			loadout.cueId = targetId
		end
	end)
	Net.Server.on("MissileFire", onMissileFire)
	Net.Server.on("CountermeasureDeploy", onCountermeasure)
	Net.Server.on("DebugLaunchAtMe", onDebugLaunch)
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
