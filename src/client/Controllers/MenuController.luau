--!strict
-- The menus (DEVELOPMENT.md §24, UI-01–04 / UI-06), drawn with React (UI/App). Replaces the Phase 1
-- spawn menu. Shown whenever you aren't flying (after the death camera); the results screen while a
-- match's results are up. Owns the menu state and turns screen actions into intents for the server.
-- Keys while in the menu: 1–3 fly that lineup slot, R flies the last jet again. (The Ground Roamer, §36, is
-- off: Config/GroundRoamer.Enabled; the menu still hides if one is out.)
-- In a lobby (MMK-03) PLAY joins the matchmaking queue for the mode picked over it (it becomes CANCEL while
-- searching); on a match server you launch in the selected jet as the match starts (you already chose to
-- play), and PLAY flies again after that; on a training server PLAY flies.

local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React")) :: any
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local LiveConfig = require(Shared.LiveConfig)
local Passes = require(Shared.Config.Passes)
local Products = require(Shared.Config.Products)
local ServerRole = require(Shared.ServerRole)
local Streak = require(Shared.Streak)
local Net = require(Shared.Net)

local BindingsController = require(script.Parent.BindingsController)
local CameraController = require(script.Parent.CameraController)
local DriveController = require(script.Parent.DriveController)
local FlightController = require(script.Parent.FlightController)
local InputController = require(script.Parent.InputController)
local MatchController = require(script.Parent.MatchController)
local PlayerDataController = require(script.Parent.PlayerDataController)
local SettingsController = require(script.Parent.SettingsController)
local TutorialController = require(script.Parent.TutorialController)

local UI = script.Parent.Parent:WaitForChild("UI")
local App = require(UI:WaitForChild("App"))
local DailyReward = require(UI:WaitForChild("DailyReward"))
local ReportDialog = require(UI:WaitForChild("ReportDialog"))
local WelcomeDialog = require(UI:WaitForChild("WelcomeDialog"))
local LoadingScreen = require(UI:WaitForChild("LoadingScreen"))
local MenuBackdrop = require(UI:WaitForChild("MenuBackdrop"))
local Sounds = require(UI:WaitForChild("Sounds"))

local MODE_NAMES = {
	Any = "",
	Dogfight = " Dogfight",
	TeamDeathmatch = " Team Deathmatch",
	AirSuperiority = " Air Superiority",
	GunsOnly = " Guns Only",
}

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
local backdrop: ScreenGui -- the prerendered Strait behind the menus (not over the results: the match is there)
local modalGui: ScreenGui -- the welcome, daily reward and report windows, above the menu (TUT-04, LIV-03, CMP-03)
local modalRoot: any
local daily = { dismissed = false, pending = false, result = nil :: any }
local welcomeDone = false -- the welcome window was answered this visit
-- The report window while it's open: { target, reason, pending, message, sent }
local report: any = nil
local state = {
	screen = "Hangar",
	detailId = nil :: string?,
	backTo = "Hangar",
	selected = nil :: string?,
	status = "",
	lastAirframe = nil :: string?,
	-- The matchmaking queue (lobby only), from QueueState
	queue = { state = "Idle", mode = "Any", startedAt = 0, message = nil :: string? },
	teleportScreen = false,
	autoLaunch = false, -- a match server: launch in the selected jet when the match starts
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

-- Keep a loading screen up through a teleport (set once per trip).
local function showTeleportScreen(text: string)
	if state.teleportScreen then
		return
	end
	state.teleportScreen = true
	pcall(function()
		TeleportService:SetTeleportGui(LoadingScreen.build(text))
	end)
end

-- PLAY: in a lobby, join or leave the queue; elsewhere, fly.
local function play(airframeId: string?)
	if not ServerRole.isLobby() then
		spawn(airframeId)
		return
	end
	local queue = state.queue
	if queue.state == "Searching" then
		Net.Client.fire("QueueLeave")
	elseif queue.state == "Idle" then
		queue.message = nil
		-- the jet you click PLAY with sets your BR in the queue (Queue, MMK-03)
		Net.Client.fire("QueueJoin", SettingsController:Get("QueueMode") or "Any", airframeId or state.selected)
	end
end

-- What the status line under PLAY says in a lobby.
local function queueStatus(): string?
	local queue = state.queue
	if queue.state == "Searching" then
		local waited = math.floor(os.clock() - queue.startedAt)
		local line =
			`Finding a{MODE_NAMES[queue.mode] or ""} match…  {waited // 60}:{string.format("%02d", waited % 60)}`
		return if queue.message then `{queue.message}  {line}` else line
	elseif queue.state == "Found" then
		return "Match found! Joining…"
	end
	return queue.message
end

-- A spend that went through gets the confirm chime (AUD-05).
local function confirmed(ok: boolean, err: string?): (boolean, string?)
	if ok then
		Sounds.play("UIConfirm")
	end
	return ok, err
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
		-- The jet picked last time (maybe on another server), if it's still in the lineup
		local saved = SettingsController:Get("SelectedJet")
		state.selected = if saved and table.find(data.Lineup, saved) then saved else data.Lineup[1]
	end
end

-- Pilots you could report: everyone else on this server, and the human pilots from the last match's
-- scoreboard (who may have left already).
local function reportTargets(): { any }
	local me = Players.LocalPlayer.UserId
	local list, added = {}, {}
	local function add(userId: number?, name: string)
		if userId and userId > 0 and userId ~= me and not added[userId] then
			added[userId] = true
			table.insert(list, { userId = userId, name = name })
		end
	end
	for _, player in Players:GetPlayers() do
		local callsign = player:GetAttribute("Callsign")
		add(
			player.UserId,
			if type(callsign) == "string" and callsign ~= "" then `{callsign} (@{player.Name})` else player.Name
		)
	end
	local match = MatchController.state
	for _, score in (match and match.ranking) or {} do
		if not score.isAI then
			add(score.userId, score.name)
		end
	end
	return list
end

local function renderReport()
	modalGui.Enabled = true
	modalRoot:render(React.createElement(ReportDialog, {
		Targets = reportTargets(),
		Target = report.target,
		Reason = report.reason,
		Pending = report.pending,
		Message = report.message,
		Sent = report.sent,
		OnTarget = function(userId: number)
			report.target = userId
			report.message = nil
			render()
		end,
		OnReason = function(id: string)
			report.reason = id
			report.message = nil
			render()
		end,
		OnSend = function()
			local sending = report
			sending.pending = true
			render()
			task.spawn(function()
				local ok, result, message = pcall(Net.Client.invoke, "ReportPlayer", sending.target, sending.reason)
				sending.pending = false
				if ok and result == true then
					sending.sent = true
					sending.message = message
					Sounds.play("UIConfirm")
				elseif ok and result == false then
					sending.message = message
				else
					sending.message = "Too many reports just now. Try again in a moment."
				end
				render()
			end)
		end,
		OnClose = function()
			report = nil
			render()
		end,
	}))
end

-- A brand-new pilot in the lobby: the welcome window, recommending training (TUT-04). Pilots who have
-- played or done a lesson are marked onboarded by the server.
local function needsWelcome(data: any): boolean
	return not welcomeDone
		and ServerRole.isLobby()
		and data ~= nil
		and not data.Flags.Onboarded
		and data.Stats.Matches == 0
		and next(data.Lessons) == nil
end

local function renderWelcome()
	modalRoot:render(React.createElement(WelcomeDialog, {
		OnTraining = function()
			welcomeDone = true
			render()
			local text = "Heading to a training server…"
			setStatus(text)
			showTeleportScreen(text)
			Net.Client.fire("Travel", "Training")
		end,
		OnClose = function()
			welcomeDone = true
			Net.Client.fire("SkipOnboarding")
			render()
		end,
	}))
end

-- The daily login reward window: once a day, while the menu is up (not over the results screen). The report
-- window takes its place while open, and the welcome window comes first.
local function renderDaily(resultsUp: boolean)
	if report and MenuController.visible then
		renderReport()
		return
	end
	local data = PlayerDataController.data
	if MenuController.visible and not resultsUp and needsWelcome(data) then
		modalGui.Enabled = true
		renderWelcome()
		return
	end
	local today = os.time() // 86400
	local show = MenuController.visible
		and not resultsUp
		and not daily.dismissed
		and data ~= nil
		and data.Streak ~= nil
		and ServerRole.get() ~= "Pending"
		and (daily.result ~= nil or Streak.canClaim(data.Streak, today))
	modalGui.Enabled = show
	if not show then
		modalRoot:render(nil)
		return
	end
	modalRoot:render(React.createElement(DailyReward, {
		Streak = data.Streak,
		Today = today,
		Result = daily.result,
		Pending = daily.pending,
		OnClaim = function()
			daily.pending = true
			render()
			task.spawn(function()
				local ok, result = pcall(Net.Client.invoke, "ClaimDailyReward")
				daily.pending = false
				if ok and result then
					daily.result = result
					Sounds.play("UIConfirm")
				else
					daily.dismissed = true -- already claimed (another server), or try again next time
				end
				render()
			end)
		end,
		OnClose = function()
			daily.dismissed = true
			daily.result = nil
			render()
		end,
	}))
end

render = function()
	if not root then
		return
	end
	backdrop.Enabled = MenuController.visible and state.screen ~= "Results"
	fixSelection()
	local match = MatchController.state
	local resultsUp = match ~= nil and match.state == "Results"
	local allowed, reason = MatchController:SpawnStatus()
	local status = state.status
	local lobby = ServerRole.isLobby()
	-- A match server: straight into the air as the match starts, in the jet picked
	-- (held while the report window is open, then launches once it closes)
	if state.autoLaunch and not report and match and ServerRole.isMatch() and not FlightController.jet then
		local airframe = state.selected and AircraftData.get(state.selected) :: any
		if match.state == "InProgress" and allowed and airframe then
			state.autoLaunch = false
			spawn(state.selected)
			return
		elseif airframe and (match.state == "Countdown" or match.state == "Waiting") and status == "" then
			status = if match.state == "Countdown"
				then `Launching in the {airframe.DisplayName} in {match.timeLeft}s`
				else `{reason}. You'll launch in the {airframe.DisplayName}.`
		end
	end
	local queue = state.queue
	if lobby then
		allowed = PlayerDataController.data ~= nil and queue.state ~= "Found"
		status = queueStatus() or (if status == "" then "Ready" else status)
	elseif status == "" then
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
			SettingsController:Set("SelectedJet", id)
			render()
		end,
		Status = status,
		CanPlay = allowed,
		OnPlay = play,
		PlayText = if not lobby
			then nil
			elseif queue.state == "Searching" then "CANCEL"
			elseif queue.state == "Found" then "JOINING…"
			else "PLAY",
		QueueMode = if lobby then SettingsController:Get("QueueMode") or "Any" else nil,
		OnQueueMode = function(mode: string)
			SettingsController:Set("QueueMode", mode)
			if state.queue.state == "Searching" then
				Net.Client.fire("QueueJoin", mode, state.selected) -- keeps your place, changes the mode
			end
		end,
		OnResearch = function(id)
			return confirmed(PlayerDataController:Research(id))
		end,
		OnBuy = function(id)
			return confirmed(PlayerDataController:Buy(id))
		end,
		OnBuySkin = function(id, skinId, currency)
			return confirmed(PlayerDataController:BuySkin(id, skinId, currency))
		end,
		OnSetSkin = function(id, skinId)
			return PlayerDataController:SetSkin(id, skinId)
		end,
		OnSetModuleFitted = function(id, moduleId, fitted)
			return PlayerDataController:SetModuleFitted(id, moduleId, fitted)
		end,
		OnBuyModule = function(id, moduleId)
			return confirmed(PlayerDataController:BuyModule(id, moduleId))
		end,
		OnLineup = function(ids)
			return PlayerDataController:SetLineup(ids)
		end,
		Role = ServerRole.get(),
		OnReport = function(userId: number?)
			report = { target = userId }
			render()
		end,
		OnTravel = function(target: string)
			local text = if target == "Training"
				then "Heading to a training server…"
				else "Heading back to the lobby…"
			setStatus(text)
			showTeleportScreen(text)
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
		FirstSession = TutorialController:FirstSession(),
		Event = LiveConfig.get("event"),
		Motd = LiveConfig.get("motd"),
		OnFinishOnboarding = function()
			Net.Client.fire("FinishOnboarding")
		end,
		OnSetTitle = function(titleId: string): (boolean, string?)
			local ok, result, message = pcall(Net.Client.invoke, "SetTitle", titleId)
			if not ok then
				return false, "Try again in a moment."
			end
			return result == true, message
		end,
		-- The free spin: the server rolls and grants the prize (Shared/Spin)
		OnSpin = function(): (any, string?)
			local ok, prize, why = pcall(Net.Client.invoke, "SpinWheel")
			if not ok then
				return nil, "No answer from the server. Try again in a moment."
			end
			return prize, why
		end,
		-- Robux purchases (SHP): Roblox's purchase window, once the product or pass exists on the dashboard
		OnBuyProduct = function(key: string): (boolean, string?)
			local id = Products.idFor(key)
			if not id then
				return false, "Coming soon"
			end
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, id)
			return true, nil
		end,
		OnBuyCosmetic = function(id: string): (boolean, string?)
			return PlayerDataController:BuyCosmetic(id)
		end,
		OnEquipCosmetic = function(kind: string, id: string): (boolean, string?)
			return PlayerDataController:EquipCosmetic(kind, id)
		end,
		OnBuyPass = function(key: string): (boolean, string?)
			local id = Passes.idFor(key)
			if not id then
				return false, "Coming soon"
			end
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, id)
			return true, nil
		end,
		OnChooseTierUnlock = function(picks: { string }): (boolean, string?)
			local ok, result, message = pcall(Net.Client.invoke, "ChooseTierUnlock", picks)
			if not ok then
				return false, "Try again in a moment."
			end
			return result == true, message
		end,
		OnSetCallsign = function(text: string): (boolean, string?)
			local ok, result, message = pcall(Net.Client.invoke, "SetCallsign", text)
			if not ok then
				return false, "Try again in a moment."
			end
			return result == true, message
		end,
		OnReroll = function(index: number): (boolean, string?)
			local ok, result, message = pcall(Net.Client.invoke, "RerollChallenge", index)
			if not ok then
				return false, "Couldn't reroll just now. Try again in a moment."
			end
			return result == true, message
		end,
		OnCapture = function(device: string, callback: (string?) -> ()): boolean
			return BindingsController:Capture(device, callback)
		end,
		Lessons = lessons(),
		OnLesson = function(lessonId)
			local ok, why = TutorialController:Begin(lessonId, state.selected or "F5E")
			setStatus(if ok then "Starting training…" else why)
		end,
	}))
	renderDaily(resultsUp)
end

-- Gamepad (UI-09): keep a button selected while the menu is up: PLAY (or FLY), else the first one. Run after
-- renders and device changes, since a screen change can remove the selected button.
local TABS = { "Hangar", "TechTree", "Career", "Shop", "Settings" }

local function gamepadSelect()
	if not (MenuController.visible and InputController.device == "Gamepad") then
		return
	end
	local selected = GuiService.SelectedObject
	-- The daily reward or report window first, while it's up
	if modalGui.Enabled then
		if selected and selected:IsDescendantOf(modalGui) and selected.Visible then
			return
		end
		local action = modalGui:FindFirstChild("Action", true)
		if action and action:IsA("GuiButton") then
			GuiService.SelectedObject = action
		else
			GuiService:Select(modalGui)
		end
		return
	end
	if selected and selected:IsDescendantOf(gui) and selected.Visible then
		return
	end
	local body = gui:FindFirstChild("Body", true)
	local screen = body and body:FindFirstChild("Screen")
	local main = screen and (screen:FindFirstChild("Play") or screen:FindFirstChild("Fly"))
	if main and main:IsA("GuiButton") then
		GuiService.SelectedObject = main
	else
		GuiService:Select(gui)
	end
end

local function setVisible(visible: boolean)
	if MenuController.visible == visible then
		return
	end
	MenuController.visible = visible
	gui.Enabled = visible
	backdrop.Enabled = visible and state.screen ~= "Results"
	if not visible then
		modalGui.Enabled = false
		report = nil
	end
	if visible then
		if state.screen == "Results" then
			state.screen = "Hangar"
		end
		render()
		task.delay(0.1, gamepadSelect) -- gamepad: start on PLAY
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
	backdrop = MenuBackdrop.build(19)
	backdrop.Parent = gui.Parent
	modalGui = Instance.new("ScreenGui")
	modalGui.Name = "AfterburnerDailyReward"
	modalGui.IgnoreGuiInset = true
	modalGui.ResetOnSpawn = false
	modalGui.DisplayOrder = 25 -- over the menu, under toasts
	modalGui.Enabled = false
	modalGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	modalRoot = ReactRoblox.createRoot(modalGui)
	-- The gamepad selection outline, in the menu's orange (UI-09)
	local outline = Instance.new("Frame")
	outline.Name = "AfterburnerSelection"
	outline.BackgroundTransparency = 1
	outline.Size = UDim2.new(1, 8, 1, 8)
	outline.Position = UDim2.fromOffset(-4, -4)
	local outlineCorner = Instance.new("UICorner")
	outlineCorner.CornerRadius = UDim.new(0, 10)
	outlineCorner.Parent = outline
	local outlineStroke = Instance.new("UIStroke")
	outlineStroke.Color = Color3.fromRGB(255, 138, 61)
	outlineStroke.Thickness = 3
	outlineStroke.Parent = outline
	Players.LocalPlayer.PlayerGui.SelectionImageObject = outline

	PlayerDataController.Changed:Connect(render)
	PlayerDataController.Rewards:Connect(function(payload: any)
		if payload and (payload.LevelsGained or 0) > 0 then
			task.delay(1.5, Sounds.play, "LevelUp") -- as the results screen's level bar fills
		end
		render()
	end)
	MatchController.Changed:Connect(function()
		local match = MatchController.state
		if match and match.state == "Closing" then
			showTeleportScreen("Heading back to the lobby…")
		end
		render()
	end)
	Net.Client.on("SpawnRefused", function(reason: string)
		state.teleportScreen = false -- a failed trip; the next one sets its own
		setStatus(reason)
	end)
	Net.Client.on("QueueState", function(payload: any)
		local queue = state.queue
		queue.state = payload.state
		queue.mode = payload.mode or queue.mode
		queue.message = payload.message
		queue.startedAt = os.clock() - (payload.waited or 0)
		if payload.state == "Found" then
			Sounds.play("MatchFound")
			showTeleportScreen("Joining your match…")
		else
			state.teleportScreen = false
		end
		render()
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
			if jetId ~= myJetId then
				return
			end
			-- A despawn (back to the hangar, a new setup, travel) isn't a loss unless someone forced it
			if cause == "Despawn" and killerUserId == 0 and (killerJetId or 0) == 0 then
				state.status = ""
			else
				state.status = `{deathMessage(killerUserId, cause, killerJetId)}. Press PLAY or R to fly again.`
			end
		end
	)

	-- Gamepad in the menu (UI-09): LB / RB switch tabs, B goes back
	UserInputService.InputBegan:Connect(function(input)
		if not self.visible or FlightController.jet or BindingsController.capturing then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Gamepad1 or state.screen == "Results" then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.ButtonL1 or key == Enum.KeyCode.ButtonR1 then
			local index = table.find(TABS, state.screen) or 1
			local step = if key == Enum.KeyCode.ButtonR1 then 1 else -1
			navigate(TABS[(index - 1 + step) % #TABS + 1])
			task.delay(0.1, function()
				GuiService.SelectedObject = nil
				gamepadSelect()
			end)
		elseif key == Enum.KeyCode.ButtonB and state.screen ~= "Hangar" then
			navigate(if state.screen == "Detail" then state.backTo or "Hangar" else "Hangar")
			task.delay(0.1, gamepadSelect)
		end
	end)
	InputController.DeviceChanged:Connect(function()
		task.defer(gamepadSelect)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or FlightController.jet or not self.visible or BindingsController.capturing then
			return
		end
		local data = PlayerDataController.data
		local index = table.find({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }, input.KeyCode)
		if index and data and data.Lineup[index] then
			state.selected = data.Lineup[index]
			SettingsController:Set("SelectedJet", state.selected)
			spawn(state.selected)
		elseif BindingsController:Matches(input, "FlyAgain") and state.lastAirframe then
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
		state.autoLaunch = ServerRole.isMatch()
		state.status = ""
		state.queue.state = "Idle"
		state.queue.message = nil
		state.teleportScreen = false
		render()
	end)
	ReplicatedStorage:GetAttributeChangedSignal("GameMode"):Connect(render)
	-- Live config changes (an event, the message of the day, a jet's BR) show at once
	ReplicatedStorage.AttributeChanged:Connect(function(name)
		if name:sub(1, 3) == "LC_" then
			render()
		end
	end)

	state.autoLaunch = ServerRole.isMatch()
	setVisible(FlightController.jet == nil and DriveController.vehicle == nil)
	render()
	-- The match status line counts down; refresh it twice a second while the menu is up
	task.spawn(function()
		while true do
			task.wait(0.5)
			if self.visible then
				render()
				task.defer(gamepadSelect)
			end
		end
	end)
end

return MenuController
