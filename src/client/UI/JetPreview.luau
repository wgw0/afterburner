--!strict
-- A jet on a slow turntable (UI-02): a copy of the aircraft model in a ViewportFrame.
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
		end)
		return function()
			connection:Disconnect()
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
