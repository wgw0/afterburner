--!strict
-- Radar locks and the radar warning receiver (DEVELOPMENT.md §14, SNS-03/05).
--   Locks are validated by the server when requested and re-checked 5× a second (range, cone, clutter
--   or notch, terrain line of sight). Break any rule and the lock is lost: both pilots find out.
--   RWR: every pilot hears who is searching them, who has locked them, and (for radar missiles, or IR
--   missiles if their jet has a missile-approach warner) who has launched at them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared.Progression)
local Countermeasures = require(Shared.Countermeasures)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Signature = require(Shared.Signature)
local Units = require(Shared.Units)

local AircraftService = require(script.Parent.AircraftService)

type Jet = AircraftService.Jet
type Lock = { target: number, since: number }
export type Threat = { id: number, kind: string, position: Vector3 }

local LOCK_CHECK_INTERVAL = 0.2
local RWR_INTERVAL = 0.5

local SensorService = {
	Priority = 32,
	LockChanged = Signal.new(), -- (shooterJet, targetJetId or 0)
}

local locks: { [number]: Lock } = {}
local lastRwr: { [Player]: string } = {}
local worldParams: RaycastParams
-- Extra RWR "Launch" threats contributed by MissileService (missiles guiding on a jet).
local launchThreats: () -> { [number]: { Threat } } = function()
	return {}
end

local function radarOf(jet: Jet): any
	local airframe = Progression.airframeForModel(jet.model) :: any
	return airframe and airframe.Radar
end

-- Radar cross-section factor (Signature.radarDetects): 1 for ordinary jets, small for stealth ones.
local function stealthOf(jet: Jet): number
	local airframe = Progression.airframeForModel(jet.model) :: any
	return airframe and airframe.Stealth or 1
end

local function realVelocity(jet: Jet): Vector3
	return Units.velocityFromStuds(jet.root.AssemblyLinearVelocity)
end

local function lineOfSight(from: Vector3, to: Vector3): boolean
	return workspace:Raycast(from, to - from, worldParams) == nil
end

-- Can `shooter`'s radar see `target` right now? Returns (ok, reason).
function SensorService:CanTrack(shooter: Jet, target: Jet): (boolean, string)
	local radar = radarOf(shooter)
	if not radar then
		return false, "no radar"
	end
	local ok, reason = Signature.radarDetects(
		radar,
		shooter.root.CFrame,
		target.root.Position,
		realVelocity(target),
		stealthOf(target)
	)
	if not ok then
		return false, reason
	end
	if not lineOfSight(shooter.root.Position, target.root.Position) then
		return false, "terrain"
	end
	return true, "ok"
end

-- Is the target notching relative to a radar at `radarPosition`?
function SensorService:IsNotching(radarPosition: Vector3, target: Jet): boolean
	return math.abs(Signature.radialSpeed(radarPosition, target.root.Position, realVelocity(target)))
		< Signature.NOTCH_SPEED
end

function SensorService:GetLock(shooterJetId: number): number?
	local lock = locks[shooterJetId]
	return lock and lock.target
end

function SensorService:LockAge(shooterJetId: number): number
	local lock = locks[shooterJetId]
	return if lock then os.clock() - lock.since else 0
end

local function setLock(shooter: Jet, targetId: number?, state: string)
	local before = locks[shooter.id]
	if targetId then
		if not before or before.target ~= targetId then
			locks[shooter.id] = { target = targetId, since = os.clock() }
		end
	else
		locks[shooter.id] = nil
	end
	if shooter.pilot then
		Net.Server.fire("LockState", shooter.pilot, targetId or 0, state)
	end
	SensorService.LockChanged:Fire(shooter, targetId or 0)
end

-- The server asks for a lock on a pilot's behalf (AI pilots). Same rules as a player's request.
function SensorService:RequestLock(shooter: Jet, target: Jet): boolean
	if shooter == target then
		return false
	end
	local ok = self:CanTrack(shooter, target)
	if ok then
		setLock(shooter, target.id, "Locked")
	end
	return ok
end

-- Called by MissileService when a jet drops chaff: each radar locked on it may lose the lock.
function SensorService:OnChaff(target: Jet, seed: number)
	for shooterId, lock in locks do
		if lock.target == target.id then
			local shooter = AircraftService:GetJetById(shooterId)
			if shooter then
				local chance = Countermeasures.chaffLockBreakChance(self:IsNotching(shooter.root.Position, target))
				if Countermeasures.roll(seed, shooterId) < chance then
					setLock(shooter, nil, "Lost")
				end
			end
		end
	end
end

function SensorService:SetLaunchThreatProvider(provider: () -> { [number]: { Threat } })
	launchThreats = provider
end

local function recheckLocks()
	for shooterId, lock in locks do
		local shooter = AircraftService:GetJetById(shooterId)
		local target = AircraftService:GetJetById(lock.target)
		if not shooter then
			locks[shooterId] = nil
		elseif not target then
			setLock(shooter, nil, "Lost")
		else
			local ok = SensorService:CanTrack(shooter, target)
			if not ok then
				setLock(shooter, nil, "Lost")
			end
		end
	end
end

local function updateRwr()
	local jets = AircraftService:GetJets()
	local launches = launchThreats()
	for _, jet in jets do
		local pilot = jet.pilot
		if not pilot then
			continue
		end
		local threats: { Threat } = {}
		for _, other in jets do
			if other.id ~= jet.id then
				local radar = radarOf(other)
				if radar then
					local lock = locks[other.id]
					if lock and lock.target == jet.id then
						table.insert(threats, { id = other.id, kind = "Lock", position = other.root.Position })
					else
						-- The RWR hears a search radar whose beam covers you, clutter or not.
						local los = jet.root.Position - other.root.Position
						local inRange = Units.toMetres(los.Magnitude) <= radar.Range
						local inCone = los.Magnitude > 1e-3
							and other.root.CFrame.LookVector:Dot(los.Unit) >= math.cos(math.rad(radar.Cone))
						if inRange and inCone then
							table.insert(threats, { id = other.id, kind = "Search", position = other.root.Position })
						end
					end
				end
			end
		end
		for _, threat in launches[jet.id] or {} do
			table.insert(threats, threat)
		end
		-- Only send when something changed (or once a second, as a heartbeat).
		local signature = {}
		for _, t in threats do
			table.insert(signature, `{t.id}:{t.kind}`)
		end
		table.sort(signature)
		local key = table.concat(signature, ",") .. "|" .. math.floor(os.clock())
		if lastRwr[pilot] ~= key then
			lastRwr[pilot] = key
			Net.Server.fire("RWRUpdate", pilot, threats)
		end
	end
end

function SensorService:Init()
	worldParams = RaycastParams.new()
	worldParams.FilterType = Enum.RaycastFilterType.Exclude
	worldParams.FilterDescendantsInstances = { workspace:WaitForChild("Jets") }

	Net.Server.on("RadarLockRequest", function(player: Player, targetId: number)
		local shooter = AircraftService:GetJet(player)
		if not shooter then
			return
		end
		if targetId == 0 then
			setLock(shooter, nil, "None")
			return
		end
		local target = AircraftService:GetJetById(targetId)
		if not target or target == shooter then
			return
		end
		local ok = self:CanTrack(shooter, target)
		if ok then
			setLock(shooter, target.id, "Locked")
		elseif shooter.pilot then
			Net.Server.fire("LockState", shooter.pilot, 0, "Lost")
		end
	end)

	AircraftService.JetDestroyed:Connect(function(jet)
		locks[jet.id] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastRwr[player] = nil
	end)
end

function SensorService:Start()
	local lockTimer, rwrTimer = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		lockTimer += dt
		rwrTimer += dt
		if lockTimer >= LOCK_CHECK_INTERVAL then
			lockTimer = 0
			debug.profilebegin("SensorService.locks")
			recheckLocks()
			debug.profileend()
		end
		if rwrTimer >= RWR_INTERVAL then
			rwrTimer = 0
			debug.profilebegin("SensorService.rwr")
			updateRwr()
			debug.profileend()
		end
	end)
end

return SensorService
