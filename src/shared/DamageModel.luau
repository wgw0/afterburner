--!strict
-- Pure damage model (DEVELOPMENT.md §12). The server owns the numbers; the pilot's client turns the
-- component health it's sent into flight model modifiers.
--
-- Components: Cockpit, Fuselage, Engine, WingL, WingR, Tail.
--   Cockpit or Fuselage at 0  -> destroyed
--   A wing at 0               -> destroyed (it comes off)
--   Engine                    -> thrust falls with damage, 0 when destroyed (glide home)
--   Tail                      -> pitch and yaw authority fall with damage
--   Hits on a destroyed part   -> carry on into the fuselage
--   Wings (partial)           -> less lift, and the jet rolls toward the damaged wing

local Types = require(script.Parent.Types)

type Modifiers = Types.Modifiers

export type Health = { [string]: number }

export type DamageRecord = { damage: number, time: number }

export type Credit = {
	killer: any?, -- whoever gets the kill (a Player on the server; anything comparable in tests)
	assists: { any },
	forcedCrash: boolean, -- killed by making the victim crash
	weapon: string?, -- set by CombatService: the killer's last weapon id ("Gun" or a missile)
}

local DamageModel = {}

DamageModel.COMPONENTS = { "Cockpit", "Fuselage", "Engine", "WingL", "WingR", "Tail" }

DamageModel.DEFAULT_HEALTH = table.freeze({
	Cockpit = 40,
	Fuselage = 150,
	Engine = 80,
	WingL = 70,
	WingR = 70,
	Tail = 60,
})

DamageModel.KILL_WINDOW = 15 -- seconds: last damager within this gets the kill
DamageModel.CRASH_WINDOW = 30 -- seconds: damager within this gets a forced-crash kill
DamageModel.ASSIST_WINDOW = 30 -- seconds
DamageModel.ASSIST_SHARE = 0.25 -- of total damage

-- Max health per component for an airframe (its ComponentHealth overrides the defaults).
function DamageModel.maxHealth(airframe: any): Health
	local health = table.clone(DamageModel.DEFAULT_HEALTH) :: Health
	local overrides = airframe and airframe.ComponentHealth
	if overrides then
		for component, value in overrides do
			health[component] = value
		end
	end
	return health
end

-- Applies damage; returns (new health, destroyed?). Never mutates the input.
function DamageModel.applyDamage(health: Health, component: string, amount: number): (Health, boolean)
	local updated = table.clone(health)
	if updated[component] == nil then
		component = "Fuselage" -- unknown hitbox: count it as the airframe
	end
	amount = math.max(amount, 0)
	-- Hits on a part that's already destroyed go into the airframe, so a jet can always be killed from
	-- any angle (otherwise rounds from dead six only ever hit the tail and engine).
	local remaining = updated[component] - amount
	updated[component] = math.max(0, remaining)
	if remaining < 0 and component ~= "Fuselage" then
		updated.Fuselage = math.max(0, updated.Fuselage + remaining)
	end
	return updated, DamageModel.isDestroyed(updated)
end

function DamageModel.isDestroyed(health: Health): boolean
	return (health.Cockpit or 1) <= 0
		or (health.Fuselage or 1) <= 0
		or (health.WingL or 1) <= 0
		or (health.WingR or 1) <= 0
end

-- Fraction of health left (0..1) per component.
function DamageModel.fractions(health: Health, maxHealth: Health): { [string]: number }
	local out = {}
	for component, max in maxHealth do
		out[component] = math.clamp((health[component] or max) / max, 0, 1)
	end
	return out
end

-- Flight model modifiers from component health fractions (FLT-10).
function DamageModel.modifiers(fractions: { [string]: number }): Modifiers
	local engine = fractions.Engine or 1
	local tail = fractions.Tail or 1
	local left = fractions.WingL or 1
	local right = fractions.WingR or 1

	-- Engine: fine to 50%, then thrust drops off; nothing left at 0.
	local thrust = if engine <= 0 then 0 elseif engine < 0.5 then 0.4 + 1.2 * (engine - 0.25) else 1
	thrust = math.clamp(thrust, 0, 1)
	-- Tail: authority falls linearly to 30%.
	local tailAuthority = 0.3 + 0.7 * tail
	-- Wings: lift follows the average wing; roll toward the weaker wing.
	local lift = 0.75 + 0.25 * (left + right) / 2
	local rollBias = (left - right) * math.rad(40) -- weak left wing (left < right) -> roll left (negative)

	return {
		thrust = thrust,
		lift = lift,
		pitch = tailAuthority,
		yaw = tailAuthority,
		roll = 0.6 + 0.4 * math.min(left, right),
		rollBias = rollBias,
	}
end

-- Who gets credit for a destroyed jet. history maps attacker -> { damage, time }.
-- cause: "Shot" | "Crash" | "Collision" | "OutOfBounds" | "PilotLeft"
function DamageModel.resolveCredit(history: { [any]: DamageRecord }, now: number, cause: string): Credit
	local total = 0
	local latest: any? = nil
	local latestTime = -math.huge
	for attacker, record in history do
		if now - record.time <= DamageModel.ASSIST_WINDOW then
			total += record.damage
		end
		if record.time > latestTime then
			latest, latestTime = attacker, record.time
		end
	end

	local window = if cause == "Shot" then DamageModel.KILL_WINDOW else DamageModel.CRASH_WINDOW
	local killer = if latest ~= nil and now - latestTime <= window then latest else nil

	local assists = {}
	if total > 0 then
		for attacker, record in history do
			if
				attacker ~= killer
				and now - record.time <= DamageModel.ASSIST_WINDOW
				and record.damage / total >= DamageModel.ASSIST_SHARE
			then
				table.insert(assists, attacker)
			end
		end
	end

	return { killer = killer, assists = assists, forcedCrash = killer ~= nil and cause ~= "Shot" }
end

return DamageModel
