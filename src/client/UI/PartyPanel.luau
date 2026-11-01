--!strict
-- Your party (MMK-05), on the right of the lobby's Hangar above MATCHMAKING: who's in it (the leader
-- starred, REMOVE for the leader), INVITE (someone on this server), INVITE FRIENDS (Roblox's invite window)
-- and LEAVE. Invites for you pop up at the top of the screen with ACCEPT and DECLINE.
-- props: Party ({ leader, members = { { userId, name } }, invites = { { userId, name } }, max }), Candidates
--   ({ { userId, name } }: players here you could invite), OnInvite(userId) -> (ok, why),
--   OnRespond(userId, yes) -> (ok, why), OnKick(userId) -> (ok, why), OnLeave(), OnInviteFriends()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local WIDTH, ROW_H = 300, 30
local GOLD = Color3.fromRGB(255, 201, 60)

-- An invite for you, at the top of the screen.
local function InviteToast(props: { Invite: { userId: number, name: string }, OnRespond: any, Order: number })
	local message, setMessage = React.useState(nil :: string?)
	return e(C.Panel, {
		Size = UDim2.fromOffset(420, 64),
		Padding = 12,
		LayoutOrder = props.Order,
		StrokeColor = Theme.Accent,
	}, {
		Text = e(C.Label, {
			Text = message or `{props.Invite.name} invited you to their party`,
			Size = UDim2.new(1, -190, 1, 0),
			Wrap = true,
			Bold = true,
			TextSize = 14,
			Color = if message then Theme.Warn else Theme.Text,
		}),
		Accept = e(C.Button, {
			Text = "ACCEPT",
			Style = "Primary",
			Size = UDim2.fromOffset(88, 36),
			Position = UDim2.new(1, -182, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			TextSize = 13,
			OnClick = function()
				local ok, why = props.OnRespond(props.Invite.userId, true)
				setMessage(if ok then nil else why)
			end,
		}),
		Decline = e(C.Button, {
			Text = "DECLINE",
			Size = UDim2.fromOffset(88, 36),
			Position = UDim2.new(1, -88, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			TextSize = 13,
			OnClick = function()
				props.OnRespond(props.Invite.userId, false)
			end,
		}),
	})
end

local function PartyPanel(props: any)
	local party = props.Party or { members = {}, invites = {}, max = 3 }
	local picking, setPicking = React.useState(false)
	local message, setMessage = React.useState(nil :: string?)
	local me = Players.LocalPlayer.UserId
	local leader = party.leader
	local inParty = leader ~= nil
	local isLeader = not inParty or leader == me
	local full = #party.members >= (party.max or 3)

	local children: { [string]: any } = {
		Layout = C.List({ Gap = 6 }),
		Title = e(C.Label, {
			Text = if inParty then `PARTY  ·  {#party.members}/{party.max or 3}` else "PARTY",
			Size = UDim2.new(1, 0, 0, 18),
			Bold = true,
			TextSize = 13,
			Color = Theme.Accent,
			LayoutOrder = 1,
		}),
	}
	if inParty then
		for i, member in party.members do
			local isThem = member.userId == leader
			children[`M{i}`] = e("Frame", {
				Size = UDim2.new(1, 0, 0, ROW_H),
				BackgroundTransparency = 1,
				LayoutOrder = 1 + i,
			}, {
				Name = e(C.Label, {
					Text = (if isThem then `<font color="#{GOLD:ToHex()}">★</font>  ` else "")
						.. member.name
						.. (if member.userId == me then "  (you)" else ""),
					Rich = true,
					Size = UDim2.new(1, -90, 1, 0),
					Bold = true,
					TextSize = 14,
				}),
				Kick = if leader == me and member.userId ~= me
					then e(C.Button, {
						Text = "REMOVE",
						Style = "Ghost",
						Size = UDim2.fromOffset(80, 24),
						Position = UDim2.new(1, -80, 0.5, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						TextSize = 11,
						OnClick = function()
							local ok, why = props.OnKick(member.userId)
							setMessage(if ok then nil else why)
						end,
					})
					else nil,
			})
		end
	else
		children.Blurb = e(C.Label, {
			Text = "Fly with friends: a party queues together and is always on the same team.",
			Size = UDim2.new(1, 0, 0, 32),
			Wrap = true,
			TextSize = 12,
			Color = Theme.Dim,
			LayoutOrder = 2,
		})
	end

	-- Picking someone here to invite
	if picking and isLeader and not full then
		local list: { [string]: any } = { Layout = C.List({ Gap = 4 }) }
		for i, candidate in props.Candidates or {} do
			list[`C{i}`] = e(C.Button, {
				Text = candidate.name,
				Size = UDim2.new(1, 0, 0, 26),
				TextSize = 13,
				LayoutOrder = i,
				OnClick = function()
					local ok, why = props.OnInvite(candidate.userId)
					setMessage(if ok then `Invited {candidate.name}` else why)
					setPicking(false)
				end,
			})
		end
		local count = #(props.Candidates or {})
		children.Pick = if count > 0
			then e("ScrollingFrame", {
				Size = UDim2.new(1, 0, 0, math.min(count, 4) * 30),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 4,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				LayoutOrder = 10,
			}, list)
			else e(C.Label, {
				Text = "Nobody else here is free. Try INVITE FRIENDS.",
				Size = UDim2.new(1, 0, 0, 18),
				TextSize = 12,
				Color = Theme.Dim,
				LayoutOrder = 10,
			})
	end

	if message then
		children.Message = e(C.Label, {
			Text = message,
			Size = UDim2.new(1, 0, 0, 16),
			TextSize = 12,
			Color = Theme.Warn,
			LayoutOrder = 11,
		})
	end

	local buttons: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = 6 }) }
	if isLeader and not full then
		buttons.Invite = e(C.Button, {
			Text = if picking then "CLOSE" else "INVITE",
			Size = UDim2.fromOffset(80, 30),
			TextSize = 12,
			LayoutOrder = 1,
			OnClick = function()
				setMessage(nil)
				setPicking(not picking)
			end,
		})
		buttons.Friends = e(C.Button, {
			Text = "INVITE FRIENDS",
			Style = "Primary",
			Size = UDim2.fromOffset(if inParty then 112 else 186, 30),
			TextSize = 12,
			LayoutOrder = 2,
			OnClick = props.OnInviteFriends,
		})
	end
	if inParty then
		buttons.Leave = e(C.Button, {
			Text = "LEAVE",
			Style = "Danger",
			Size = UDim2.fromOffset(if isLeader and not full then 68 else 272, 30),
			TextSize = 12,
			LayoutOrder = 3,
			OnClick = function()
				setPicking(false)
				props.OnLeave()
			end,
		})
	end
	children.Buttons =
		e("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 20 }, buttons)

	local toasts: { [string]: any } = { Layout = C.List({ Gap = 8, Align = "Center" }) }
	for i, invite in party.invites or {} do
		toasts[`I{invite.userId}`] = e(InviteToast, { Invite = invite, OnRespond = props.OnRespond, Order = i })
	end

	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Panel = e(C.Panel, {
			Size = UDim2.fromOffset(WIDTH, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.new(1, -20, 1, -304),
			AnchorPoint = Vector2.new(1, 1),
			Padding = 14,
		}, children),
		Invites = if #(party.invites or {}) > 0
			then e("Frame", {
				Size = UDim2.fromOffset(420, 300),
				Position = UDim2.new(0.5, 0, 0, 20),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
			}, toasts)
			else nil,
	})
end

return PartyPanel
