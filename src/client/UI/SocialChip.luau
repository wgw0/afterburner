--!strict
-- The friends bonus on the hangar (Shared/Social), a small chip under the news banner: lit green with a tick
-- when it's on, dim with how to get it when it isn't. Reads the FriendsBonus attribute SocialService keeps on
-- the player. Not on training servers (nothing is earned there).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config.Social)
local ServerRole = require(Shared.ServerRole)
local Social = require(Shared.Social)

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement

-- Re-renders when one of the player's attributes changes.
local function useAttribute(name: string): any
	local player = Players.LocalPlayer
	local value, setValue = React.useState(player:GetAttribute(name))
	React.useEffect(function()
		setValue(player:GetAttribute(name))
		local connection = player:GetAttributeChangedSignal(name):Connect(function()
			setValue(player:GetAttribute(name))
		end)
		return function()
			connection:Disconnect()
		end
	end, { name })
	return value
end

local function SocialChip(_props: {})
	local on = useAttribute(Social.FRIENDS_ATTRIBUTE) == true
	if ServerRole.isTraining() then
		return nil
	end
	local pct = Social.percent(Config.FRIENDS)
	local text = if on then `✓ FLYING WITH FRIENDS {pct}` else `FLY WITH FRIENDS: {pct} CREDITS & XP`
	return e(C.Panel, {
		Size = UDim2.fromOffset(36 + #text * 7, 28),
		Position = UDim2.new(0.5, 0, 0, 56),
		AnchorPoint = Vector2.new(0.5, 0),
		StrokeColor = if on then Theme.Good else Theme.Dim,
		StrokeThickness = 1,
		StrokeTransparency = 0.4,
		Transparency = 0.25,
		Padding = 3,
	}, {
		Label = e(C.Label, {
			Text = text,
			Size = UDim2.fromScale(1, 1),
			Align = "Center",
			Bold = on,
			TextSize = 12,
			Color = if on then Theme.Good else Theme.Dim,
		}),
	})
end

return SocialChip
