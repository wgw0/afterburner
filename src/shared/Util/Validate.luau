--!strict
-- Checks for untrusted values (anything that came from a client).

local Validate = {}

function Validate.isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.isInteger(value: any): boolean
	return Validate.isFiniteNumber(value) and value % 1 == 0
end

function Validate.inRange(value: any, min: number, max: number): boolean
	return Validate.isFiniteNumber(value) and value >= min and value <= max
end

function Validate.isVector3(value: any): boolean
	return typeof(value) == "Vector3"
		and Validate.isFiniteNumber(value.X)
		and Validate.isFiniteNumber(value.Y)
		and Validate.isFiniteNumber(value.Z)
end

function Validate.isUnitVector(value: any, tolerance: number?): boolean
	return Validate.isVector3(value) and math.abs(value.Magnitude - 1) <= (tolerance or 1e-3)
end

function Validate.isString(value: any, maxLength: number?): boolean
	return type(value) == "string" and #value <= (maxLength or 200) and utf8.len(value) ~= nil
end

function Validate.isEnumString(value: any, allowed: { [string]: any } | { string }): boolean
	if type(value) ~= "string" then
		return false
	end
	if (allowed :: any)[value] ~= nil then
		return true
	end
	return table.find(allowed :: { string }, value) ~= nil
end

-- Type specs used by the Net layer. A trailing "?" makes the argument optional (nil allowed).
local checkers: { [string]: (any) -> boolean } = {
	number = Validate.isFiniteNumber,
	integer = Validate.isInteger,
	string = function(v)
		return Validate.isString(v)
	end,
	boolean = function(v)
		return type(v) == "boolean"
	end,
	Vector3 = Validate.isVector3,
	CFrame = function(v)
		return typeof(v) == "CFrame" and Validate.isVector3(v.Position)
	end,
	table = function(v)
		return type(v) == "table"
	end,
	buffer = function(v)
		return type(v) == "buffer"
	end,
	any = function(_)
		return true
	end,
}

function Validate.isKnownSpec(spec: string): boolean
	local base = if string.sub(spec, -1) == "?" then string.sub(spec, 1, -2) else spec
	return checkers[base] ~= nil
end

function Validate.matchesSpec(value: any, spec: string): boolean
	local optional = string.sub(spec, -1) == "?"
	local base = if optional then string.sub(spec, 1, -2) else spec
	if value == nil then
		return optional
	end
	local checker = checkers[base]
	assert(checker, `Unknown type spec "{spec}"`)
	return checker(value)
end

-- Validates an argument list against specs. Returns (ok, reason).
function Validate.args(specs: { string }, count: number, ...: any): (boolean, string?)
	if count > #specs then
		return false, `too many arguments ({count} > {#specs})`
	end
	local values = { ... }
	for i, spec in specs do
		if not Validate.matchesSpec(values[i], spec) then
			return false, `argument {i} failed "{spec}"`
		end
	end
	return true, nil
end

return Validate
