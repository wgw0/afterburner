--!strict
-- The confirm window: asked before anything that spends Credits, RP or Wings, or removes, leaves or resets
-- something. `Confirm.yes({...})` shows it and waits for the answer, so a handler reads
--   if not Confirm.yes({ Title = "BUY F-4E PHANTOM II?", Body = "...", Action = "BUY · 12,000 Cr" }) then return end
-- props: Title, Body, Action (the confirm button's text), Danger (a red confirm button for losing something).
-- In its own ScreenGui above the menu and its other windows; one at a time (a second ask while one is open
-- answers no).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local ReactRoblox = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("ReactRoblox")) :: any

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement

export type Options = { Title: string, Body: string?, Action: string?, Danger: boolean? }

local Confirm = {}

local open = false

local WIDTH, PAD = 480, 22

-- Wrapped text doesn't grow a box that sizes itself, so the heights are measured
local function height(text: string?, size: number, font: Enum.Font): number
	if not text or text == "" then
		return 0
	end
	return TextService:GetTextSize(text, size, font, Vector2.new(WIDTH - 2 * PAD, 2000)).Y
end

local function Dialog(props: { Options: Options, OnAnswer: (boolean) -> () })
	local o = props.Options
	local titleH = height(o.Title, 22, Theme.FontHeavy)
	local bodyH = height(o.Body, 16, Theme.Font)
	local total = PAD + titleH + (if bodyH > 0 then 14 + bodyH else 0) + 14 + 48 + PAD
	return e("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
	}, {
		Panel = e(C.Panel, {
			Size = UDim2.fromOffset(WIDTH, total),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Padding = PAD,
			StrokeColor = if o.Danger then Theme.Bad else Theme.Accent,
			StrokeThickness = 2,
		}, {
			Layout = C.List({ Gap = 14 }),
			Title = e(C.Label, {
				Text = o.Title,
				Size = UDim2.new(1, 0, 0, titleH),
				Wrap = true,
				TextSize = 22,
				Heavy = true,
				Color = if o.Danger then Theme.Bad else Theme.Accent,
				LayoutOrder = 1,
			}),
			Body = if o.Body
				then e(C.Label, {
					Text = o.Body,
					Size = UDim2.new(1, 0, 0, bodyH),
					Wrap = true,
					TextSize = 16,
					LayoutOrder = 2,
				})
				else nil,
			Buttons = e("Frame", {
				Size = UDim2.new(1, 0, 0, 48),
				BackgroundTransparency = 1,
				LayoutOrder = 3,
			}, {
				Cancel = e(C.Button, {
					Text = "CANCEL",
					Style = "Ghost",
					Size = UDim2.new(0.4, -6, 1, 0),
					TextSize = 16,
					OnClick = function()
						props.OnAnswer(false)
					end,
				}),
				Yes = e(C.Button, {
					Text = o.Action or "CONFIRM",
					Style = if o.Danger then "Danger" else "Primary",
					Size = UDim2.new(0.6, -6, 1, 0),
					Position = UDim2.fromScale(1, 0),
					AnchorPoint = Vector2.new(1, 0),
					TextSize = 16,
					OnClick = function()
						props.OnAnswer(true)
					end,
				}),
			}),
		}),
	})
end

-- Shows the window and waits; true if the player confirmed.
function Confirm.yes(options: Options): boolean
	if open then
		return false
	end
	open = true
	local folder = Instance.new("Folder")
	local root = ReactRoblox.createRoot(folder)
	local answer: boolean? = nil
	local waiting = coroutine.running()
	local function onAnswer(yes: boolean)
		if answer ~= nil then
			return
		end
		answer = yes
		task.defer(function()
			root:unmount()
			folder:Destroy()
			open = false
			task.spawn(waiting, yes)
		end)
	end
	root:render(ReactRoblox.createPortal({
		AfterburnerConfirm = e("ScreenGui", {
			DisplayOrder = 60,
			IgnoreGuiInset = true,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		}, {
			Dialog = e(Dialog, { Options = options, OnAnswer = onAnswer }),
		}),
	}, Players.LocalPlayer:WaitForChild("PlayerGui")))
	return coroutine.yield()
end

return Confirm
