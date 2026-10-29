--!strict
-- The menus (DEVELOPMENT.md §24, UI-01–04 / UI-06), drawn with React (UI/App). Replaces the Phase 1
-- spawn menu. Shown whenever you aren't flying (after the death camera); the results screen while a
-- match's results are up. Owns the menu state and turns screen actions into intents for the server.
-- Keys while in the menu: 1–3 fly that lineup slot, R flies the last jet again. DRIVE takes out the Ground
-- Roamer (§36); the menu stays hidden while you drive.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React")) :: any
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local ServerRole = require(Shared.ServerRole)
local Net = require(Shared.Net)

local CameraController = require(script.Parent.CameraController)
local DriveController = require(script.Parent.DriveController)
local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)
local MatchController = require(script.Parent.MatchController)
local PlayerDataController = require(script.Parent.PlayerDataController)
local SettingsController = require(script.Parent.SettingsController)
local TutorialController = require(script.Parent.TutorialController)

local App = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("App"))

local LESSON_NAMES = {
	Flight = "Basic flight",
	Energy = "Energy",
	Guns = "Guns",
	Missiles = "Missiles",
	Defend = "Defend",
	Fight = "First fight",
}

local MenuController = {
	Priority = 90,
	visible = false,
}

local gui: ScreenGui
local root: any
local state = {
	screen = "Hangar",
	detailId = nil :: string?,
	backTo = "Hangar",
	selected = nil :: string?,
	status = "",
	lastAirframe = nil :: string?,
}
local myJetId: number? = nil

local function lessons()
	local list = {}
	for _, id in TutorialController.ORDER do
		table.insert(list, { id = id, name = LESSON_NAMES[id] or id })
	end
	return list
end

local render: () -> ()

local function setStatus(text: string)
	state.status = text
	render()
end

local function spawn(airframeId: string?)
	if not airframeId then
		return
	end
	state.lastAirframe = airframeId
	local allowed, reason = MatchController:SpawnStatus()
	if not allowed then
		setStatus(reason)
		return
	end
	setStatus("Spawning…")
	Net.Client.fire("RequestSpawn", airframeId)
end

local function navigate(screen: string, id: string?)
	if screen == "Detail" then
		state.backTo = if state.screen == "Detail" then state.backTo else state.screen
		state.detailId = id
	end
	state.screen = screen
	render()
end

-- Keep the selected jet valid: something in the lineup (on a training server, any jet will do).
local function fixSelection()
	local data = PlayerDataController.data
	if not data then
		return
	end
	if ServerRole.isTraining() and state.selected and AircraftData.get(state.selected) then
		return
	end
	if not (state.selected and table.find(data.Lineup, state.selected)) then
		state.selected = data.Lineup[1]
	end
end

render = function()
	if not root then
		return
	end
	fixSelection()
	local match = MatchController.state
	local resultsUp = match ~= nil and match.state == "Results"
	local allowed, reason = MatchController:SpawnStatus()
	local status = state.status
	if status == "" then
		status = if allowed then "Ready" else reason
	elseif not allowed and status == "Spawning…" then
		status = reason
	end
	root:render(React.createElement(App, {
		Data = PlayerDataController.data,
		Screen = if resultsUp then "Results" else state.screen,
		DetailId = state.detailId,
		BackTo = state.backTo,
		Navigate = navigate,
		Match = match,
		Rewards = PlayerDataController.lastRewards,
		Selected = state.selected,
		OnSelect = function(id)
			state.selected = id
			render()
		end,
		Status = status,
		CanPlay = allowed,
		OnPlay = spawn,
		OnDrive = function()
			setStatus("Fetching the Ground Roamer…")
			task.spawn(function()
				local ok, why = DriveController:TakeOut(nil)
				setStatus(if ok then "" else why or "Couldn't take it out")
			end)
		end,
		OnResearch = function(id)
			return PlayerDataController:Research(id)
		end,
		OnBuy = function(id)
			return PlayerDataController:Buy(id)
		end,
		OnBuySkin = function(id, skinId)
			return PlayerDataController:BuySkin(id, skinId)
		end,
		OnSetSkin = function(id, skinId)
			return PlayerDataController:SetSkin(id, skinId)
		end,
		OnSetModuleFitted = function(id, moduleId, fitted)
			return PlayerDataController:SetModuleFitted(id, moduleId, fitted)
		end,
		OnBuyModule = function(id, moduleId)
			return PlayerDataController:BuyModule(id, moduleId)
		end,
		OnLineup = function(ids)
			return PlayerDataController:SetLineup(ids)
		end,
		Role = ServerRole.get(),
		OnTravel = function(target: string)
			setStatus(
				if target == "Training" then "Heading to a training server…" else "Heading back to multiplayer…"
			)
			Net.Client.fire("Travel", target)
		end,
		VsAIRunning = ServerRole.isTraining() and ReplicatedStorage:GetAttribute("GameMode") ~= "FreeFlight",
		ModeName = match and match.modeName,
		OnVsAI = function(modeId: string, difficulty: string, count: number)
			setStatus("Starting Vs AI…")
			Net.Client.fire("TrainingSetup", modeId, difficulty, count)
		end,
		OnFreeFlight = function()
			setStatus("")
			Net.Client.fire("TrainingSetup", "FreeFlight", "Normal", 0)
		end,
		Settings = SettingsController.values,
		MenuScale = SettingsController:Get("MenuScale"),
		OnSetting = function(key, value)
			SettingsController:Set(key, value)
		end,
		Lessons = lessons(),
		OnLesson = function(lessonId)
			local ok, why = TutorialController:Begin(lessonId, state.selected or "F5E")
			setStatus(if ok then "Starting training…" else why)
		end,
	}))
end

local function setVisible(visible: boolean)
	if MenuController.visible == visible then
		return
	end
	MenuController.visible = visible
	gui.Enabled = visible
	if visible then
		if state.screen == "Results" then
			state.screen = "Hangar"
		end
		render()
		if InputController.device == "Gamepad" then
			task.defer(function()
				GuiService:Select(gui) -- gamepad: start on the first button
			end)
		end
	elseif GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
end

local function deathMessage(killerUserId: number, cause: string, killerJetId: number?): string
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
	return reason
end

function MenuController:Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerMenu"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	root = ReactRoblox.createRoot(gui)

	PlayerDataController.Changed:Connect(render)
	PlayerDataController.Rewards:Connect(render)
	MatchController.Changed:Connect(render)
	Net.Client.on("SpawnRefused", function(reason: string)
		setStatus(reason)
	end)

	FlightController.JetChanged:Connect(function(jet)
		if jet then
			myJetId = jet:GetAttribute("JetId") :: number?
			state.status = ""
			setVisible(false)
			return
		end
		-- Let the death camera play before the menu comes back
		task.spawn(function()
			while CameraController:InDeathCam() do
				task.wait(0.1)
			end
			setVisible(FlightController.jet == nil)
		end)
	end)
	Net.Client.on(
		"JetDestroyed",
		function(jetId: number, killerUserId: number, cause: string, _: any, killerJetId: number?)
			if jetId == myJetId and cause ~= "Despawn" then -- a despawn (new setup, travel) isn't a loss
				state.status = `{deathMessage(killerUserId, cause, killerJetId)}. Press PLAY or R to fly again.`
			end
		end
	)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or FlightController.jet or not self.visible then
			return
		end
		local data = PlayerDataController.data
		local index = table.find({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }, input.KeyCode)
		if index and data and data.Lineup[index] then
			state.selected = data.Lineup[index]
			spawn(state.selected)
		elseif input.KeyCode == Enum.KeyCode.R and state.lastAirframe then
			spawn(state.lastAirframe)
		end
	end)

	DriveController.VehicleChanged:Connect(function(vehicle)
		if vehicle then
			setVisible(false)
		elseif FlightController.jet == nil and not CameraController:InDeathCam() then
			setVisible(true)
		end
	end)

	SettingsController.Changed:Connect(function()
		render()
	end)
	-- The server's role and mode change the menu (in Studio, Travel switches the role in place)
	ReplicatedStorage:GetAttributeChangedSignal("ServerRole"):Connect(function()
		state.status = ""
		render()
	end)
	ReplicatedStorage:GetAttributeChangedSignal("GameMode"):Connect(render)

	setVisible(FlightController.jet == nil and DriveController.vehicle == nil)
	render()
	-- The match status line counts down; refresh it twice a second while the menu is up
	task.spawn(function()
		while true do
			task.wait(0.5)
			if self.visible then
				render()
			end
		end
	end)
end

return MenuController
