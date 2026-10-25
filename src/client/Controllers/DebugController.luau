--!strict
-- Live flight tuning panel (DEVELOPMENT.md §6.5, FLT-06). Test environment only. Press P.
-- Edit the current jet's coefficients while flying, watch the force breakdown, then Export to print
-- a Luau table to paste into the airframe module.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Environment = require(Shared.Config.Environment)
local FlightModel = require(Shared.FlightModel)
local Units = require(Shared.Units)

local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)

local TUNABLE = {
	"Mass",
	"MaxThrust",
	"AfterburnerMult",
	"WingArea",
	"CD0",
	"InducedK",
	"CLAlpha",
	"CLMax",
	"CriticalAoA",
	"MaxG",
	"MinG",
	"MaxRollRate",
	"MaxPitchRate",
	"MaxYawRate",
	"MaxMach",
}

local DebugController = {
	Priority = 95,
	open = false,
}

local gui: ScreenGui
local readout: TextLabel
local boxes: { [string]: TextBox } = {}

local function refreshBoxes()
	local airframe = FlightController.airframe
	for key, box in boxes do
		box.Text = if airframe then tostring(airframe[key]) else "-"
	end
end

local function export(): string
	local airframe = FlightController.airframe
	if not airframe then
		return "-- no jet"
	end
	local lines = { `-- {airframe.Id} tuned values` }
	for _, key in TUNABLE do
		table.insert(lines, `{key} = {airframe[key]},`)
	end
	return table.concat(lines, "\n")
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerTuning"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.Enabled = false

	local panel = Instance.new("Frame")
	panel.Position = UDim2.new(1, -360, 0, 70)
	panel.Size = UDim2.fromOffset(340, 640)
	panel.BackgroundColor3 = Color3.fromRGB(10, 14, 22)
	panel.BackgroundTransparency = 0.15
	panel.Parent = gui

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 3)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = panel

	local title = Instance.new("TextLabel")
	title.LayoutOrder = 0
	title.Size = UDim2.new(1, 0, 0, 24)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(255, 138, 61)
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "FLIGHT TUNING (P to close)"
	title.Parent = panel

	for i, key in TUNABLE do
		local row = Instance.new("Frame")
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 22)
		row.BackgroundTransparency = 1
		row.Parent = panel
		local name = Instance.new("TextLabel")
		name.Size = UDim2.fromScale(0.55, 1)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.Code
		name.TextColor3 = Color3.fromRGB(200, 210, 225)
		name.TextSize = 14
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Text = key
		name.Parent = row
		local box = Instance.new("TextBox")
		box.Position = UDim2.fromScale(0.55, 0)
		box.Size = UDim2.fromScale(0.45, 1)
		box.BackgroundColor3 = Color3.fromRGB(30, 38, 52)
		box.Font = Enum.Font.Code
		box.TextColor3 = Color3.new(1, 1, 1)
		box.TextSize = 14
		box.ClearTextOnFocus = false
		box.Parent = row
		box.FocusLost:Connect(function()
			local airframe = FlightController.airframe
			local value = tonumber(box.Text)
			if airframe and value and value == value then
				airframe[key] = value
			end
			refreshBoxes()
		end)
		boxes[key] = box
	end

	local exportButton = Instance.new("TextButton")
	exportButton.LayoutOrder = 100
	exportButton.Size = UDim2.new(1, 0, 0, 26)
	exportButton.BackgroundColor3 = Color3.fromRGB(255, 138, 61)
	exportButton.Font = Enum.Font.GothamBold
	exportButton.TextColor3 = Color3.new(0, 0, 0)
	exportButton.TextSize = 14
	exportButton.Text = "EXPORT TO OUTPUT"
	exportButton.Parent = panel
	exportButton.Activated:Connect(function()
		print(export())
	end)

	readout = Instance.new("TextLabel")
	readout.LayoutOrder = 101
	readout.Size = UDim2.new(1, 0, 0, 200)
	readout.BackgroundTransparency = 1
	readout.Font = Enum.Font.Code
	readout.TextColor3 = Color3.fromRGB(93, 255, 168)
	readout.TextSize = 14
	readout.TextXAlignment = Enum.TextXAlignment.Left
	readout.TextYAlignment = Enum.TextYAlignment.Top
	readout.Parent = panel

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

local function update()
	if not DebugController.open then
		return
	end
	local state, airframe, input = FlightController.state, FlightController.airframe, FlightController.input
	if not (state and airframe and input) then
		readout.Text = "No jet"
		return
	end
	local f = FlightModel.computeForces(state, input, airframe)
	local weight = f.mass * 9.81
	local excessPower = (f.thrust + f.drag):Dot(state.velocity.Unit) * state.speed / weight
	local turnRate = math.deg(math.sqrt(math.max(state.gLoad ^ 2 - 1, 0)) * 9.81 / math.max(state.speed, 1))
	readout.Text = table.concat({
		string.format("Speed  %4d kt  M%.2f", math.round(Units.knots(state.speed)), state.mach),
		string.format("Alt    %6d ft", math.round(Units.feet(state.altitude))),
		string.format(
			"AoA    %5.1f°  β %4.1f°  %s",
			math.deg(state.aoa),
			math.deg(state.sideslip),
			if state.stalled then "STALL" else ""
		),
		string.format("G      %5.2f  stress %.2f", state.gLoad, state.gStress),
		string.format("Turn   %5.1f °/s", turnRate),
		string.format("Ps     %+6.1f m/s", excessPower),
		string.format("Lift   %6.1f kN  CL %.2f", f.lift.Magnitude / 1000, f.cl),
		string.format("Drag   %6.1f kN  CD %.3f", f.drag.Magnitude / 1000, f.cd),
		string.format("Thrust %6.1f kN", f.thrust.Magnitude / 1000),
		string.format(
			"Corner %4d kt here",
			math.round(Units.knots(FlightModel.cornerSpeed(airframe, state.altitude, state.fuel)))
		),
	}, "\n")
end

function DebugController:Start()
	if not Environment.isTest() then
		return
	end
	build()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.P then
			return
		end
		self.open = not self.open
		gui.Enabled = self.open
		InputController:SetUIOpen(self.open)
		refreshBoxes()
	end)
	FlightController.JetChanged:Connect(refreshBoxes)
	RunService.RenderStepped:Connect(update)
end

return DebugController
