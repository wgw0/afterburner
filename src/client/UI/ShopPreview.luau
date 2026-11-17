--!strict
-- The picture on a Shop card (Will: every item shows what you're buying). props: Id (a Config/Cosmetics id),
-- Size, Position, AnchorPoint.
--   Camo: its picture (the F-16A in it, tools/blender/camo_cards.py).
--   Trail: the F-16A on afterburner in a ViewportFrame, streaming display smoke in the trail's colours from
--     both wingtips (several colours follow one another along the trail, as in the game). Trails and beams
--     don't draw in a ViewportFrame, so the smoke is a line of glowing puffs.
--   WingArt: looking straight down on the F-16A's right wing, close in on the decal (Shared/WingArt; a decal is
--     only about 2 studs across on a 15-stud jet, too small to read with the whole jet in view). Its
--     SurfaceGuis don't draw in a ViewportFrame either, so each plate's picture is swapped for a Decal.
--   Marker: drawn flat: a strip of grey hull with a row of five of the marks, as under the canopy.
-- The jet scenes are still (no turntable), so a ViewportFrame only draws once; the scene is built a frame
-- after the card mounts so opening the Shop doesn't stall.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalogue = require(Shared:WaitForChild("Config"):WaitForChild("Cosmetics"))
local WingArt = require(Shared:WaitForChild("WingArt"))
local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement

local AIRFRAME = "F16A" -- the camo cards' jet, in its own default skin
local PUFFS = 40 -- per wingtip: close enough to read as one plume
local MARKS = 5 -- a five-star mastery's row
local AFTERBURNER = Color3.fromRGB(255, 150, 60)

-- A colour along a list of colours (0 = the first, 1 = the last), as a ColorSequence would give it.
local function along(colours: { Color3 }, t: number): Color3
	if #colours == 1 then
		return colours[1]
	end
	local x = math.clamp(t, 0, 1) * (#colours - 1)
	local i = math.min(math.floor(x) + 1, #colours - 1)
	return colours[i]:Lerp(colours[i + 1], x - (i - 1))
end

local function anchored(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
end

local function part(shape: Enum.PartType, colour: Color3, size: number, at: Vector3, transparency: number): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Material = Enum.Material.Neon -- flat and bright: reads bold on a small card
	p.Color = colour
	p.Size = Vector3.one * size
	p.Position = at
	p.Transparency = transparency
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	return p
end

-- Display smoke from both wingtips and the afterburner lit; returns where the camera should look.
local function smoke(model: Model, colours: { Color3 }, length: number): Vector3
	local root = model.PrimaryPart :: BasePart
	local back = -root.CFrame.LookVector
	local up = root.CFrame.UpVector
	local trail = length * 1.5
	for _, side in { "WingtipL", "WingtipR" } do
		local tip = root:FindFirstChild(side) :: Attachment?
		if tip then
			for i = 1, PUFFS do
				local t = (i - 1) / (PUFFS - 1)
				local size = length * (0.05 + 0.16 * t) -- spreading as it trails
				local at = tip.WorldPosition + back * (trail * t + size * 0.3) + up * (math.sin(t * 7) * length * 0.015)
				part(Enum.PartType.Ball, along(colours, t), size, at, 0.1 + 0.55 * t).Parent = model
			end
		end
	end
	local nozzle = root:FindFirstChild("Nozzle1") :: Attachment?
	if nozzle then
		local flame = length * 0.06
		part(Enum.PartType.Ball, AFTERBURNER, flame, nozzle.WorldPosition + back * flame * 0.6, 0.15).Parent = model
	end
	return root.Position + back * trail * 0.38
end

-- Wing art's plates hold SurfaceGuis, which a ViewportFrame doesn't draw: put each picture in a Decal instead.
-- Returns the right wing's plate (the card zooms in on it).
local function decals(model: Model): Part?
	local root = model.PrimaryPart :: BasePart
	local right: Part? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("SurfaceGui") and d.Parent and d.Parent.Name == "WingArt" then
			local image = d:FindFirstChildWhichIsA("ImageLabel")
			if image then
				local decal = Instance.new("Decal")
				decal.Face = d.Face
				decal.Texture = image.Image
				decal.Parent = d.Parent
			end
			local plate = d.Parent :: Part
			if (plate.Position - root.Position):Dot(root.CFrame.RightVector) > 0 then
				right = plate
			end
			d:Destroy()
		end
	end
	return right
end

-- The F-16A wearing a contrail or wing art, still, in a ViewportFrame.
local function JetScene(props: any)
	local viewportRef = React.useRef(nil)
	React.useEffect(function()
		local viewport = viewportRef.current :: ViewportFrame?
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local aircraft = assets and assets:FindFirstChild("Aircraft")
		local source = aircraft and aircraft:FindFirstChild(AIRFRAME)
		if not (viewport and source) then
			return nil
		end
		local item = Catalogue.get(props.Id)
		local world = Instance.new("WorldModel")
		local camera = Instance.new("Camera")
		camera.FieldOfView = 30
		local alive = true
		task.defer(function()
			if not alive then
				return
			end
			local model = source:Clone() :: Model
			anchored(model)
			model:PivotTo(CFrame.new())
			model.Parent = world
			world.Parent = viewport -- in the game before WingArt casts its rays
			local root = model.PrimaryPart :: BasePart
			local forward, up, right = root.CFrame.LookVector, root.CFrame.UpVector, root.CFrame.RightVector
			local _, size = model:GetBoundingBox()
			local length = math.max(size.X, size.Z)
			if item and item.Kind == "Trail" then
				local focus = smoke(model, item.Colours or { Color3.new(1, 1, 1) }, length)
				-- From the side, ahead and above: the jet at one end and the smoke streaming away behind it
				local distance = length * 2.3
				local eye = focus + right * distance * 0.8 + forward * distance * 0.45 + up * distance * 0.38
				camera.CFrame = CFrame.lookAt(eye, focus)
			else
				WingArt.apply(model, props.Id)
				local plate = decals(model)
				if plate then
					-- Straight down onto the right wing's decal, close enough to read it, with the wing around it
					-- (checked in Studio: about twice the decal's width away)
					local distance = plate.Size.X * 2.3
					camera.CFrame =
						CFrame.lookAt(plate.Position + plate.CFrame.LookVector * distance, plate.Position, -right)
				else -- no room on the wing: the whole jet from above
					local distance = length * 1.4
					local eye = root.Position + up * distance + right * distance * 0.3
					camera.CFrame = CFrame.lookAt(eye, root.Position, -right)
				end
			end
			camera.Parent = viewport
			viewport.CurrentCamera = camera
		end)
		return function()
			alive = false
			world:Destroy()
			camera:Destroy()
		end
	end, { props.Id })
	return e("ViewportFrame", {
		ref = viewportRef,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 160, 180),
		LightColor = Color3.fromRGB(255, 245, 230),
		LightDirection = Vector3.new(-1, -1, -0.5),
	})
end

-- A kill-marker style, flat: a strip of grey hull with the canopy's edge above and a row of the marks.
local function MarkerStrip(props: any)
	local item = Catalogue.get(props.Id)
	return e("Frame", {
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundTransparency = 1,
	}, {
		Hull = e("Frame", {
			Size = UDim2.fromScale(0.86, 0.56),
			Position = UDim2.fromScale(0.5, 0.56),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(150, 158, 168), -- the default Three-Tone Grey
		}, {
			Corner = C.corner(10),
			Shade = e("UIGradient", {
				Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 125, 135)),
				Rotation = 90,
			}),
			-- The canopy's frame along the top
			Canopy = e("Frame", {
				Size = UDim2.new(0.62, 0, 0, 6),
				Position = UDim2.fromScale(0.08, 0),
				BackgroundColor3 = Color3.fromRGB(40, 46, 56),
				BorderSizePixel = 0,
			}, { Corner = C.corner(3) }),
			Marks = e(C.Label, {
				Text = string.rep(if item then item.Glyph or "★" else "★", MARKS),
				Size = UDim2.fromScale(0.9, 0.62),
				Position = UDim2.fromScale(0.5, 0.58),
				AnchorPoint = Vector2.new(0.5, 0.5),
				TextSize = 30,
				Bold = true,
				Align = "Center",
				Color = if item then item.Colour else Theme.Text,
			}),
		}),
	})
end

local function ShopPreview(props: any)
	local item = Catalogue.get(props.Id)
	if not item then
		return nil
	elseif item.Kind == "Camo" then
		return e("ImageLabel", {
			Image = if item.Images then item.Images[1] else "",
			Size = props.Size,
			Position = props.Position,
			AnchorPoint = props.AnchorPoint,
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
		})
	elseif item.Kind == "Marker" then
		return e(MarkerStrip, props)
	end
	return e(JetScene, props)
end

return ShopPreview
