--!strict
-- Spawn menu: pick a jet and join the match. Shown whenever you have no jet (after the death camera).
-- Follows the match: shows the countdown / respawn timer and only spawns when the server will allow it.
-- Keys: 1 / 2 pick a jet, R respawns the last one. Replaced by the hangar in Phase 5 (UI-02).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Net = require(Shared.Net)

local CameraController = require(script.Parent.CameraController)
local InputController = require(script.Parent.InputController)
local FlightController = require(script.Parent.FlightController)
local MatchController = require(script.Parent.MatchController)
local TutorialController = require(script.Parent.TutorialController)

local ORANGE = Color3.fromRGB(255, 138, 61)
local NAVY = Color3.fromRGB(13, 26, 51)

local SpawnController = {
	Priority = 90,
	lastAirframe = nil :: string?,
}

local gui: ScreenGui
local statusLabel: TextLabel
local matchLabel: TextLabel
local lastMessage = ""
local firstButton: GuiObject? = nil

local function request(airframeId: string)
	SpawnController.lastAirframe = airframeId
	local allowed, reason = MatchController:SpawnStatus()
	if not allowed then
		statusLabel.Text = reason
		return
	end
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
	panel.Size = UDim2.fromOffset(460, 400)
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
	subtitle.Text = "choose your jet"
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
		if i == 1 then
			firstButton = button
		end
	end

	-- Training (TUT-02): Free Flight only for now; reserved training servers come with TUT-04.
	local trainingTop = 100 + #order * 70 + 4
	local trainingTitle = Instance.new("TextLabel")
	trainingTitle.BackgroundTransparency = 1
	trainingTitle.Position = UDim2.fromOffset(30, trainingTop)
	trainingTitle.Size = UDim2.fromOffset(90, 36)
	trainingTitle.Font = Enum.Font.GothamBold
	trainingTitle.Text = "TRAINING"
	trainingTitle.TextColor3 = ORANGE
	trainingTitle.TextSize = 15
	trainingTitle.TextXAlignment = Enum.TextXAlignment.Left
	trainingTitle.Parent = panel
	local names = { Flight = "1 FLIGHT", Energy = "2 ENERGY", Guns = "3 GUNS" }
	for i, lessonId in TutorialController.ORDER do
		local lessonButton = Instance.new("TextButton")
		lessonButton.Position = UDim2.fromOffset(124 + (i - 1) * 104, trainingTop)
		lessonButton.Size = UDim2.fromOffset(96, 36)
		lessonButton.BackgroundColor3 = Color3.fromRGB(40, 70, 60)
		lessonButton.AutoButtonColor = true
		lessonButton.Font = Enum.Font.GothamBold
		lessonButton.TextColor3 = Color3.new(1, 1, 1)
		lessonButton.TextSize = 14
		lessonButton.Text = names[lessonId] or lessonId
		lessonButton.Parent = panel
		local lc = Instance.new("UICorner")
		lc.CornerRadius = UDim.new(0, 8)
		lc.Parent = lessonButton
		lessonButton.Activated:Connect(function()
			local ok, reason = TutorialController:Begin(lessonId, SpawnController.lastAirframe or order[1])
			statusLabel.Text = if ok then "Starting training…" else reason
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

	matchLabel = Instance.new("TextLabel")
	matchLabel.BackgroundTransparency = 1
	matchLabel.Position = UDim2.new(0, 0, 1, -78)
	matchLabel.Size = UDim2.new(1, 0, 0, 24)
	matchLabel.Font = Enum.Font.GothamBold
	matchLabel.TextColor3 = ORANGE
	matchLabel.TextSize = 17
	matchLabel.Text = ""
	matchLabel.Parent = panel
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
	Net.Client.on(
		"JetDestroyed",
		function(jetId: number, killerUserId: number, cause: string, _: any, killerJetId: number?)
			if jetId ~= myJetId then
				return
			end
			-- The killer's name: a player, or the pilot of the killer's jet (AI pilots have no user id).
			local killerPlayer = if killerUserId ~= 0 then Players:GetPlayerByUserId(killerUserId) else nil
			local killer: string? = killerPlayer and killerPlayer.Name
			if not killer and killerJetId and killerJetId ~= 0 then
				for _, jet in workspace:WaitForChild("Jets"):GetChildren() do
					if jet:GetAttribute("JetId") == killerJetId then
						killer = jet:GetAttribute("PilotName") :: string?
					end
				end
			end
			local reason = if cause == "Shot"
				then "You were shot down"
				elseif cause == "Collision" then "Mid-air collision"
				elseif cause == "Crash" then "You crashed"
				elseif cause == "OutOfBounds" then "You left the battle area"
				else "Your jet was lost"
			if killer then
				reason ..= if cause == "Shot" then ` by {killer}` else ` (forced by {killer})`
			end
			lastMessage = reason
			statusLabel.Text = `{reason}. Pick a jet or press R to fly again.`
		end
	)
	gui.Enabled = FlightController.jet == nil

	-- Match status line (countdown, respawn timer) and hide the menu while results are up.
	task.spawn(function()
		while true do
			local allowed, reason = MatchController:SpawnStatus()
			matchLabel.Text = if allowed then "Ready: pick your jet" else reason
			local resultsUp = MatchController.state ~= nil and MatchController.state.state == "Results"
			if FlightController.jet == nil and not CameraController:InDeathCam() then
				gui.Enabled = not resultsUp
			end
			-- Gamepad: put the selection on the first jet so A picks it.
			if gui.Enabled and InputController.device == "Gamepad" and GuiService.SelectedObject == nil then
				GuiService.SelectedObject = firstButton
			elseif not gui.Enabled and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
				GuiService.SelectedObject = nil
			end
			task.wait(0.25)
		end
	end)
	local _ = lastMessage
end

return SpawnController
