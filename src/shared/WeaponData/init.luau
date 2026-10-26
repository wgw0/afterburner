--!strict
-- Weapon registry (DEVELOPMENT.md §5.4). One module per weapon installation, validated on load.
-- Phase 2 has guns only; missiles arrive in Phase 3 (ACD-05).

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

local RULES: { [string]: { number } | string } = {
	Id = "string",
	DisplayName = "string",
	NameStatus = "name",
	Class = "class",
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

local WeaponData = {}

function WeaponData.validate(id: string, data: any): { string }
	local problems = {}
	if type(data) ~= "table" then
		return { `{id}: module must return a table` }
	end
	for field, rule in RULES do
		local value = data[field]
		if value == nil then
			table.insert(problems, `{id}: missing {field}`)
		elseif rule == "string" then
			if type(value) ~= "string" or value == "" then
				table.insert(problems, `{id}: {field} must be a non-empty string`)
			end
		elseif rule == "name" then
			if value ~= "Real" and value ~= "SemiFictional" then
				table.insert(problems, `{id}: NameStatus must be Real or SemiFictional`)
			end
		elseif rule == "class" then
			if value ~= "Gun" then
				table.insert(problems, `{id}: Class must be Gun (missiles come in Phase 3)`)
			end
		else
			local range = rule :: { number }
			if type(value) ~= "number" or value ~= value or value < range[1] or value > range[2] then
				table.insert(problems, `{id}: {field} = {tostring(value)} is outside {range[1]}..{range[2]}`)
			end
		end
	end
	if data.Id ~= nil and data.Id ~= id then
		table.insert(problems, `{id}: Id "{tostring(data.Id)}" must match the module name`)
	end
	table.sort(problems)
	return problems
end

function WeaponData.load(folder: Instance): { [string]: Gun }
	local loaded: { [string]: Gun } = {}
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

function WeaponData.get(id: string): Gun?
	return registry[id]
end

function WeaponData.getAll(): { [string]: Gun }
	return registry
end

return WeaponData
