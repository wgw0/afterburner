--!strict
-- ACD-03 (CI half): checks the aircraft models inside the committed place file, outside Roblox.
-- Opens the .rbxl with Lune, runs the same AircraftModelContract.validate the server runs at boot on
-- every model in ReplicatedStorage.Assets.Aircraft, and checks every airframe in AircraftData has one.
-- Usage: lune run scripts/validate-models.luau [path/to/place.rbxl]   (default: Afterburner.rbxl)

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Contract = require("../src/shared/AircraftModelContract")

local path = process.args[1] or "Afterburner.rbxl"
local game = roblox.deserializePlace(fs.readFile(path))

local problems: { string } = {}
local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
local aircraft = assets and assets:FindFirstChild("Aircraft")
if not aircraft then
	print(`{path}: ReplicatedStorage.Assets.Aircraft is missing`)
	process.exit(1)
end

local models: { [string]: boolean } = {}
for _, model in (aircraft :: any):GetChildren() do
	models[model.Name] = true
	for _, problem in Contract.validate(model) do
		table.insert(problems, problem)
	end
end

-- Every airframe needs a model (AircraftData/<Id>.luau ↔ Assets.Aircraft.<Id>)
local airframes = 0
for _, file in fs.readDir("src/shared/AircraftData") do
	local id = string.match(file, "^(.+)%.luau$")
	if id and id ~= "init" then
		airframes += 1
		if not models[id] then
			table.insert(problems, `{id}: airframe has no model in ReplicatedStorage.Assets.Aircraft`)
		end
	end
end

-- Every missile family has a drawable model (WeaponData MISSILE_MODELS ↔ Assets.Missiles.<Family>), and every
-- missile names one of them (the Model field)
local families: { string } = {}
local registry = fs.readFile("src/shared/WeaponData/init.luau")
local list = string.match(registry, "local MISSILE_MODELS = {([^}]*)}")
for family in string.gmatch(list or "", '"([%w_]+)"') do
	table.insert(families, family)
end
if #families == 0 then
	table.insert(problems, "src/shared/WeaponData/init.luau: MISSILE_MODELS not found")
end
local missiles = (assets :: any):FindFirstChild("Missiles")
for _, family in families do
	local model = missiles and missiles:FindFirstChild(family)
	if not (model and model:IsA("Model")) then
		table.insert(problems, `{family}: missile family has no model in ReplicatedStorage.Assets.Missiles`)
	elseif not (model.PrimaryPart and model.PrimaryPart.Anchored) then
		table.insert(problems, `Assets.Missiles.{family}: needs an anchored PrimaryPart`)
	elseif not (model.PrimaryPart:FindFirstChild("Tail") and model:GetAttribute("Length")) then
		table.insert(problems, `Assets.Missiles.{family}: needs a Tail attachment and a Length attribute`)
	end
end
for _, file in fs.readDir("src/shared/WeaponData") do
	local source = file ~= "init.luau" and fs.readFile(`src/shared/WeaponData/{file}`)
	if source and string.match(source, 'Class = "[^"]*"') ~= 'Class = "Gun"' then
		local family = string.match(source, 'Model = "([%w_]+)"')
		if not (family and table.find(families, family)) then
			table.insert(problems, `{file}: missile needs a Model from MISSILE_MODELS`)
		end
	end
end

if #problems > 0 then
	print(`Model contract FAILED for {path}:`)
	for _, problem in problems do
		print(`  - {problem}`)
	end
	process.exit(1)
end
local count = 0
for _ in models do
	count += 1
end
print(`Model contract OK: {count} models checked, {airframes} airframes covered ({path})`)
