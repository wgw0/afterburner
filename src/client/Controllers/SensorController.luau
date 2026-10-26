--!strict
-- What your jet knows about other jets (DEVELOPMENT.md §14, SNS-01/02).
--   Visual: spotted within 3 km (5 km if they're high enough to leave contrails) with clear line of sight.
--   Radar: contacts your radar can see right now (same rules the server uses for locks).
--   Lock: your radar lock, as confirmed by the server.
--   IR seeker: for the selected heat-seeker, the target it sees and how long it's been held (for the
--     tone and the HUD). The server keeps its own copy and decides what can actually be fired.
--   RWR: threats the server says are painting you.
-- Updated 5× a second; the HUD, scopes, camera (padlock) and audio read from here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Flight = require(Shared.Config.Flight)
local Guidance = require(Shared.Guidance)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Signature = require(Shared.Signature)
local Units = require(Shared.Units)
local WeaponData = require(Shared.WeaponData)

local FlightController = require(script.Parent.FlightController)

local UPDATE_INTERVAL = 0.2
local VISUAL_RANGE = 3000 -- real metres
local CONTRAIL_VISUAL_RANGE = 5000

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
	irTargetId = 0, -- what the selected heat-seeker sees, 0 = nothing
	irHeldFor = 0, -- seconds the seeker has held irTargetId
	irLocked = false, -- held for the missile's LockTime
	threats = {} :: { Threat },
	LockChanged = Signal.new(), -- (id, state)
}

local losParams: RaycastParams

local function clearLineOfSight(from: Vector3, to: Vector3): boolean
	return workspace:Raycast(from, to - from, losParams) == nil
end

function SensorController:SelectedMissile(): WeaponData.Missile?
	local jet = FlightController.jet
	local id = jet and jet:GetAttribute("SelectedMissile") :: string?
	return if id and id ~= "" then WeaponData.getMissile(id) else nil
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

local function update()
	local self = SensorController
	local jet, root = FlightController.jet, FlightController.root
	if not (jet and root) then
		table.clear(self.contacts)
		self.irTargetId, self.irHeldFor, self.irLocked = 0, 0, false
		return
	end
	local airframe = AircraftData.get(jet:GetAttribute("AirframeId") :: string) :: any
	local radar = airframe and airframe.Radar
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

	-- IR seeker for the selected heat-seeker
	local missile = self:SelectedMissile()
	local bestId, bestDot = 0, -2
	if missile and WeaponData.isIR(missile) then
		for id, contact in self.contacts do
			local throttle = (contact.model:GetAttribute("Throttle") :: number?) or 0.85
			local afterburner = contact.model:GetAttribute("Afterburner") == true
			local otherRoot = contact.model.PrimaryPart
			if otherRoot and Guidance.irLockable(missile, myCF, otherRoot.CFrame, throttle, afterburner) then
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
		self.lockId = if state == "Locked" then targetId else 0
		self.LockChanged:Fire(targetId, state)
	end)
	Net.Client.on("RWRUpdate", function(threats: { Threat })
		self.threats = threats
	end)
	FlightController.JetChanged:Connect(function()
		self.lockId = 0
		self.threats = {}
	end)
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
