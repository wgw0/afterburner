--!strict
-- A jet on a slow turntable (UI-02): a copy of the aircraft model in a ViewportFrame.
-- A ViewportFrame doesn't draw SurfaceGuis, which is how kill markers and wing art are painted on a jet
-- (Shared/HullDecal). Wing art's pictures move into Decals (WingArt.toDecals). Kill markers are text, so each
-- strip is drawn as a label over the ViewportFrame instead, following the strip's place on the turning jet
-- and shown while that side faces the camera (checked in Studio, November 2026).
-- props: AirframeId, Skin (optional), Mastery (stars, for kill markers; optional), Marker and WingArt (equipped
-- cosmetics, optional), Size, Position, AnchorPoint.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local KillMarkers = require(Shared:WaitForChild("KillMarkers"))
local WingArt = require(Shared:WaitForChild("WingArt"))
local Skins = require(Shared:WaitForChild("Skins"))
local Theme = require(script.Parent.Theme)

local e = React.createElement

type Overlay = { plate: BasePart, label: TextLabel }

-- Takes each kill-marker strip's text off its plate and makes a label for it over the viewport.
local function overlays(model: Model, viewport: ViewportFrame): { Overlay }
	local list = {}
	for _, plate in model:GetDescendants() do
		local gui = plate:IsA("BasePart") and plate.Name == "KillMarkers" and plate:FindFirstChildWhichIsA("SurfaceGui")
		local text = gui and gui:FindFirstChildWhichIsA("TextLabel")
		if not (gui and text) then
			continue
		end
		local label = text:Clone()
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Visible = false
		label.ZIndex = 2
		label.Parent = viewport
		gui:Destroy()
		table.insert(list, { plate = plate :: BasePart, label = label })
	end
	return list
end

-- Where a point falls in the viewport, in pixels (nil behind the camera).
local function project(camera: Camera, size: Vector2, point: Vector3): Vector2?
	local rel = camera.CFrame:PointToObjectSpace(point)
	if rel.Z >= -0.01 then
		return nil
	end
	local scale = math.tan(math.rad(camera.FieldOfView) / 2) * -rel.Z
	local x = rel.X / (scale * size.X / size.Y)
	local y = rel.Y / scale
	return Vector2.new((x + 1) / 2 * size.X, (1 - y) / 2 * size.Y)
end

-- Lays a strip's label over its plate as the camera sees it: its ends (the SurfaceGui's left is the plate's +X
-- seen from the front), its height, and hidden while the plate faces away.
local function place(mark: Overlay, camera: Camera, size: Vector2)
	local cf, half = mark.plate.CFrame, mark.plate.Size / 2
	local facing = (camera.CFrame.Position - cf.Position):Dot(cf.LookVector) > 0
	local left = project(camera, size, cf * Vector3.new(half.X, 0, 0))
	local right = project(camera, size, cf * Vector3.new(-half.X, 0, 0))
	local top = project(camera, size, cf * Vector3.new(0, half.Y, 0))
	local bottom = project(camera, size, cf * Vector3.new(0, -half.Y, 0))
	if not (facing and left and right and top and bottom) then
		mark.label.Visible = false
		return
	end
	local along = right - left
	mark.label.Visible = true
	mark.label.Position = UDim2.fromOffset((left.X + right.X) / 2, (left.Y + right.Y) / 2)
	mark.label.Size = UDim2.fromOffset(along.Magnitude, (top - bottom).Magnitude)
	mark.label.Rotation = math.deg(math.atan2(along.Y, along.X))
end

local function JetPreview(props: any)
	local viewportRef = React.useRef(nil)

	React.useEffect(function()
		local viewport = viewportRef.current :: ViewportFrame?
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local source = assets and assets:FindFirstChild("Aircraft") and assets.Aircraft:FindFirstChild(props.AirframeId)
		if not (viewport and source) then
			return nil
		end
		local world = Instance.new("WorldModel")
		local model = source:Clone() :: Model
		if props.Skin then
			Skins.apply(model, props.AirframeId, props.Skin)
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		model:PivotTo(CFrame.new())
		model.Parent = world
		world.Parent = viewport
		-- Once the world is in the game (rays don't work in a detached one): they're cast onto the skin
		KillMarkers.apply(model, props.Mastery or 0, props.Marker)
		WingArt.apply(model, props.WingArt)
		WingArt.toDecals(model)
		local marks = overlays(model, viewport)
		local _, size = model:GetBoundingBox()
		local distance = math.max(size.X, size.Z) * 1.45 + 2.8
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		local angle = math.rad(210)
		local connection = RunService.RenderStepped:Connect(function(dt)
			angle += dt * 0.35
			local eye = Vector3.new(math.sin(angle) * distance, distance * 0.32, math.cos(angle) * distance)
			camera.CFrame = CFrame.lookAt(eye, Vector3.new(0, 0, 0))
			for _, mark in marks do
				place(mark, camera, viewport.AbsoluteSize)
			end
		end)
		return function()
			connection:Disconnect()
			for _, mark in marks do
				mark.label:Destroy()
			end
			world:Destroy()
			camera:Destroy()
		end
	end, { props.AirframeId, props.Skin, props.Mastery, props.Marker, props.WingArt })

	return e("ViewportFrame", {
		ref = viewportRef,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(150, 160, 180),
		LightColor = Color3.fromRGB(255, 245, 230),
		LightDirection = Vector3.new(-1, -1, -0.5),
		ImageColor3 = Theme.Text,
	})
end

return JetPreview
