--!strict
-- Minimal test framework for pure modules (DEVELOPMENT.md §33).
-- Run from the Studio command bar (or the MCP execute tool) in Edit mode:
--   require(game.ServerStorage.Tests.TestRunner).run()
-- Modules are cloned before requiring, so edits synced by Rojo are always picked up (no require cache).
--
-- A spec is a ModuleScript named *.spec that returns function(ctx), where ctx provides
-- describe, it, expect and Shared (a fresh clone of ReplicatedStorage.Shared).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestRunner = {}

export type Result = { passed: number, failed: number, skipped: number, failures: { string } }

-- Headless runs (scripts/run-tests.luau, TST-04) have no physics or terrain: a test that needs them calls
-- ctx.engineOnly() first and is counted as skipped there.
local SKIP = "[engine-only test skipped]"

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function show(value: any): string
	if type(value) == "string" then
		return `"{value}"`
	end
	return tostring(value)
end

local function makeExpect()
	return function(actual: any)
		local e = {}
		function e.toBe(expected: any)
			if actual ~= expected then
				error(`expected {show(expected)}, got {show(actual)}`, 2)
			end
		end
		function e.toEqual(expected: any)
			if not deepEqual(actual, expected) then
				error(`expected tables to be deeply equal`, 2)
			end
		end
		function e.toBeCloseTo(expected: number, tolerance: number?)
			local tol = tolerance or 1e-6
			local diff = if typeof(actual) == "Vector3"
				then (actual - expected).Magnitude
				else math.abs(actual - expected)
			if diff > tol then
				error(`expected {show(actual)} to be within {tol} of {show(expected)}`, 2)
			end
		end
		function e.toBeTruthy()
			if not actual then
				error(`expected a truthy value, got {show(actual)}`, 2)
			end
		end
		function e.toBeFalsy()
			if actual then
				error(`expected a falsy value, got {show(actual)}`, 2)
			end
		end
		function e.toBeGreaterThan(expected: number)
			if not (actual > expected) then
				error(`expected {show(actual)} > {show(expected)}`, 2)
			end
		end
		function e.toBeLessThan(expected: number)
			if not (actual < expected) then
				error(`expected {show(actual)} < {show(expected)}`, 2)
			end
		end
		function e.toThrow(pattern: string?)
			local ok, err = pcall(actual)
			if ok then
				error("expected function to throw", 2)
			end
			if pattern and not string.find(tostring(err), pattern, 1, true) then
				error(`expected error containing "{pattern}", got "{err}"`, 2)
			end
		end
		return e
	end
end

-- Runs every *.spec module under the Tests folder. Optional filter matches spec names.
function TestRunner.run(filter: string?): Result
	local result: Result = { passed = 0, failed = 0, skipped = 0, failures = {} }
	local headless = game:GetAttribute("TestsHeadless") == true
	local function engineOnly()
		if headless then
			error(SKIP, 0)
		end
	end
	local sandbox = Instance.new("Folder")
	sandbox.Name = "TestSandbox"
	local shared = ReplicatedStorage:WaitForChild("Shared"):Clone()
	shared.Parent = sandbox
	local tests = (script.Parent :: Instance):Clone()
	tests.Parent = sandbox
	sandbox.Parent = game:GetService("ServerStorage")

	local expect = makeExpect()

	for _, spec in tests:GetDescendants() do
		if not (spec:IsA("ModuleScript") and string.match(spec.Name, "%.spec$")) then
			continue
		end
		if filter and not string.find(spec.Name, filter, 1, true) then
			continue
		end

		local prefix = { string.gsub(spec.Name, "%.spec$", "") }
		local stack: { string } = { prefix[1] }

		local function describe(name: string, body: () -> ())
			table.insert(stack, name)
			body()
			table.remove(stack)
		end

		local function it(name: string, body: () -> ())
			local fullName = table.concat(stack, " > ") .. " > " .. name
			local ok, err = xpcall(body, function(e)
				return tostring(e)
			end)
			if ok then
				result.passed += 1
			elseif string.find(err, SKIP, 1, true) then
				result.skipped += 1
			else
				result.failed += 1
				table.insert(result.failures, `{fullName}\n    {err}`)
			end
		end

		local loaded, specFn = pcall(require, spec)
		if not loaded or type(specFn) ~= "function" then
			result.failed += 1
			table.insert(result.failures, `{spec.Name}: failed to load ({specFn})`)
			continue
		end
		local ran, err =
			pcall(specFn, { describe = describe, it = it, expect = expect, Shared = shared, engineOnly = engineOnly })
		if not ran then
			result.failed += 1
			table.insert(result.failures, `{spec.Name}: error outside a test ({err})`)
		end
	end

	sandbox:Destroy()

	print(
		`[Tests] {result.passed} passed, {result.failed} failed`
			.. (if result.skipped > 0 then `, {result.skipped} skipped (need the engine)` else "")
	)
	for _, failure in result.failures do
		warn(`[Tests] FAIL {failure}`)
	end
	return result
end

return TestRunner
