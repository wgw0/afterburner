--!strict
-- Match UI (DEVELOPMENT.md §17.5, MCH-04): a banner with the mode, state and time, the scoreboard (hold
-- Tab / gamepad Start). Reads MatchState from the server. The results screen is part of the menus
-- (MenuController / UI Results), which also show your rewards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local TeamConfig = require(Shared.Config.Teams)

local BindingsController = require(script.Parent.BindingsController)
local SettingsController = require(script.Parent.SettingsController)

local NAVY = Color3.fromRGB(10, 18, 34)
local ORANGE = Color3.fromRGB(255, 138, 61)
local WHITE = Color3.new(1, 1, 1)
local DIM = Color3.fromRGB(170, 180, 200)
local ME = Color3.fromRGB(255, 200, 120)

local MatchController = {
	Priority = 85,
	state = nil :: any, -- last MatchState
	Changed = Signal.new(), -- (state)
}

local gui: ScreenGui
local banner: TextLabel
local board: Frame
local boardRows: Frame
local localPlayer = Players.LocalPlayer

local VIP_GOLD = "FFC93C" -- the VIP tag on the scoreboard
local function label(parent: Instance, text: string, size: number, colour: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = colour or WHITE
	l.Text = text
	l.Parent = parent
	return l
end

local function panel(name: string, size: UDim2): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.45)
	f.Size = size
	f.BackgroundColor3 = NAVY
	f.BackgroundTransparency = 0.12
	f.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = ORANGE
	stroke.Thickness = 1.5
	stroke.Parent = f
	f.Parent = gui
	return f
end

local function rowsFrame(parent: Instance, top: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Position = UDim2.fromOffset(16, top)
	f.Size = UDim2.new(1, -32, 1, -top - 40)
	f.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = f
	return f
end

local function teamName(team: string): string
	local info = (TeamConfig :: any)[team]
	return string.upper(if info then info.DisplayName else team)
end

local function teamColour(team: string?): Color3?
	local info = team and (TeamConfig :: any)[team]
	return info and info.Colour
end

-- Team modes: each team's pilots under a header with its kills, in team order.
local function byTeam(ranking: { any }, teams: { string }, teamScores: { [string]: number }): { any }
	local rows = {}
	for _, team in teams do
		table.insert(rows, { header = true, team = team, kills = teamScores[team] or 0 })
		for _, score in ranking do
			if score.team == team then
				table.insert(rows, score)
			end
		end
	end
	return rows
end

local function fillRows(container: Frame, ranking: { any }, limit: number)
	-- Everything from the last fill: rows (Frames) and team headers (TextLabels), not the list layout
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 20)
	header.LayoutOrder = 0
	header.Parent = container
	local columns = {
		{ "PILOT", 0, 0.42 },
		{ "JET", 0.42, 0.22 },
		{ "K", 0.64, 0.08 },
		{ "A", 0.72, 0.08 },
		{ "D", 0.8, 0.08 },
		{ "SCORE", 0.88, 0.12 },
	}
	for _, c in columns do
		local l = label(header, c[1] :: string, 12, DIM)
		l.Position = UDim2.fromScale(c[2] :: number, 0)
		l.Size = UDim2.fromScale(c[3] :: number, 1)
		l.TextXAlignment = if c[1] == "PILOT" or c[1] == "JET"
			then Enum.TextXAlignment.Left
			else Enum.TextXAlignment.Center
	end
	local rank = 0
	for i, score in ranking do
		if i > limit then
			break
		end
		if score.header then
			local head = label(container, `{teamName(score.team)}   {score.kills}`, 15, teamColour(score.team))
			head.Size = UDim2.new(1, 0, 0, 22)
			head.TextXAlignment = Enum.TextXAlignment.Left
			head.LayoutOrder = i
			rank = 0
			continue
		end
		rank += 1
		local row = Instance.new("Frame")
		row.BackgroundColor3 = Color3.new(1, 1, 1)
		row.BackgroundTransparency = if i % 2 == 0 then 0.94 else 1
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 22)
		row.LayoutOrder = i
		row.Parent = container
		local mine = score.userId == localPlayer.UserId
		-- A player's title (Config/LevelRewards) after their name
		local player = if score.userId ~= 0 then Players:GetPlayerByUserId(score.userId) else nil
		local title = player and player:GetAttribute("Title") :: string?
		-- The VIP Pilot pass: a bold gold VIP (names are letters, digits and _ only, so rich text is safe)
		local vip = if player and player:GetAttribute("Pass_VIP") == true
			then `<font color="#{VIP_GOLD}"><b>VIP</b></font> `
			else ""
		-- A custom callsign shows the Roblox username after it
		local username = if player and player.Name ~= score.name
			then ` <font color="#8C96A8">@{player.Name}</font>`
			else ""
		local airframe = score.airframe and AircraftData.get(score.airframe) :: any
		local values = {
			if title and title ~= ""
				then `{rank}. {vip}{score.name}{username} · {title}`
				else `{rank}. {vip}{score.name}{username}`,
			if airframe then airframe.DisplayName else "",
			tostring(score.kills),
			tostring(score.assists),
			tostring(score.deaths),
			tostring(score.score),
		}
		for c, column in columns do
			local colour = if mine then ME elseif c == 1 and score.team then teamColour(score.team) else nil
			local l = label(row, values[c], 15, colour or (if score.isAI then DIM else WHITE))
			l.Font = Enum.Font.Gotham
			l.Position = UDim2.fromScale(column[2] :: number, 0)
			l.Size = UDim2.fromScale(column[3] :: number, 1)
			l.TextXAlignment = if c <= 2 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
			l.TextTruncate = Enum.TextTruncate.AtEnd
			l.RichText = c == 1
		end
	end
end

local function formatTime(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function render(s: any)
	local menu = localPlayer.PlayerGui:FindFirstChild("AfterburnerMenu")
	banner.Visible = not (menu and (menu :: ScreenGui).Enabled)
		and s.state ~= "Lobby"
		and s.state ~= "Pending"
		and s.state ~= "Closing"
	if s.mode == "FreeFlight" then
		banner.Text = "FREE FLIGHT"
	elseif s.state == "Waiting" and s.expected then
		banner.Text = `{string.upper(s.modeName)}  ·  WAITING FOR PILOTS {s.arrived}/{s.expected}  ·  {s.timeLeft}`
	elseif s.state == "Waiting" then
		banner.Text = `{string.upper(s.modeName)}  ·  WAITING FOR PILOTS`
	elseif s.state == "Countdown" then
		banner.Text = `{string.upper(s.modeName)}  ·  STARTS IN {s.timeLeft}`
	elseif s.state == "InProgress" and s.teams and s.tickets and s.zones then
		-- Air Superiority: tickets, then each zone's letter in its owner's colour
		local parts = {}
		for _, team in s.teams do
			table.insert(parts, `{teamName(team)} {s.tickets[team] or 0}`)
		end
		local letters = {}
		for _, zone in s.zones do
			local colour = teamColour(zone.owner) or DIM
			table.insert(
				letters,
				string.format(
					'<font color="#%02X%02X%02X">%s</font>',
					math.round(colour.R * 255),
					math.round(colour.G * 255),
					math.round(colour.B * 255),
					zone.id
				)
			)
		end
		banner.Text =
			`{string.upper(s.modeName)}  ·  {formatTime(s.timeLeft)}  ·  {table.concat(parts, " – ")}  ·  {table.concat(
				letters,
				" "
			)}`
	elseif s.state == "InProgress" and s.teams and s.teamScores then
		-- Team modes: both teams' kills against the limit, and which team you're on
		local parts = {}
		for _, team in s.teams do
			table.insert(parts, `{teamName(team)} {s.teamScores[team] or 0}`)
		end
		local mine = localPlayer:GetAttribute("Team")
		local yours = if type(mine) == "string" and mine ~= "" then `  ·  YOU: {teamName(mine)}` else ""
		banner.Text =
			`{string.upper(s.modeName)}  ·  {formatTime(s.timeLeft)}  ·  {table.concat(parts, " – ")} (TO {s.scoreLimit}){yours}`
	elseif s.state == "InProgress" then
		local leader = s.ranking[1]
		local lead = if leader then `  ·  LEAD {leader.name} {leader.kills}/{s.scoreLimit}` else ""
		banner.Text = `{string.upper(s.modeName)}  ·  {formatTime(s.timeLeft)}{lead}`
	else
		banner.Text = `{string.upper(s.modeName)}  ·  MATCH OVER`
	end

	if board.Visible then
		local rows = if s.teams and s.teamScores then byTeam(s.ranking, s.teams, s.teamScores) else s.ranking
		fillRows(boardRows, rows, 18)
	end
end

function MatchController:Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerMatch"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 25

	banner = label(gui, "", 16, WHITE)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 6)
	banner.Size = UDim2.fromOffset(560, 22)
	banner.TextStrokeTransparency = 0.5
	banner.RichText = true -- zone letters in their owners' colours

	board = panel("Scoreboard", UDim2.fromOffset(680, 440))
	local boardTitle = label(board, "SCOREBOARD", 20, ORANGE)
	boardTitle.Position = UDim2.fromOffset(0, 10)
	boardTitle.Size = UDim2.new(1, 0, 0, 24)
	boardRows = rowsFrame(board, 44)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	-- Menu scale setting (SET-03) applies to the banner and scoreboard too
	local scales = {}
	for _, target in { banner, board } do
		local scale = Instance.new("UIScale")
		scale.Parent = target
		table.insert(scales, scale)
	end
	local function applyScale()
		for _, scale in scales do
			scale.Scale = SettingsController:Get("MenuScale") or 1
		end
	end
	applyScale()
	SettingsController.Changed:Connect(function(key)
		if key == "MenuScale" then
			applyScale()
		end
	end)

	Net.Client.on("MatchState", function(s: any)
		self.state = s
		render(s)
		self.Changed:Fire(s)
	end)

	local function setBoard(open: boolean)
		board.Visible = open and self.state ~= nil and self.state.scored
		if board.Visible then
			render(self.state)
		end
	end
	-- Our scoreboard replaces Roblox's player list, which would otherwise take Tab (and mark it processed).
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	-- Held (Tab / Start by default, INP-05). Roblox can mark Tab processed, so that isn't checked.
	UserInputService.InputBegan:Connect(function(input)
		if BindingsController:Matches(input, "Scoreboard") then
			setBoard(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if BindingsController:Matches(input, "Scoreboard") then
			setBoard(false)
		end
	end)
end

-- Can the local player spawn right now? Returns (allowed, reason).
function MatchController:SpawnStatus(): (boolean, string)
	local s = self.state
	if not s then
		return false, "Connecting…"
	end
	-- Not until the area you'll spawn in has loaded (StreamingService), so nobody starts in the void
	if not localPlayer:GetAttribute("MapReady") then
		return false, "Loading the map…"
	end
	if s.state == "Lobby" then
		return false, "Press PLAY to find a match"
	elseif s.state == "Pending" then
		return false, "Joining…"
	elseif s.state == "Closing" then
		return false, "Heading back to the lobby…"
	end
	if s.mode == "FreeFlight" then
		return true, ""
	end
	if s.state == "Waiting" and s.expected then
		return false, `Waiting for pilots ({s.arrived}/{s.expected})`
	elseif s.state == "Waiting" then
		return false, "Waiting for the match to start"
	elseif s.state == "Countdown" then
		return false, `Match starts in {s.timeLeft}s`
	elseif s.state == "Results" then
		return false, if s.expected then "Match over. Back to the lobby soon." else "Match over. Next match soon."
	end
	local wait = localPlayer:GetAttribute("RespawnIn") :: number?
	local lives = localPlayer:GetAttribute("LivesLeft") :: number?
	if lives == 0 then
		return false, "No lives left this match"
	end
	if wait and wait > 0 then
		return false, `Respawn in {wait}s`
	end
	return true, ""
end

return MatchController
