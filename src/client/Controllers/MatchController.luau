--!strict
-- Match UI (DEVELOPMENT.md §17.5, MCH-04): a banner with the mode, state and time, the scoreboard (hold
-- Tab / gamepad Start). Reads MatchState from the server. The results screen is part of the menus
-- (MenuController / UI Results), which also show your rewards.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)

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

local function fillRows(container: Frame, ranking: { any }, limit: number)
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 20)
	header.LayoutOrder = 0
	header.Parent = container
	local columns =
		{ { "PILOT", 0, 0.52 }, { "K", 0.52, 0.12 }, { "A", 0.64, 0.12 }, { "D", 0.76, 0.12 }, { "SCORE", 0.88, 0.12 } }
	for _, c in columns do
		local l = label(header, c[1] :: string, 12, DIM)
		l.Position = UDim2.fromScale(c[2] :: number, 0)
		l.Size = UDim2.fromScale(c[3] :: number, 1)
		l.TextXAlignment = if c[1] == "PILOT" then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
	end
	for i, score in ranking do
		if i > limit then
			break
		end
		local row = Instance.new("Frame")
		row.BackgroundColor3 = Color3.new(1, 1, 1)
		row.BackgroundTransparency = if i % 2 == 0 then 0.94 else 1
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, 22)
		row.LayoutOrder = i
		row.Parent = container
		local mine = score.userId == localPlayer.UserId
		local values = {
			`{i}. {score.name}`,
			tostring(score.kills),
			tostring(score.assists),
			tostring(score.deaths),
			tostring(score.score),
		}
		for c, column in columns do
			local l = label(row, values[c], 15, if mine then ME elseif score.isAI then DIM else WHITE)
			l.Font = Enum.Font.Gotham
			l.Position = UDim2.fromScale(column[2] :: number, 0)
			l.Size = UDim2.fromScale(column[3] :: number, 1)
			l.TextXAlignment = if c == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
		end
	end
end

local function formatTime(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function render(s: any)
	local menu = localPlayer.PlayerGui:FindFirstChild("AfterburnerMenu")
	banner.Visible = not (menu and (menu :: ScreenGui).Enabled)
	if s.mode == "FreeFlight" then
		banner.Text = "FREE FLIGHT"
	elseif s.state == "Waiting" then
		banner.Text = `{string.upper(s.modeName)}  ·  WAITING FOR PILOTS`
	elseif s.state == "Countdown" then
		banner.Text = `{string.upper(s.modeName)}  ·  STARTS IN {s.timeLeft}`
	elseif s.state == "InProgress" then
		local leader = s.ranking[1]
		local lead = if leader then `  ·  LEAD {leader.name} {leader.kills}/{s.scoreLimit}` else ""
		banner.Text = `{string.upper(s.modeName)}  ·  {formatTime(s.timeLeft)}{lead}`
	else
		banner.Text = `{string.upper(s.modeName)}  ·  MATCH OVER`
	end

	if board.Visible then
		fillRows(boardRows, s.ranking, 16)
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

	board = panel("Scoreboard", UDim2.fromOffset(520, 440))
	local boardTitle = label(board, "SCOREBOARD", 20, ORANGE)
	boardTitle.Position = UDim2.fromOffset(0, 10)
	boardTitle.Size = UDim2.new(1, 0, 0, 24)
	boardRows = rowsFrame(board, 44)

	gui.Parent = localPlayer:WaitForChild("PlayerGui")

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
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed and input.KeyCode ~= Enum.KeyCode.Tab then
			return
		end
		if input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.ButtonStart then
			setBoard(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Tab or input.KeyCode == Enum.KeyCode.ButtonStart then
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
	if s.mode == "FreeFlight" then
		return true, ""
	end
	if s.state == "Waiting" then
		return false, "Waiting for the match to start"
	elseif s.state == "Countdown" then
		return false, `Match starts in {s.timeLeft}s`
	elseif s.state == "Results" then
		return false, "Match over. Next match soon."
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
