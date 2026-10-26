--!strict
-- Phase 1 test-flight menu: pick a jet and spawn over the test range. Shown whenever you have no jet.
-- Keys: 1 / 2 pick a jet, R respawns the last one. Replaced by the hangar in Phase 5 (UI-02).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Net = require(Shared.Net)

local CameraController = require(script.Parent.CameraController)
local FlightController = require(script.Parent.FlightController)

local ORANGE = Color3.fromRGB(255, 138, 61)
local NAVY = Color3.fromRGB(13, 26, 51)

local SpawnController = {
	Priority = 90,
	lastAirframe = nil :: string?,
}

local gui: ScreenGui
local statusLabel: TextLabel

local function request(airframeId: string)
	SpawnController.lastAirframe = airframeId
	statusLabel.Text = "Spawning…"
	Net.Client.fire("RequestSpawn", airframeId)
end

local function build(): { string }
	gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerSpawn"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(460, 330)
	panel.BackgroundColor3 = NAVY
	panel.BackgroundTransparency = 0.1
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	local stroke = Instance.new("UIStroke")
	stroke.Color = ORANGE
	stroke.Thickness = 2
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 18)
	title.Size = UDim2.new(1, 0, 0, 44)
	title.Font = Enum.Font.GothamBlack
	title.Text = "AFTERBURNER"
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextSize = 38
	title.Parent = panel

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(0, 62)
	subtitle.Size = UDim2.new(1, 0, 0, 22)
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.Text = "PHASE 1 TEST FLIGHT · choose your jet"
	subtitle.TextColor3 = Color3.fromRGB(255, 210, 168)
	subtitle.TextSize = 16
	subtitle.Parent = panel

	local order = {}
	for id in AircraftData.getAll() do
		table.insert(order, id)
	end
	table.sort(order)

	for i, id in order do
		local airframe = AircraftData.get(id) :: any
		local button = Instance.new("TextButton")
		button.Position = UDim2.fromOffset(30, 100 + (i - 1) * 70)
		button.Size = UDim2.new(1, -60, 0, 58)
		button.BackgroundColor3 = Color3.fromRGB(43, 58, 85)
		button.AutoButtonColor = true
		button.Font = Enum.Font.GothamBold
		button.TextColor3 = Color3.new(1, 1, 1)
		button.TextSize = 22
		button.Text = `[{i}]  {airframe.DisplayName}   ·   BR {airframe.BattleRating}`
		button.Parent = panel
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 8)
		bc.Parent = button
		button.Activated:Connect(function()
			request(id)
		end)
	end

	statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.new(0, 0, 1, -50)
	statusLabel.Size = UDim2.new(1, 0, 0, 36)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextColor3 = Color3.fromRGB(200, 210, 225)
	statusLabel.TextSize = 15
	statusLabel.TextWrapped = true
	statusLabel.Text = "W/S throttle · mouse to aim · Q/E roll · A/D rudder · RMB look · Shift override limits"
	statusLabel.Parent = panel

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return order
end

function SpawnController:Start()
	local order = build()
	local keys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local index = table.find(keys, input.KeyCode)
		if index and order[index] and not FlightController.jet then
			request(order[index])
		elseif input.KeyCode == Enum.KeyCode.R and self.lastAirframe and not FlightController.jet then -- R cycles missiles in flight
			request(self.lastAirframe)
		end
	end)

	local myJetId: number? = nil
	FlightController.JetChanged:Connect(function(jet)
		if jet then
			myJetId = jet:GetAttribute("JetId") :: number?
			gui.Enabled = false
			return
		end
		-- Let the death camera play before the menu comes back.
		task.spawn(function()
			while CameraController:InDeathCam() do
				task.wait(0.1)
			end
			gui.Enabled = FlightController.jet == nil
		end)
	end)
	Net.Client.on("JetDestroyed", function(jetId: number, killerUserId: number, cause: string)
		if jetId ~= myJetId then
			return
		end
		local killer = if killerUserId ~= 0 then Players:GetPlayerByUserId(killerUserId) else nil
		local reason = if cause == "Shot"
			then "You were shot down"
			elseif cause == "Collision" then "Mid-air collision"
			elseif cause == "Crash" then "You crashed"
			else "Your jet was lost"
		if killer then
			reason ..= if cause == "Shot" then ` by {killer.Name}` else ` (forced by {killer.Name})`
		end
		statusLabel.Text = `{reason}. Pick a jet or press R to fly again.`
	end)
	gui.Enabled = FlightController.jet == nil
end

return SpawnController
