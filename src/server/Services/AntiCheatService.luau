--!strict
-- Movement anti-cheat for pilot-owned jets (DEVELOPMENT.md §16, SEC-01/03).
-- The pilot's client owns its jet's physics, so the server samples every jet 10× a second and checks the
-- step against what that airframe can physically do (MovementCheck). A violation is a strike; 3 strikes
-- in 10 s resets the jet to its last good state; 3 resets in a minute kicks. Never bans automatically:
-- everything is logged (Telemetry + a rate-limited server warning) for review.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local MovementCheck = require(Shared.MovementCheck)

local Telemetry = require(ServerScriptService.Server.Lib.Telemetry)
local AircraftService = require(script.Parent.AircraftService)

type Jet = AircraftService.Jet

local SAMPLE_INTERVAL = 0.1
local GRACE = 3 -- seconds after spawning or a reset before checks apply
local RESET_HANDBACK = 0.5 -- seconds the server holds the jet after a reset

type Watch = {
	limits: MovementCheck.Limits,
	previous: MovementCheck.Sample?,
	lastGood: { cframe: CFrame, velocity: Vector3 }?,
	graceUntil: number,
}

local AntiCheatService = {
	Priority = 45,
	violations = 0, -- total, for tests and the admin panel
	resets = 0,
	kicks = 0,
}

local watches: { [number]: Watch } = {}
local strikes: { [Player]: MovementCheck.Strikes } = {}
local lastWarn: { [Player]: number } = {}
local kicked: { [Player]: boolean } = {}

-- Counters on ServerStorage, readable by tests and admin tools (server-only).
local function publish()
	ServerStorage:SetAttribute("AntiCheatViolations", AntiCheatService.violations)
	ServerStorage:SetAttribute("AntiCheatResets", AntiCheatService.resets)
	ServerStorage:SetAttribute("AntiCheatKicks", AntiCheatService.kicks)
end

local function resetJet(jet: Jet, watch: Watch)
	local good = watch.lastGood
	local pilot = jet.pilot
	if not (good and pilot) then
		return
	end
	AntiCheatService.resets += 1
	publish()
	jet.root:SetNetworkOwner(nil)
	jet.model:PivotTo(good.cframe)
	jet.root.AssemblyLinearVelocity = good.velocity
	local linear = jet.root:FindFirstChild("FlightLinear") :: LinearVelocity?
	if linear then
		linear.VectorVelocity = good.velocity
	end
	watch.previous = nil
	watch.graceUntil = os.clock() + GRACE
	task.delay(RESET_HANDBACK, function()
		if AircraftService:GetJetById(jet.id) and pilot.Parent then
			jet.root:SetNetworkOwner(pilot)
		end
	end)
end

local function check(jet: Jet, watch: Watch, now: number)
	local pilot = jet.pilot
	if not pilot or kicked[pilot] then
		return
	end
	local sample = { time = now, position = jet.root.Position, velocity = jet.root.AssemblyLinearVelocity }
	local previous = watch.previous
	watch.previous = sample
	if now < watch.graceUntil or not previous then
		watch.lastGood = { cframe = jet.root.CFrame, velocity = sample.velocity }
		return
	end
	local ok, reason, detail = MovementCheck.evaluate(previous, sample, watch.limits)
	if ok then
		watch.lastGood = { cframe = jet.root.CFrame, velocity = sample.velocity }
		return
	end

	AntiCheatService.violations += 1
	publish()
	Telemetry.event("AntiCheatStrike", detail, { reason = reason }, pilot)
	if os.clock() - (lastWarn[pilot] or 0) > 5 then
		lastWarn[pilot] = os.clock()
		warn(
			`[AntiCheat] {pilot.Name} ({pilot.UserId}): {reason} {math.round(detail or 0)} `
				.. `(speed {math.round(previous.velocity.Magnitude)} -> {math.round(sample.velocity.Magnitude)} studs/s, `
				.. `moved {math.round((sample.position - previous.position).Magnitude)} studs in {string.format(
					"%.2f",
					now - previous.time
				)} s)`
		)
	end
	local playerStrikes = strikes[pilot] or MovementCheck.newStrikes()
	strikes[pilot] = playerStrikes
	local action = MovementCheck.strike(playerStrikes, now)
	if action == "reset" then
		resetJet(jet, watch)
	elseif action == "kick" then
		kicked[pilot] = true
		AntiCheatService.kicks += 1
		publish()
		Telemetry.event("AntiCheatKick", 1, { reason = reason }, pilot)
		warn(`[AntiCheat] Kicking {pilot.Name} ({pilot.UserId}) after repeated movement violations`)
		pilot:Kick("Disconnected: movement anomaly detected. If this keeps happening, please report it.")
	end
end

function AntiCheatService:Init()
	publish()
	AircraftService.JetSpawned:Connect(function(jet)
		if jet.pilot then
			local airframe = AircraftData.get(jet.airframeId) :: any
			watches[jet.id] = {
				limits = MovementCheck.limits(airframe),
				previous = nil,
				lastGood = nil,
				graceUntil = os.clock() + GRACE,
			}
		end
	end)
	AircraftService.JetDestroyed:Connect(function(jet)
		watches[jet.id] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		strikes[player] = nil
		lastWarn[player] = nil
		kicked[player] = nil
	end)
end

function AntiCheatService:Start()
	local timer = 0
	RunService.Heartbeat:Connect(function(dt)
		timer += dt
		if timer < SAMPLE_INTERVAL then
			return
		end
		timer = 0
		local now = os.clock()
		for id, watch in watches do
			local jet = AircraftService:GetJetById(id)
			if jet then
				check(jet, watch, now)
			else
				watches[id] = nil
			end
		end
	end)
end

return AntiCheatService
