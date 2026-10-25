--!strict
-- Airframe registry (DEVELOPMENT.md §5.1). Each sibling module defines one airframe.
-- Every airframe is validated when this module loads; any problem stops boot with a clear message.

local Types = require(script.Parent.Types)

type Airframe = Types.Airframe
type Rule =
	{ kind: "string" }
	| { kind: "enum", values: { string } }
	| {
		kind: "number",
		min: number,
		max: number,
		integer: boolean?,
	}
	| { kind: "boolean" }

local function num(min: number, max: number, integer: boolean?): Rule
	return { kind = "number", min = min, max = max, integer = integer }
end
local STRING: Rule = { kind = "string" }
local BOOLEAN: Rule = { kind = "boolean" }
local function enum(values: { string }): Rule
	return { kind = "enum", values = values }
end

-- Required fields and their allowed ranges. Ranges are sanity bounds, not balance targets.
local REQUIRED: { [string]: Rule } = {
	Id = STRING,
	DisplayName = STRING,
	NameStatus = enum({ "Real", "SemiFictional" }),
	FallbackName = STRING,
	Branch = enum({ "NATO", "East", "Europe" }),
	Tier = num(1, 8, true),
	BattleRating = num(1, 15),
	Era = enum({ "Analogue", "EarlyGlass", "FullGlass", "WAD" }),
	ModelName = STRING,
	Mass = num(1000, 40000),
	MaxThrust = num(5000, 400000),
	AfterburnerMult = num(1, 2.5),
	FuelBurnDry = num(0.05, 10),
	FuelBurnAB = num(0.05, 30),
	Fuel = num(200, 20000),
	WingArea = num(5, 150),
	CD0 = num(0.005, 0.1),
	InducedK = num(0.02, 1),
	CLAlpha = num(1, 8),
	CLMax = num(0.5, 3),
	CriticalAoA = num(5, 60),
	MaxG = num(3, 12),
	MinG = num(-6, -0.5),
	MaxRollRate = num(30, 600),
	MaxPitchRate = num(5, 90),
	MaxYawRate = num(1, 60),
	MaxMach = num(0.5, 3.5),
}

local OPTIONAL: { [string]: Rule } = {
	ThrustVectoring = BOOLEAN,
	Stealth = num(0, 1),
}

local function check(field: string, value: any, rule: Rule): string?
	if rule.kind == "string" then
		if type(value) ~= "string" or value == "" then
			return `{field} must be a non-empty string`
		end
	elseif rule.kind == "boolean" then
		if type(value) ~= "boolean" then
			return `{field} must be a boolean`
		end
	elseif rule.kind == "enum" then
		if not table.find((rule :: any).values, value) then
			return `{field} must be one of {table.concat((rule :: any).values, ", ")} (got {tostring(value)})`
		end
	elseif rule.kind == "number" then
		local r = rule :: any
		if type(value) ~= "number" or value ~= value then
			return `{field} must be a number`
		end
		if value < r.min or value > r.max then
			return `{field} = {value} is outside {r.min}..{r.max}`
		end
		if r.integer and value % 1 ~= 0 then
			return `{field} must be a whole number`
		end
	end
	return nil
end

local AircraftData = {}

-- Returns a list of problems (empty when valid). Exposed for tests and tooling.
function AircraftData.validate(id: string, data: any): { string }
	local problems = {}
	if type(data) ~= "table" then
		return { `{id}: module must return a table` }
	end
	for field, rule in REQUIRED do
		if data[field] == nil then
			table.insert(problems, `{id}: missing {field}`)
		else
			local problem = check(field, data[field], rule)
			if problem then
				table.insert(problems, `{id}: {problem}`)
			end
		end
	end
	for field, rule in OPTIONAL do
		if data[field] ~= nil then
			local problem = check(field, data[field], rule)
			if problem then
				table.insert(problems, `{id}: {problem}`)
			end
		end
	end
	if data.Id ~= nil and data.Id ~= id then
		table.insert(problems, `{id}: Id "{tostring(data.Id)}" must match the module name`)
	end
	if type(data.FuelBurnAB) == "number" and type(data.FuelBurnDry) == "number" then
		if data.FuelBurnAB < data.FuelBurnDry then
			table.insert(problems, `{id}: FuelBurnAB must be at least FuelBurnDry`)
		end
	end
	table.sort(problems)
	return problems
end

-- Loads and validates every airframe module in a folder. Errors listing every problem found.
function AircraftData.load(folder: Instance): { [string]: Airframe }
	local loaded: { [string]: Airframe } = {}
	local allProblems = {}
	for _, child in folder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, data = pcall(require, child)
			if not ok then
				table.insert(allProblems, `{child.Name}: failed to load ({data})`)
				continue
			end
			local problems = AircraftData.validate(child.Name, data)
			if #problems > 0 then
				table.move(problems, 1, #problems, #allProblems + 1, allProblems)
			else
				loaded[child.Name] = table.freeze(data)
			end
		end
	end
	if #allProblems > 0 then
		error("[AircraftData] Invalid airframes:\n  " .. table.concat(allProblems, "\n  "), 0)
	end
	return loaded
end

local registry = AircraftData.load(script)

function AircraftData.get(id: string): Airframe?
	return registry[id]
end

function AircraftData.getAll(): { [string]: Airframe }
	return registry
end

function AircraftData.byTier(tier: number): { Airframe }
	local list = {}
	for _, airframe in registry do
		if airframe.Tier == tier then
			table.insert(list, airframe)
		end
	end
	table.sort(list, function(a, b)
		return a.Id < b.Id
	end)
	return list
end

return AircraftData
