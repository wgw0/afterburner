--!strict
-- Training lessons 1–3 (DEVELOPMENT.md §28, TUT-01/02). Runs in Free Flight: pick a lesson from the spawn
-- menu, the jet spawns and a prompt panel walks you through the steps. LessonRunner does the bookkeeping;
-- this controller builds the lessons, the prompt panel and the world props (rings, drones).
--   1 Basic flight: pitch, roll, afterburner, then fly through 6 rings.
--   2 Energy: dive for speed, zoom climb (speed bleeds), hard turn (speed bleeds), recover.
--   3 Guns: destroy 3 target drones with the gun.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LessonRunner = require(Shared.LessonRunner)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local Units = require(Shared.Units)

local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)

local ORANGE = Color3.fromRGB(255, 138, 61)
local NAVY = Color3.fromRGB(13, 26, 51)
local RING_COUNT = 6
local RING_RADIUS = 73 -- studs (about 73 m)
local RING_SPACING = 7 -- seconds of flight between rings at the speed you start with

export type Context = {
	state: any, -- FlightState
	root: BasePart,
	afterburner: boolean,
	kills: number,
	dt: number,
}

local TutorialController = {
	Priority = 87,
	active = nil :: string?, -- lesson id while a lesson runs
	Finished = Signal.new(), -- (lessonId)
}

local gui: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local stepLabel: TextLabel
local hintLabel: TextLabel
local runner: LessonRunner.Runner? = nil
local pendingLesson: string? = nil
local props: Folder? = nil
local kills = 0
local myJetId: number? = nil
local doneUntil = 0

local function knots(state: any): number
	return Units.knots(state.speed)
end

local function bank(cf: CFrame): number
	local right = cf.RightVector
	return math.deg(math.asin(math.clamp(-right.Y, -1, 1)))
end

local function pitchDegrees(cf: CFrame): number
	return math.deg(math.asin(math.clamp(cf.LookVector.Y, -1, 1)))
end

local function clearProps()
	if props then
		props:Destroy()
		props = nil
	end
end

local function makeRing(cf: CFrame, index: number): Model
	local ring = Instance.new("Model")
	ring.Name = `Ring{index}`
	local segments = 20
	for i = 1, segments do
		local angle = i / segments * math.pi * 2
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.Neon
		part.Color = if index == 1 then ORANGE else Color3.fromRGB(110, 200, 255)
		part.Size = Vector3.new(3.9, 3.9, 2 * math.pi * RING_RADIUS / segments)
		part.CFrame = cf
			* CFrame.new(math.cos(angle) * RING_RADIUS, math.sin(angle) * RING_RADIUS, 0)
			* CFrame.Angles(0, 0, angle)
			* CFrame.Angles(math.pi / 2, 0, 0)
		part.Parent = ring
	end
	ring:SetAttribute("Centre", cf.Position)
	ring.Parent = props
	return ring
end

-- Lay the rings out ahead of the jet: gentle turns left and right, small climbs and descents.
local function layRings(root: BasePart, state: any): { CFrame }
	clearProps()
	local folder = Instance.new("Folder")
	folder.Name = "TutorialProps"
	folder.Parent = workspace
	props = folder
	local spacing = Units.velocityToStuds(math.max(state.speed, 180)) * RING_SPACING
	local heading = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local cf = CFrame.lookAt(root.Position, root.Position + heading)
	local rings = {}
	for i = 1, RING_COUNT do
		local turn = math.rad(if i % 2 == 0 then 18 else -14)
		local climb = if i % 3 == 0 then -17 else 20
		cf = cf * CFrame.Angles(0, turn, 0) * CFrame.new(0, 0, -spacing)
		cf = cf + Vector3.new(0, climb, 0)
		rings[i] = cf
		makeRing(cf, i)
	end
	return rings
end

local function recolourRings(next: number)
	if not props then
		return
	end
	for _, ring in props:GetChildren() do
		local index = tonumber(string.match(ring.Name, "%d+")) or 0
		for _, part in ring:GetChildren() do
			if part:IsA("BasePart") then
				part.Color = if index == next then ORANGE else Color3.fromRGB(110, 200, 255)
				part.Transparency = if index < next then 1 else 0.15
			end
		end
	end
end

local LESSONS: { [string]: LessonRunner.Lesson } = {
	Flight = {
		id = "Flight",
		title = "LESSON 1 · BASIC FLIGHT",
		steps = {
			{
				text = "Pull the nose up 15° above the horizon.",
				hint = "Mouse up (or stick back). The jet flies to where you aim.",
				check = function(ctx: Context)
					return pitchDegrees(ctx.root.CFrame) > 15
				end,
			},
			{
				text = "Level off, then roll to a 60° bank.",
				hint = "Q / E roll · on a pad or touch, push the stick sideways",
				check = function(ctx: Context)
					return math.abs(bank(ctx.root.CFrame)) > 60
				end,
			},
			{
				text = "Light the afterburner.",
				hint = "Hold W at 100% throttle (RT on a pad, top of the slider on touch)",
				check = function(ctx: Context)
					return ctx.afterburner
				end,
			},
			{
				text = `Fly through all {RING_COUNT} rings. The orange one is next.`,
				hint = "Aim at the ring's centre. Missed one? Loop round and try again.",
				enter = function(ctx: Context, memory)
					memory.rings = layRings(ctx.root, ctx.state)
					memory.next = 1
					recolourRings(1)
				end,
				check = function(ctx: Context, memory)
					local ring: CFrame = memory.rings[memory.next]
					local offset = ring:PointToObjectSpace(ctx.root.Position)
					if math.abs(offset.Z) < 17 and Vector2.new(offset.X, offset.Y).Magnitude < RING_RADIUS then
						memory.next += 1
						recolourRings(memory.next)
					end
					return memory.next > RING_COUNT
				end,
			},
		},
	},
	Energy = {
		id = "Energy",
		title = "LESSON 2 · ENERGY",
		steps = {
			{
				text = "Speed is life. Dive and build up to 500 knots.",
				hint = "Nose down, full throttle. Watch the speed tape on the left.",
				check = function(ctx: Context)
					return knots(ctx.state) >= 500
				end,
			},
			{
				text = "Now zoom climb: pull up and gain 400 m.",
				hint = "Your speed turns into height. Watch it bleed away.",
				enter = function(ctx: Context, memory)
					memory.startAltitude = ctx.state.altitude
				end,
				check = function(ctx: Context, memory)
					return ctx.state.altitude >= memory.startAltitude + 400
				end,
			},
			{
				text = "Level out and pull a hard turn: hold over 5 G for 4 seconds.",
				hint = "Turning costs speed too. Hard turns are paid for with energy.",
				enter = function(_ctx: Context, memory)
					memory.held = 0
					memory.startSpeed = nil
				end,
				check = function(ctx: Context, memory)
					if ctx.state.gLoad > 5 then
						memory.startSpeed = memory.startSpeed or knots(ctx.state)
						memory.held += ctx.dt
					end
					return memory.held >= 4
				end,
			},
			{
				text = "You lost speed in the turn. Get back to 450 knots.",
				hint = "Unload (ease off the stick) and use the afterburner to recover fastest.",
				check = function(ctx: Context)
					return knots(ctx.state) >= 450
				end,
			},
		},
	},
	Guns = {
		id = "Guns",
		title = "LESSON 3 · GUNS",
		steps = {
			{
				text = "A target drone is ahead. Destroy 3 drones with the gun.",
				hint = "Put the pipper (the gun sight) on the drone and hold fire (LMB / A / FIRE).",
				enter = function(_ctx: Context, memory)
					memory.startKills = kills
					memory.spawned = kills
					Net.Client.fire("DebugSpawnDrone", "ahead")
				end,
				check = function(_ctx: Context, memory)
					local got = kills - memory.startKills
					-- One drone at a time: spawn the next after each kill.
					if kills > memory.spawned and got < 3 then
						memory.spawned = kills
						Net.Client.fire("DebugSpawnDrone", "ahead")
					end
					return got >= 3
				end,
			},
		},
	},
}

TutorialController.ORDER = { "Flight", "Energy", "Guns" }

local function label(parent: Instance, size: number, colour: Color3, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = colour
	l.TextWrapped = true
	l.Parent = parent
	return l
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerTutorial"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 12
	gui.Enabled = false

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 34)
	panel.Size = UDim2.fromOffset(520, 92)
	panel.BackgroundColor3 = NAVY
	panel.BackgroundTransparency = 0.2
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = ORANGE
	stroke.Parent = panel

	titleLabel = label(panel, 13, ORANGE, Enum.Font.GothamBold)
	titleLabel.Position = UDim2.fromOffset(12, 6)
	titleLabel.Size = UDim2.new(1, -24, 0, 16)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	stepLabel = label(panel, 18, Color3.new(1, 1, 1), Enum.Font.GothamBold)
	stepLabel.Position = UDim2.fromOffset(12, 24)
	stepLabel.Size = UDim2.new(1, -24, 0, 40)
	hintLabel = label(panel, 13, Color3.fromRGB(190, 200, 220), Enum.Font.Gotham)
	hintLabel.Position = UDim2.new(0, 12, 1, -24)
	hintLabel.Size = UDim2.new(1, -24, 0, 18)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function stop()
	runner = nil
	TutorialController.active = nil
	clearProps()
	if os.clock() > doneUntil then
		gui.Enabled = false
	end
end

local function render()
	local r = runner
	if not r then
		return
	end
	local step = r:current()
	local index, total = r:progress()
	titleLabel.Text = `{r.lesson.title}  ·  STEP {index}/{total}`
	if step then
		stepLabel.Text = step.text
		hintLabel.Text = step.hint or ""
	end
end

-- Start a lesson: spawns the jet (or uses the current one) and runs the steps.
function TutorialController:Begin(lessonId: string, airframeId: string): (boolean, string)
	if not LESSONS[lessonId] then
		return false, "Unknown lesson"
	end
	if ReplicatedStorage:GetAttribute("GameMode") ~= "FreeFlight" then
		return false, "Training runs on Free Flight servers"
	end
	pendingLesson = lessonId
	if FlightController.jet then
		self:_start()
	else
		Net.Client.fire("RequestSpawn", airframeId)
	end
	return true, ""
end

function TutorialController:_start()
	local lessonId = pendingLesson
	pendingLesson = nil
	if not lessonId then
		return
	end
	runner = LessonRunner.new(LESSONS[lessonId])
	self.active = lessonId
	gui.Enabled = true
	render()
end

function TutorialController:Cancel()
	pendingLesson = nil
	stop()
end

local function update(dt: number)
	local r = runner
	local state, root = FlightController.state, FlightController.root
	if not (r and state and root) then
		return
	end
	local ctx: Context = {
		state = state,
		root = root,
		afterburner = InputController.afterburner,
		kills = kills,
		dt = dt,
	}
	local finished = r:update(ctx)
	render()
	if finished then
		local id = r.lesson.id
		stepLabel.Text = "Lesson complete!"
		hintLabel.Text = "Open the menu (respawn) to pick the next lesson."
		doneUntil = os.clock() + 6
		stop()
		gui.Enabled = true
		task.delay(6, function()
			if not runner then
				gui.Enabled = false
			end
		end)
		TutorialController.Finished:Fire(id)
	end
end

function TutorialController:Start()
	build()
	FlightController.JetChanged:Connect(function(jet)
		if jet then
			myJetId = jet:GetAttribute("JetId") :: number?
			if pendingLesson then
				self:_start()
			end
		else
			myJetId = nil
			stop()
		end
	end)
	Net.Client.on("JetDestroyed", function(jetId: number, killerUserId: number)
		if killerUserId == Players.LocalPlayer.UserId and jetId ~= myJetId then
			kills += 1
		end
	end)
	ReplicatedStorage:GetAttributeChangedSignal("GameMode"):Connect(function()
		if ReplicatedStorage:GetAttribute("GameMode") ~= "FreeFlight" then
			self:Cancel()
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return TutorialController
