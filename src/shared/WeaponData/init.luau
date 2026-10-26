--!strict
-- Weapon registry (DEVELOPMENT.md §5.4). One module per weapon, validated on load.
-- Guns (Phase 2) and missiles (Phase 3, ACD-05) share the registry; each class has its own rules.

export type Gun = {
	Id: string,
	DisplayName: string,
	NameStatus: "Real" | "SemiFictional",
	Class: "Gun",
	RateOfFire: number, -- rounds per minute, whole installation
	MuzzleVelocity: number, -- real m/s
	Damage: number, -- per hit, before component multipliers
	Ammo: number, -- rounds carried
	Spread: number, -- degrees, cone half-angle
	Drag: number, -- 1/m: deceleration = Drag × speed²
	Lifetime: number, -- seconds before a round is discarded
	HeatPerShot: number, -- 0..1 heat added per round
	CoolRate: number, -- heat removed per second
}

export type MissileClass = "IR_Rear" | "IR_All" | "IR_Adv" | "SARH" | "ARH"

export type Missile = {
	Id: string,
	DisplayName: string,
	NameStatus: "Real" | "SemiFictional",
	Class: MissileClass,
	MotorBurnTime: number, -- seconds
	MotorAccel: number, -- m/s² along the flight path while the motor burns
	Drag: number, -- 1/m at sea level: deceleration = Drag × (ρ/ρ0) × speed²
	MaxG: number, -- turn limit at full energy
	MinSpeed: number, -- real m/s: below this the missile stops guiding
	MaxRange: number, -- real metres (launch zone display)
	MinRange: number, -- real metres (arming distance)
	SeekerCone: number, -- degrees off the shooter's nose a target can be locked
	Gimbal: number, -- degrees off the missile's nose the seeker can track
	LockTime: number, -- seconds a target must be held before launch (IR)
	NavConstant: number, -- proportional navigation gain
	FlareResistance: number, -- 0..1
	ChaffResistance: number, -- 0..1
	ProximityFuse: number, -- real metres
	Damage: number,
	Lifetime: number, -- seconds before self-destruct
}

local MISSILE_CLASSES = { "IR_Rear", "IR_All", "IR_Adv", "SARH", "ARH" }

local COMMON: { [string]: string } = {
	Id = "string",
	DisplayName = "string",
	NameStatus = "name",
	Class = "class",
}

local GUN_RULES: { [string]: { number } } = {
	RateOfFire = { 100, 8000 },
	MuzzleVelocity = { 300, 1500 },
	Damage = { 1, 200 },
	Ammo = { 10, 3000 },
	Spread = { 0, 3 },
	Drag = { 0, 0.01 },
	Lifetime = { 0.5, 6 },
	HeatPerShot = { 0, 0.1 },
	CoolRate = { 0, 2 },
}

local MISSILE_RULES: { [string]: { number } } = {
	MotorBurnTime = { 0.5, 15 },
	MotorAccel = { 20, 800 },
	Drag = { 0, 0.001 },
	MaxG = { 5, 60 },
	MinSpeed = { 50, 600 },
	MaxRange = { 500, 200000 },
	MinRange = { 0, 3000 },
	SeekerCone = { 1, 90 },
	Gimbal = { 5, 120 },
	LockTime = { 0, 5 },
	NavConstant = { 2, 6 },
	FlareResistance = { 0, 1 },
	ChaffResistance = { 0, 1 },
	ProximityFuse = { 1, 30 },
	Damage = { 10, 500 },
	Lifetime = { 3, 120 },
}

local WeaponData = {}

function WeaponData.isMissile(weapon: any): boolean
	return type(weapon) == "table" and table.find(MISSILE_CLASSES, weapon.Class) ~= nil
end

function WeaponData.isIR(weapon: any): boolean
	return type(weapon) == "table"
		and (weapon.Class == "IR_Rear" or weapon.Class == "IR_All" or weapon.Class == "IR_Adv")
end

function WeaponData.isRadar(weapon: any): boolean
	return type(weapon) == "table" and (weapon.Class == "SARH" or weapon.Class == "ARH")
end

function WeaponData.validate(id: string, data: any): { string }
	local problems = {}
	if type(data) ~= "table" then
		return { `{id}: module must return a table` }
	end
	for field, rule in COMMON do
		local value = data[field]
		if value == nil then
			table.insert(problems, `{id}: missing {field}`)
		elseif rule == "string" and (type(value) ~= "string" or value == "") then
			table.insert(problems, `{id}: {field} must be a non-empty string`)
		elseif rule == "name" and value ~= "Real" and value ~= "SemiFictional" then
			table.insert(problems, `{id}: NameStatus must be Real or SemiFictional`)
		elseif rule == "class" and value ~= "Gun" and not table.find(MISSILE_CLASSES, value) then
			table.insert(problems, `{id}: unknown Class {tostring(value)}`)
		end
	end
	local rules = if data.Class == "Gun" then GUN_RULES elseif WeaponData.isMissile(data) then MISSILE_RULES else nil
	for field, range in rules or {} do
		local value = data[field]
		if value == nil then
			table.insert(problems, `{id}: missing {field}`)
		elseif type(value) ~= "number" or value ~= value or value < range[1] or value > range[2] then
			table.insert(problems, `{id}: {field} = {tostring(value)} is outside {range[1]}..{range[2]}`)
		end
	end
	if data.Id ~= nil and data.Id ~= id then
		table.insert(problems, `{id}: Id "{tostring(data.Id)}" must match the module name`)
	end
	table.sort(problems)
	return problems
end

function WeaponData.load(folder: Instance): { [string]: any }
	local loaded: { [string]: any } = {}
	local all = {}
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, data = pcall(require, child)
			if not ok then
				table.insert(all, `{child.Name}: failed to load ({data})`)
				continue
			end
			local problems = WeaponData.validate(child.Name, data)
			if #problems > 0 then
				table.move(problems, 1, #problems, #all + 1, all)
			else
				loaded[child.Name] = table.freeze(data)
			end
		end
	end
	if #all > 0 then
		error("[WeaponData] Invalid weapons:\n  " .. table.concat(all, "\n  "), 0)
	end
	return loaded
end

local registry = WeaponData.load(script)

-- A gun (nil if the id isn't a gun).
function WeaponData.get(id: string): Gun?
	local w = registry[id]
	return if w and w.Class == "Gun" then w else nil
end

-- A missile (nil if the id isn't a missile).
function WeaponData.getMissile(id: string): Missile?
	local w = registry[id]
	return if WeaponData.isMissile(w) then w else nil
end

function WeaponData.getAll(): { [string]: any }
	return registry
end

return WeaponData
