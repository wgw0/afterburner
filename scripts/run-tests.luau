--!nonstrict -- a small Roblox runtime for Lune; its shims are deliberately loose
-- TST-04: runs the unit tests (tests/*.spec, the same TestRunner Studio uses) headless, outside Roblox.
-- Loads the committed place (for its models and assets), swaps in the code from a fresh Rojo build, then
-- runs ServerStorage.Tests.TestRunner with a minimal Roblox runtime: ModuleScripts are loaded from their
-- Source with `script` and an instance-aware `require`, and the few engine pieces the tests touch are
-- shimmed below. Exits non-zero if any test fails.
-- Usage: lune run scripts/run-tests.luau [built.rbxl] [place.rbxl] [filter]
--   (defaults: build/Afterburner.rbxl, Afterburner.rbxl; run `rojo build -o build/Afterburner.rbxl` first)

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local taskLib = require("@lune/task")

local builtPath = process.args[1] or "build/Afterburner.rbxl"
local placePath = process.args[2] or "Afterburner.rbxl"
local filter = process.args[3]

local game = roblox.deserializePlace(fs.readFile(placePath))
local built = roblox.deserializePlace(fs.readFile(builtPath))

-- The code subtrees Rojo manages (default.project.json): the place's copies may be stale, so they're
-- replaced by the fresh build.
local MAPPED = {
	{ "ReplicatedStorage", "Shared" },
	{ "ReplicatedStorage", "Packages" },
	{ "ServerScriptService", "Server" },
	{ "ServerStorage", "Tests" },
	{ "ServerStorage", "Tools" },
	{ "ServerStorage", "ServerPackages" },
	{ "StarterPlayer", "StarterPlayerScripts", "Client" },
}
for _, path in MAPPED do
	local from, to = built, game
	for i = 1, #path - 1 do
		from = from:FindFirstChild(path[i])
		to = to:FindFirstChild(path[i]) or game:GetService(path[i])
	end
	local fresh = from and from:FindFirstChild(path[#path])
	if fresh then
		local old = to:FindFirstChild(path[#path])
		if old then
			old.Parent = nil
		end
		fresh:Clone().Parent = to
	end
end

---------------------------------------------------------------------------
-- Shims for the engine pieces the tests and the modules they load touch
---------------------------------------------------------------------------

-- Random: a seeded generator with Roblox's API (not Roblox's exact sequence). Code here often seeds a fresh
-- generator from neighbouring numbers and takes its first value (Countermeasures.roll), so seeds and outputs
-- both go through MurmurHash3's finalizer to keep those first values independent.
local TWO32 = 4294967296
local function mul32(a: number, b: number): number
	local lo, hi = a % 65536, (a - a % 65536) / 65536
	return (((hi * b) % 65536) * 65536 + lo * b) % TWO32
end
local function fmix32(h: number): number
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x85EBCA6B)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 0xC2B2AE35)
	return bit32.bxor(h, bit32.rshift(h, 16))
end

local Random = {}
Random.__index = Random
Random.__type = "Random"
function Random.new(seed: number?)
	local s = math.floor(seed or os.clock() * 1e6)
	local lo, hi = s % TWO32, math.floor(s / TWO32) % TWO32
	local state = fmix32(bit32.bxor(fmix32(lo), mul32(hi, 0x9E3779B1)))
	return setmetatable({ state = if state == 0 then 0x9E3779B9 else state }, Random)
end
function Random:_next(): number
	-- xorshift32 steps the state; the output is mixed again
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return fmix32(x) / TWO32
end
function Random:NextNumber(min: number?, max: number?): number
	local lo, hi = min or 0, max or 1
	return lo + (hi - lo) * self:_next()
end
function Random:NextInteger(min: number, max: number): number
	return min + math.floor(self:_next() * (max - min + 1))
end
function Random:Shuffle(t: { any })
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end

-- CFrame.lookAt (and the two-point CFrame.new) in Lune 0.10.5 point the wrong way along Z; this builds them
-- the way Roblox does
local function lookAt(at, target, up)
	up = up or roblox.Vector3.new(0, 1, 0)
	local look = (target - at).Unit
	if math.abs(look:Dot(up.Unit)) > 0.9999 then
		up = roblox.Vector3.new(0, 0, 1)
	end
	local right = look:Cross(up).Unit
	return roblox.CFrame.fromMatrix(at, right, right:Cross(look), -look)
end
local CFrame = setmetatable({
	lookAt = lookAt,
	new = function(...)
		local a, b = ...
		if select("#", ...) == 2 and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			return lookAt(a, b)
		end
		return roblox.CFrame.new(...)
	end,
}, { __index = roblox.CFrame })

-- Engine methods and properties Lune's instances don't have
game.GameId = 0 -- known to Lune but without a value in a loaded place
game.PlaceId = 0
roblox.implementMethod("RunService", "IsStudio", function()
	return false
end)
roblox.implementMethod("Instance", "WaitForChild", function(self, name: string)
	local child = self:FindFirstChild(name)
	if not child then
		error(`{self:GetFullName()}.{name} doesn't exist (WaitForChild would wait forever)`, 2)
	end
	return child
end)

local base = {
	game = game,
	workspace = game:GetService("Workspace"),
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Rect = roblox.Rect,
	Ray = roblox.Ray,
	BrickColor = roblox.BrickColor,
	Enum = roblox.Enum,
	Random = Random,
	task = taskLib,
	tick = os.clock,
	warn = function(...)
		print("[warn]", ...)
	end,
}

local cache: { [any]: any } = {}
local loading: { [any]: boolean } = {}
local requireModule

-- Each module gets its own globals table (luau.load doesn't follow an __index fallback), with `script`
local function envFor(scriptInstance)
	local env = table.clone(base)
	env.script = scriptInstance
	env.require = requireModule
	return env
end

function requireModule(target)
	if typeof(target) ~= "Instance" then
		error(`require({tostring(target)}): only ModuleScript instances are supported here`, 2)
	end
	local cached = cache[target]
	if cached ~= nil then
		return cached
	end
	if loading[target] then
		error(`require loop at {target:GetFullName()}`, 2)
	end
	loading[target] = true
	local chunk = luau.load(target.Source, { debugName = target:GetFullName(), environment = envFor(target) })
	local result = chunk()
	loading[target] = nil
	cache[target] = result
	return result
end
base.require = requireModule

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------

game:SetAttribute("TestsHeadless", true) -- ctx.engineOnly() skips tests that need the real engine
local runner = game:GetService("ServerStorage"):FindFirstChild("Tests"):FindFirstChild("TestRunner")
local TestRunner = requireModule(runner)
local result = TestRunner.run(filter)
process.exit(if result.failed == 0 then 0 else 1)
