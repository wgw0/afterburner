--!strict
-- The group and friends bonuses on the hangar (Shared/Social), a small chip under the news banner: each bonus
-- lit green with a tick when it's on, dim with how to get it when it isn't. The group half only shows once
-- Config/Social has a group id. Reads the GroupBonus / FriendsBonus attributes SocialService keeps on the
-- player. Not on training servers (nothing is earned there).

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
	local inGroup = useAttribute(Social.GROUP_ATTRIBUTE) == true
	local withFriends = useAttribute(Social.FRIENDS_ATTRIBUTE) == true
	if ServerRole.isTraining() then
		return nil
	end
	local parts: { { text: string, on: boolean } } = {}
	if Social.groupOn() then
		local pct = Social.percent(Config.GROUP)
		table.insert(parts, {
			text = if inGroup then `✓ GROUP {pct}` else `JOIN THE GROUP: {pct} CREDITS & XP`,
			on = inGroup,
		})
	end
	local pct = Social.percent(Config.FRIENDS)
	table.insert(parts, {
		text = if withFriends then `✓ FLYING WITH FRIENDS {pct}` else `FLY WITH FRIENDS: {pct} CREDITS & XP`,
		on = withFriends,
	})

	local children: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = 16, Align = "Center" }) }
	local width = 24
	for i, part in parts do
		local w = 12 + #part.text * 7
		width += w + (if i > 1 then 16 else 0)
		children[`P{i}`] = e(C.Label, {
			Text = part.text,
			Size = UDim2.fromOffset(w, 22),
			Align = "Center",
			Bold = part.on,
			TextSize = 12,
			Color = if part.on then Theme.Good else Theme.Dim,
			LayoutOrder = i,
		})
	end
	return e(C.Panel, {
		Size = UDim2.fromOffset(width, 28),
		Position = UDim2.new(0.5, 0, 0, 56),
		AnchorPoint = Vector2.new(0.5, 0),
		StrokeColor = if inGroup or withFriends then Theme.Good else Theme.Dim,
		StrokeThickness = 1,
		StrokeTransparency = 0.4,
		Transparency = 0.25,
		Padding = 3,
	}, children)
end

return SocialChip
