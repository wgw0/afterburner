--!strict
-- The Strait's sky and light (MAP-03), after John Constable: an English afternoon, a warm hazy
-- horizon, soft blue overhead and heaped cumulus. The skybox is painted by tools/blender/sky_paint.py
-- with the same sun direction this sets (the clouds are lit from the sun's side); real volumetric
-- clouds sit below it, tinted to match, for flying through.
-- Run in Edit mode: require(game.ServerStorage.Tools.SkyBuilder).build()
-- Re-run sky_paint.py with the printed sun direction if the time of day or latitude changes.

local Lighting = game:GetService("Lighting")

local SKY = { -- tools/blender/out/textures/sky/Sky_<face>.png
	Ft = "rbxassetid://118679307222703",
	Bk = "rbxassetid://122828760196459",
	Lf = "rbxassetid://122089654119265",
	Rt = "rbxassetid://87213036243594",
	Up = "rbxassetid://110985701659360",
	Dn = "rbxassetid://121807682653138",
}

local GRASS = { -- tools/blender/out/textures/terrain/<name>_Color.png
	{
		name = "StraitGrass",
		material = Enum.Material.Grass,
		colorMap = "rbxassetid://104092848076892",
		tint = Color3.fromRGB(172, 180, 150),
	},
	{
		name = "StraitLeafyGrass",
		material = Enum.Material.LeafyGrass,
		colorMap = "rbxassetid://94963831683337",
		tint = Color3.fromRGB(160, 172, 138),
	},
}

local SkyBuilder = {}

local function child(parent: Instance, className: string, name: string): any
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		existing.Name = name
		return existing
	end
	local made = Instance.new(className)
	made.Name = name
	made.Parent = parent
	return made
end

function SkyBuilder.build(): string
	-- An afternoon in the south of England
	Lighting.GeographicLatitude = 51.5
	Lighting.ClockTime = 15.75
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(112, 112, 120)
	Lighting.OutdoorAmbient = Color3.fromRGB(136, 140, 152)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 238, 210) -- warm low sun
	Lighting.ColorShift_Bottom = Color3.fromRGB(46, 52, 66)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.ExposureCompensation = 0.1
	Lighting.ShadowSoftness = 0.35

	local sky = child(Lighting, "Sky", "Sky") :: Sky
	for face, id in SKY do
		(sky :: any)["Skybox" .. face] = id
	end
	sky.SkyboxOrientation = Vector3.zero
	sky.CelestialBodiesShown = true
	sky.SunAngularSize = 12
	sky.StarCount = 0

	-- Haze: warm near the ground, bluing with distance
	local atmosphere = child(Lighting, "Atmosphere", "Atmosphere") :: Atmosphere
	-- (density works per stud, and the map is 40,000 studs across: 0.3 swallowed the ground)
	atmosphere.Density = 0.1
	atmosphere.Offset = 0.05
	atmosphere.Color = Color3.fromRGB(214, 210, 196)
	atmosphere.Decay = Color3.fromRGB(122, 142, 172)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 0.6

	local clouds = child(workspace.Terrain, "Clouds", "Clouds") :: Clouds
	clouds.Cover = 0.55
	clouds.Density = 0.6
	clouds.Color = Color3.fromRGB(252, 247, 236)

	local grade = child(Lighting, "ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	grade.Brightness = 0
	grade.Contrast = 0.06
	grade.Saturation = 0.05
	grade.TintColor = Color3.fromRGB(255, 251, 242)

	local bloom = child(Lighting, "BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 1.6

	local rays = child(Lighting, "SunRaysEffect", "SunRays") :: SunRaysEffect
	rays.Intensity = 0.06
	rays.Spread = 0.6

	-- Grass seen from the air: a patchwork of fields and hedgerows (tools/blender/terrain_paint.py),
	-- tiled large, in place of the grass decoration that only draws within a few dozen studs
	local MaterialService = game:GetService("MaterialService")
	for _, spec in GRASS do
		local variant = MaterialService:FindFirstChild(spec.name) or Instance.new("MaterialVariant")
		variant.Name = spec.name
		variant.BaseMaterial = spec.material
		variant.ColorMap = spec.colorMap
		variant.StudsPerTile = 2048 -- fields ~400 studs (110 m) across
		variant.MaterialPattern = Enum.MaterialPattern.Regular -- terrain doesn't draw Organic variants
		variant.Parent = MaterialService
		MaterialService:SetBaseMaterialOverride(spec.material, spec.name)
		-- The terrain colour tints the texture; lighter than the old flat greens so the fields show
		workspace.Terrain:SetMaterialColor(spec.material, spec.tint)
	end

	local sun = Lighting:GetSunDirection()
	return string.format("sky built; sun direction %.4f %.4f %.4f (pass to sky_paint.py --sun)", sun.X, sun.Y, sun.Z)
end

return SkyBuilder
