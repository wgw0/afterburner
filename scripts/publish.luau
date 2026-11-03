-- Publishes every place of an experience in one go, without Studio (RELEASE.md "Every place, every time").
-- For each place: takes its file in the repo (the models, skins and other assets), swaps in the code from a
-- fresh Rojo build, checks the models, and uploads it with Roblox's Open Cloud place publishing API.
-- Usage:
--   lune run scripts/publish.luau test          both places of Afterburner (TEST)
--   lune run scripts/publish.luau live          both places of Afterburner (asks first; master, committed)
--   lune run scripts/publish.luau test --dry    build and check the files (build/publish/) without uploading
-- The API key (Creator Hub → Open Cloud → API Keys, "universe-places" write access to both experiences) is
-- read from the ROBLOX_API_KEY environment variable, or from publish-key.txt in the repo root (gitignored).
-- Asset changes (a new jet, new skins) still happen in Studio: change the TEST place, Download a Copy over
-- its file here, commit, then run this for each experience.

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local stdio = require("@lune/stdio")

-- The places of each experience and the repo file each is published from (ids as in Config/Places)
local EXPERIENCES = {
	test = {
		name = "Afterburner (TEST)",
		universe = 10773135125,
		places = {
			{ name = "Lobby (the Strait)", id = 72582604278324, file = "Afterburner.rbxl" },
			{ name = "Desert Range", id = 105532168384050, file = "DesertRange.rbxl" },
		},
	},
	live = {
		name = "Afterburner (live)",
		universe = 10773807904,
		places = {
			{ name = "Lobby (the Strait)", id = 95037764806358, file = "Afterburner.rbxl" },
			{ name = "Desert Range", id = 130074220241967, file = "DesertRange.rbxl" },
		},
	},
}

-- The code subtrees Rojo manages (default.project.json), as in scripts/run-tests.luau
local MAPPED = {
	{ "ReplicatedStorage", "Shared" },
	{ "ReplicatedStorage", "Packages" },
	{ "ServerScriptService", "Server" },
	{ "ServerStorage", "Tests" },
	{ "ServerStorage", "Tools" },
	{ "ServerStorage", "ServerPackages" },
	{ "StarterPlayer", "StarterPlayerScripts", "Client" },
}

local function fail(message: string): never
	stdio.ewrite(stdio.color("red") .. "✗ " .. message .. stdio.color("reset") .. "\n")
	process.exit(1)
	error(message)
end

local function run(program: string, args: { string }): string
	local result = process.exec(program, args)
	if not result.ok then
		fail(`{program} {table.concat(args, " ")} failed:\n{result.stdout}{result.stderr}`)
	end
	return result.stdout
end

local function apiKey(): string
	local key = process.env.ROBLOX_API_KEY
	if (not key or key == "") and fs.isFile("publish-key.txt") then
		key = fs.readFile("publish-key.txt")
	end
	key = key and string.gsub(key, "%s", "") or ""
	if key == "" then
		fail("No API key: set ROBLOX_API_KEY, or put the key in publish-key.txt in the repo root")
	end
	return key
end

-- A place file with the fresh code in it
local function withCode(placeFile: string, built: any): string
	local game = roblox.deserializePlace(fs.readFile(placeFile))
	for _, path in MAPPED do
		local from, to = built, game
		for i = 1, #path - 1 do
			from = from:FindFirstChild(path[i])
			to = to:FindFirstChild(path[i]) or game:GetService(path[i])
		end
		local fresh = from and from:FindFirstChild(path[#path])
		if not fresh then
			fail(`The build has no {table.concat(path, ".")}`)
		end
		local old = to:FindFirstChild(path[#path])
		if old then
			old:Destroy()
		end
		fresh:Clone().Parent = to
	end
	return roblox.serializePlace(game)
end

-- Arguments
local which = process.args[1]
local dry = table.find(process.args, "--dry") ~= nil
local experience = which and EXPERIENCES[which]
if not experience then
	fail("Say which experience: lune run scripts/publish.luau test   (or live)")
end

-- Live only goes out from a committed master, and only when asked twice
if which == "live" and not dry then
	local branch = string.gsub(run("git", { "branch", "--show-current" }), "%s", "")
	if branch ~= "master" then
		fail(`Live is published from master (you're on {branch}): merge first`)
	end
	if
		string.gsub(
			run("git", { "status", "--porcelain", "--", "src", "Afterburner.rbxl", "DesertRange.rbxl" }),
			"%s",
			""
		) ~= ""
	then
		fail("There are uncommitted changes to the code or place files: commit them first")
	end
	if not stdio.prompt("confirm", "Publish every place of the LIVE game? Players get it on their next server") then
		fail("Not published")
	end
end

print(`Publishing {experience.name}{if dry then " (dry run: nothing is uploaded)" else ""}`)
local key = if dry then "" else apiKey()

-- Build the code once
fs.writeDir("build/publish")
run("rojo", { "build", "-o", "build/publish/code.rbxl" })
local built = roblox.deserializePlace(fs.readFile("build/publish/code.rbxl"))

for _, place in experience.places do
	if not fs.isFile(place.file) then
		fail(`{place.file} is missing`)
	end
	local out = `build/publish/{which}-{place.id}.rbxl`
	fs.writeFile(out, withCode(place.file, built))
	-- The same model check as for a downloaded place
	run("lune", { "run", "scripts/validate-models.luau", out })
	if dry then
		print(`  ✓ {place.name}: built and checked ({out})`)
		continue
	end
	local response = net.request({
		url = `https://apis.roblox.com/universes/v1/{experience.universe}/places/{place.id}/versions?versionType=Published`,
		method = "POST",
		headers = { ["x-api-key"] = key, ["Content-Type"] = "application/octet-stream" },
		body = fs.readFile(out),
	})
	if not response.ok then
		fail(`{place.name} wasn't published (HTTP {response.statusCode}): {response.body}`)
	end
	local ok, decoded = pcall(net.jsonDecode, response.body)
	local version = if ok and type(decoded) == "table" then decoded.versionNumber else "?"
	print(`  ✓ {place.name}: published, version {version}`)
end

print(
	if dry
		then "Done (dry run)."
		else "Done. New servers run this version; restart servers in Creator Hub to move everyone now."
)
