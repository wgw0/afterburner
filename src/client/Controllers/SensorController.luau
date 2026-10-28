--!strict
-- What your jet knows about other jets (DEVELOPMENT.md §14, SNS-01/02).
--   Visual: spotted within 3 km (5 km if they're high enough to leave contrails) with clear line of sight.
--   Radar: contacts your radar can see right now (same rules the server uses for locks).
--   Lockable: the contacts the selected missile could lock right now (heat-seeker: inside its seeker
--     cone and hot enough at that range; radar missile: on your radar). The HUD circles them.
--   Lock: your radar lock, as confirmed by the server. Pressing lock starts a 1 s lock-on (the target
--     must stay on radar) before the request goes to the server, so a radar lock builds up like an IR one.
--   IR seeker: for the selected heat-seeker, the target it sees and how long it's been held (for the
--     tone and the HUD). The server keeps its own copy and decides what can actually be fired.
--     The lock key cages the seeker (off, silent) and uncages it again. With none of the selected
--     missile left, the seeker is off and nothing is shown as lockable.
--   RWR: threats the server says are painting you.
-- Updated 5× a second; the HUD, scopes, camera (padlock) and audio read from here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Progression = require(Shared.Progression)
local Flight = require(Shared.Config.Flight)
local Guidance = require(Shared.Guidance)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Signature = require(Shared.Signature)
local Units = require(Shared.Units)
local WeaponData = require(Shared.WeaponData)

local FlightController = require(script.Parent.FlightController)

local UPDATE_INTERVAL = 0.2
local RADAR_LOCK_ON = 1.0 -- seconds a radar contact is held before the lock request
local VISUAL_RANGE = 3000 -- real metres
local CONTRAIL_VISUAL_RANGE = 5000
local MESSAGE_TIME = 3 -- seconds a lock message stays on the HUD

-- Why the radar can't see a target, in HUD words (Signature.radarDetects reasons, plus terrain)
local REASONS = {
	range = "OUT OF RADAR RANGE",
	cone = "NOT IN RADAR CONE",
	clutter = "GROUND CLUTTER",
	notch = "TARGET NOTCHING",
	terrain = "TERRAIN IN THE WAY",
}

export type Contact = {
	model: Model,
	id: number,
	position: Vector3,
	velocity: Vector3, -- real m/s
	range: number, -- real metres
	spotted: boolean,
	onRadar: boolean,
}

export type Threat = { id: number, kind: string, position: Vector3 }

local SensorController = {
	Priority = 33,
	contacts = {} :: { [number]: Contact },
	lockId = 0, -- your radar lock (server-confirmed), 0 = none
	lockable = {} :: { [number]: boolean },
	acquiringId = 0, -- radar lock-on in progress (before / while asking the server), 0 = none
	acquireStart = 0,
	requestedAt = 0,
	irTargetId = 0, -- what the selected heat-seeker sees, 0 = nothing
	irHeldFor = 0, -- seconds the seeker has held irTargetId
	irLocked = false, -- held for the missile's LockTime
	seekerCaged = false, -- the pilot switched the heat-seeker off (lock key)
	threats = {} :: { Threat },
	message = "", -- why a lock failed or broke, shown on the HUD until messageUntil
	messageUntil = 0,
	LockChanged = Signal.new(), -- (id, state)
}

local losParams: RaycastParams
local lastMissileId = ""

local function clearLineOfSight(from: Vector3, to: Vector3): boolean
	return workspace:Raycast(from, to - from, losParams) == nil
end

function SensorController:SelectedMissile(): WeaponData.Missile?
	local jet = FlightController.jet
	local id = jet and jet:GetAttribute("SelectedMissile") :: string?
	return if id and id ~= "" then WeaponData.getMissile(id) else nil
end

-- How many of the selected missile are left.
function SensorController:MissilesLeft(): number
	local jet = FlightController.jet
	local id = jet and jet:GetAttribute("SelectedMissile") :: string?
	if not (jet and id and id ~= "") then
		return 0
	end
	return (jet:GetAttribute(`Msl_{id}`) :: number?) or 0
end

function SensorController:GetModel(id: number): Model?
	local contact = self.contacts[id]
	return contact and contact.model
end

-- Best thing to padlock: your lock, else your IR target, else the nearest spotted jet ahead.
function SensorController:PadlockTarget(): Model?
	if self.lockId ~= 0 and self.contacts[self.lockId] then
		return self.contacts[self.lockId].model
	end
	if self.irTargetId ~= 0 and self.contacts[self.irTargetId] then
		return self.contacts[self.irTargetId].model
	end
	local best, bestRange = nil, math.huge
	for _, contact in self.contacts do
		if contact.spotted and contact.range < bestRange then
			best, bestRange = contact.model, contact.range
		end
	end
	return best
end

local function radarOf(jet: Model): Signature.RadarSpec?
	local airframe = Progression.airframeForModel(jet) :: any
	return airframe and airframe.Radar
end

-- Why your radar can't see `model` right now ("ok" if it can).
local function reasonFor(model: Model): string
	local jet, root = FlightController.jet, FlightController.root
	local radar = jet and radarOf(jet)
	local otherRoot = model.PrimaryPart
	if not (root and radar and otherRoot) then
		return "range"
	end
	local velocity = Units.velocityFromStuds(otherRoot.AssemblyLinearVelocity)
	local ok, reason = Signature.radarDetects(radar, root.CFrame, otherRoot.Position, velocity)
	if ok and not clearLineOfSight(root.Position, otherRoot.Position) then
		return "terrain"
	end
	return reason
end

local function say(text: string)
	SensorController.message = text
	SensorController.messageUntil = os.clock() + MESSAGE_TIME
end

-- Explains why the lock key found nothing to lock: the reason for the jet nearest your nose.
function SensorController:ExplainNoLock()
	local jet, root = FlightController.jet, FlightController.root
	if not (jet and root) then
		return
	end
	if not radarOf(jet) then
		say("NO RADAR")
		return
	end
	local best, bestDot = nil, -2
	for _, model in workspace.Jets:GetChildren() do
		local otherRoot = model:IsA("Model") and model ~= jet and model.PrimaryPart
		if otherRoot then
			local dot = root.CFrame.LookVector:Dot((otherRoot.Position - root.Position).Unit)
			if dot > bestDot then
				best, bestDot = model, dot
			end
		end
	end
	say(if best then `NO LOCK: {REASONS[reasonFor(best)] or "NO TARGET"}` else "NO LOCK: NO TARGETS")
end

-- Shows a message on the HUD for a few seconds (e.g. "NO LOCK: PRESS T").
function SensorController:Say(text: string)
	say(text)
end

local function lockBroken(id: number, heading: string)
	local model = SensorController:GetModel(id)
	if not model then -- dropped from the contacts once the radar lost it
		for _, other in workspace.Jets:GetChildren() do
			if other:IsA("Model") and other:GetAttribute("JetId") == id then
				model = other
			end
		end
	end
	local reason = if model then REASONS[reasonFor(model)] else nil
	say(if reason then `{heading}: {reason}` else heading)
end

local function update()
	local self = SensorController
	local jet, root = FlightController.jet, FlightController.root
	if not (jet and root) then
		table.clear(self.contacts)
		self.irTargetId, self.irHeldFor, self.irLocked = 0, 0, false
		return
	end
	local radar = radarOf(jet)
	local myCF = root.CFrame
	local seen: { [number]: boolean } = {}

	for _, model in workspace.Jets:GetChildren() do
		if not model:IsA("Model") or model == jet then
			continue
		end
		local id = model:GetAttribute("JetId") :: number?
		local otherRoot = model.PrimaryPart
		if not (id and otherRoot) then
			continue
		end
		local range = Units.toMetres((otherRoot.Position - myCF.Position).Magnitude)
		local velocity = Units.velocityFromStuds(otherRoot.AssemblyLinearVelocity)
		local high = Units.altitudeMetres(otherRoot.Position.Y) > Flight.CONTRAIL_ALTITUDE
		local visualRange = if high then CONTRAIL_VISUAL_RANGE else VISUAL_RANGE
		local los = nil
		local function hasLos(): boolean
			if los == nil then
				los = clearLineOfSight(myCF.Position, otherRoot.Position)
			end
			return los :: boolean
		end
		local spotted = range <= visualRange and hasLos()
		local onRadar = false
		if radar then
			onRadar = Signature.radarDetects(radar, myCF, otherRoot.Position, velocity) and hasLos()
		end
		if spotted or onRadar or id == self.lockId then
			seen[id] = true
			self.contacts[id] = {
				model = model,
				id = id,
				position = otherRoot.Position,
				velocity = velocity,
				range = range,
				spotted = spotted,
				onRadar = onRadar,
			}
		end
	end
	for id in self.contacts do
		if not seen[id] then
			self.contacts[id] = nil
		end
	end

	-- IR seeker for the selected heat-seeker; what the selected missile could lock
	local missile = self:SelectedMissile()
	if missile and missile.Id ~= lastMissileId then
		self.seekerCaged = false -- a newly selected missile starts with its seeker on
	end
	lastMissileId = if missile then missile.Id else ""
	if self:MissilesLeft() == 0 then
		missile = nil -- nothing left to fire: no seeker, nothing lockable
	end
	local bestId, bestDot = 0, -2
	table.clear(self.lockable)
	if missile and WeaponData.isRadar(missile) then
		for id, contact in self.contacts do
			if contact.onRadar then
				self.lockable[id] = true
			end
		end
	end
	if self.acquiringId ~= 0 then
		local contact = self.contacts[self.acquiringId]
		-- Give up if the contact left the radar before the lock-on finished, or the server never answered.
		local lost = not (contact and contact.onRadar)
		local unanswered = self.acquireStart == 0 and os.clock() - self.requestedAt > 2
		if lost or unanswered then
			if lost then
				lockBroken(self.acquiringId, "LOCK BROKEN")
			end
			self.acquiringId = 0
		elseif self.acquireStart > 0 and os.clock() - self.acquireStart >= RADAR_LOCK_ON then
			self.acquireStart = 0 -- asked; waiting for the server's answer
			self.requestedAt = os.clock()
			Net.Client.fire("RadarLockRequest", self.acquiringId)
		end
	end
	if missile and WeaponData.isIR(missile) and not self.seekerCaged then
		for id, contact in self.contacts do
			local throttle = (contact.model:GetAttribute("Throttle") :: number?) or 0.85
			local afterburner = contact.model:GetAttribute("Afterburner") == true
			local otherRoot = contact.model.PrimaryPart
			if otherRoot and Guidance.irLockable(missile, myCF, otherRoot.CFrame, throttle, afterburner) then
				self.lockable[id] = true
				local dot = myCF.LookVector:Dot((otherRoot.Position - myCF.Position).Unit)
				if dot > bestDot then
					bestId, bestDot = id, dot
				end
			end
		end
	end
	if bestId ~= self.irTargetId then
		self.irTargetId, self.irHeldFor = bestId, 0
	elseif bestId ~= 0 then
		self.irHeldFor += UPDATE_INTERVAL
	end
	self.irLocked = missile ~= nil and bestId ~= 0 and self.irHeldFor >= missile.LockTime
end

function SensorController:Init()
	losParams = RaycastParams.new()
	losParams.FilterType = Enum.RaycastFilterType.Exclude
	losParams.FilterDescendantsInstances = { workspace:WaitForChild("Jets") }

	Net.Client.on("LockState", function(targetId: number, state: string)
		if state == "Lost" then
			-- The server sends no target with a lost lock: explain it against the one we had
			lockBroken(if self.lockId ~= 0 then self.lockId else self.acquiringId, "LOCK LOST")
		elseif state == "Locked" then
			self.messageUntil = 0
		end
		self.lockId = if state == "Locked" then targetId else 0
		self.acquiringId = 0
		self.LockChanged:Fire(targetId, state)
	end)
	Net.Client.on("RWRUpdate", function(threats: { Threat })
		self.threats = threats
	end)
	FlightController.JetChanged:Connect(function()
		self.lockId = 0
		self.acquiringId = 0
		self.seekerCaged = false
		self.threats = {}
	end)
end

-- Starts a radar lock-on on a contact (the server is asked once it has stayed on radar for 1 s).
function SensorController:StartRadarLock(id: number)
	self.acquiringId = id
	self.acquireStart = os.clock()
end

-- Switches the heat-seeker off (silent, nothing tracked) or back on.
function SensorController:ToggleSeeker()
	self.seekerCaged = not self.seekerCaged
	self.irTargetId, self.irHeldFor, self.irLocked = 0, 0, false
end

-- Drops the radar lock, or cancels a lock-on in progress.
function SensorController:CancelRadarLock()
	self.acquiringId = 0
	if self.lockId ~= 0 then
		Net.Client.fire("RadarLockRequest", 0)
	end
end

function SensorController:Start()
	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer += dt
		if timer >= UPDATE_INTERVAL then
			timer = 0
			debug.profilebegin("SensorController.update")
			update()
			debug.profileend()
		end
	end)
end

return SensorController
