--!strict
-- Toasts (LIV-01/02): a card under the top of the screen when a challenge completes or an achievement is
-- earned (ChallengeNotice), in the menu's navy and orange, one at a time for SHOW seconds, in flight or in
-- the menu. A chime plays with each (UIConfirm, or LevelUp for an achievement). Admin announcements (OPS-04)
-- use the same card, taller so two lines fit, for as long as the admin asked.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local UI = script.Parent.Parent:WaitForChild("UI")
local Sounds = require(UI:WaitForChild("Sounds"))
local Theme = require(UI:WaitForChild("Theme"))

local SHOW = 4.5
local WIDTH, HEIGHT = 440, 74

local ToastController = {
	Priority = 93,
}

local gui: ScreenGui
local card: Frame
local kindLabel: TextLabel
local textLabel: TextLabel
local stroke: UIStroke
local stripe: Frame
local rewardLabel: TextLabel
local queue: { any } = {}
local showing = false

local function label(parent: Instance, size: number, font: Enum.Font, colour: Color3, y: number, h: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, -28, 0, h)
	l.Position = UDim2.fromOffset(14, y)
	l.Font = font
	l.TextSize = size
	l.TextColor3 = colour
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function showNext()
	if showing or #queue == 0 then
		return
	end
	showing = true
	local notice = table.remove(queue, 1)
	local achievement = notice.kind == "Achievement"
	local tall = notice.kind == "Announcement" -- two lines of text, no reward line
	card.Size = UDim2.fromOffset(WIDTH, if tall then HEIGHT + 16 else HEIGHT)
	textLabel.Size = UDim2.new(1, -28, 0, if tall then 44 else 22)
	textLabel.TextWrapped = tall
	textLabel.TextTruncate = if tall then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd
	rewardLabel.Visible = not tall
	kindLabel.Text = if notice.heading
		then notice.heading
		elseif achievement then "ACHIEVEMENT UNLOCKED"
		else `{string.upper(notice.kind)} COMPLETE`
	textLabel.Text = notice.text
	local rewards = {}
	if (notice.credits or 0) > 0 then
		table.insert(rewards, `+{formatNumber(notice.credits)} Cr`)
	end
	if (notice.xp or 0) > 0 then
		table.insert(rewards, `+{formatNumber(notice.xp)} XP`)
	end
	rewardLabel.Text = if achievement then notice.detail or "" else table.concat(rewards, "  ·  ")
	rewardLabel.TextColor3 = if achievement then Theme.Dim else Theme.Good
	-- An achievement wears its rarity's colour
	local colour = notice.rarity and Theme.Rarity[notice.rarity] or Theme.Accent
	stroke.Color = colour
	stripe.BackgroundColor3 = colour
	kindLabel.TextColor3 = colour
	Sounds.play(if achievement then "LevelUp" else "UIConfirm")

	card.Position = UDim2.new(0.5, 0, 0, -HEIGHT)
	card.Visible = true
	TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 64),
	}):Play()
	task.delay(notice.seconds or SHOW, function()
		local out = TweenService:Create(card, TweenInfo.new(0.25), { Position = UDim2.new(0.5, 0, 0, -HEIGHT) })
		out:Play()
		out.Completed:Wait()
		card.Visible = false
		showing = false
		showNext()
	end)
end

function ToastController:Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "AfterburnerToasts"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30 -- over the menu

	card = Instance.new("Frame")
	card.Name = "Toast"
	card.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.BackgroundColor3 = Theme.Panel
	card.BackgroundTransparency = 0.05
	card.Visible = false
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.Radius)
	corner.Parent = card
	stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Accent
	stroke.Thickness = 1.5
	stroke.Parent = card
	-- An orange stripe down the left edge
	stripe = Instance.new("Frame")
	stripe.Size = UDim2.new(0, 4, 1, -16)
	stripe.Position = UDim2.fromOffset(0, 8)
	stripe.BackgroundColor3 = Theme.Accent
	stripe.BorderSizePixel = 0
	stripe.Parent = card

	kindLabel = label(card, 11, Theme.FontBold, Theme.Accent, 9, 14)
	textLabel = label(card, 17, Theme.FontBold, Theme.Text, 25, 22)
	rewardLabel = label(card, 13, Theme.FontBold, Theme.Good, 48, 18)
end

function ToastController:Start()
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	Net.Client.on("ChallengeNotice", function(notice: any)
		table.insert(queue, notice)
		showNext()
	end)
	Net.Client.on("Announcement", function(message: any)
		table.insert(queue, {
			kind = "Announcement",
			heading = "ANNOUNCEMENT",
			text = tostring(message.text),
			seconds = math.clamp(tonumber(message.seconds) or 10, 5, 60),
		})
		showNext()
	end)
end

return ToastController
