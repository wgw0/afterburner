--!strict
-- Your squadron (LIV-06), on the Career screen's SQUADRON tab. Not in one: invites waiting for you, JOIN by
-- tag, and CREATE (name, tag, open or invite-only, for Squadron.COST Credits). In one: its tag and name, this
-- week's points toward the goal and the reward to claim, the members (roles, who's online; the owner can
-- promote and remove, officers can remove members), INVITE (players on this server), open / invite-only, LEAVE.
-- props: OnSquadron() -> view?, OnSquadronAction(action, a?, b?) -> (ok, message), Version (re-fetch when it
-- changes), Order.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Squadron = require(Shared.Squadron)

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local GOLD = Color3.fromRGB(255, 201, 60)

local function box(props: {
	Text: string,
	Placeholder: string,
	Width: number,
	Max: number,
	OnText: (string) -> (),
	Order: number,
})
	return e("TextBox", {
		Text = props.Text,
		PlaceholderText = props.Placeholder,
		PlaceholderColor3 = Theme.Dim,
		ClearTextOnFocus = false,
		Font = Theme.FontBold,
		TextSize = 14,
		TextColor3 = Theme.Text,
		BackgroundColor3 = Theme.Background,
		Size = UDim2.fromOffset(props.Width, 32),
		LayoutOrder = props.Order,
		[React.Change.Text] = function(b: TextBox)
			if #b.Text > props.Max then
				b.Text = string.sub(b.Text, 1, props.Max)
			end
			props.OnText(b.Text)
		end,
	}, { Corner = C.corner(6), Stroke = C.stroke(Theme.Accent, 1) })
end

local function row(order: number, children: { [string]: any }, height: number?)
	children.Layout = C.List({ Horizontal = true, Gap = 8, AlignY = "Center" })
	return e(
		"Frame",
		{ Size = UDim2.new(1, 0, 0, height or 32), BackgroundTransparency = 1, LayoutOrder = order },
		children
	)
end

local function SquadronPanel(props: any)
	local view, setView = React.useState(nil :: any)
	local message, setMessage = React.useState(nil :: string?)
	local busy, setBusy = React.useState(false)
	local name, setName = React.useState("")
	local tag, setTag = React.useState("")
	local joinTag, setJoinTag = React.useState("")
	local open, setOpen = React.useState(true)
	local inviting, setInviting = React.useState(false)
	local refresh, setRefresh = React.useState(0)

	React.useEffect(function()
		local current = true
		task.spawn(function()
			local v = props.OnSquadron()
			if current then
				setView(v)
			end
		end)
		return function()
			current = false
		end
	end, { refresh, props.Version })

	local function act(action: string, a: any?, b: any?)
		setBusy(true)
		task.spawn(function()
			local ok, msg = props.OnSquadronAction(action, a, b)
			setBusy(false)
			setMessage(msg or (if ok then nil else "Try again in a moment."))
			if ok then
				setInviting(false)
				setRefresh(refresh + 1)
			end
		end)
	end

	local children: { [string]: any } = { Layout = C.List({ Gap = 10 }) }
	if not view then
		children.Loading = e(C.Label, { Text = "Loading…", TextSize = 14, Color = Theme.Dim, LayoutOrder = 1 })
		return e("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = props.Order,
		}, children)
	end

	local me = Players.LocalPlayer.UserId
	local squad = view.squadron
	if not squad then
		-- Invites, join, create
		for i, invite in view.invites or {} do
			children[`Invite{i}`] = row(i, {
				Text = e(C.Label, {
					Text = `[{invite.tag}] {invite.name} invited you`,
					Size = UDim2.fromOffset(360, 32),
					Bold = true,
					TextSize = 15,
					Color = GOLD,
					LayoutOrder = 1,
				}),
				Yes = e(C.Button, {
					Text = "JOIN",
					Style = "Primary",
					Size = UDim2.fromOffset(90, 32),
					TextSize = 13,
					Pending = busy,
					LayoutOrder = 2,
					OnClick = function()
						act("Respond", invite.id, true)
					end,
				}),
				No = e(C.Button, {
					Text = "DECLINE",
					Size = UDim2.fromOffset(110, 32),
					TextSize = 13,
					LayoutOrder = 3,
					OnClick = function()
						act("Respond", invite.id, false)
					end,
				}),
			})
		end
		children.Blurb = e(C.Label, {
			Text = `Fly under a shared tag ("[ACE] You"). Every player shot down earns your squadron {view.points.kill} point and every win {view.points.win}; at {view.goal} points in a week, everyone in it can claim {C.number(
				view.reward
			)} Credits.`,
			Size = UDim2.new(1, 0, 0, 36),
			Wrap = true,
			TextSize = 13,
			Color = Theme.Dim,
			LayoutOrder = 10,
		})
		children.JoinTitle =
			e(C.Label, { Text = "JOIN A SQUADRON", Bold = true, TextSize = 14, Color = Theme.Accent, LayoutOrder = 11 })
		children.Join = row(12, {
			Tag = box({
				Text = joinTag,
				Placeholder = "TAG",
				Width = 120,
				Max = Squadron.TAG_MAX,
				OnText = setJoinTag,
				Order = 1,
			}),
			Go = e(C.Button, {
				Text = "JOIN",
				Style = "Primary",
				Size = UDim2.fromOffset(100, 32),
				TextSize = 13,
				Pending = busy,
				Disabled = #joinTag < Squadron.TAG_MIN,
				LayoutOrder = 2,
				OnClick = function()
					act("Join", joinTag)
				end,
			}),
			Hint = e(C.Label, {
				Text = "Open squadrons only; an invite-only one has to invite you.",
				Size = UDim2.fromOffset(420, 32),
				TextSize = 12,
				Color = Theme.Dim,
				LayoutOrder = 3,
			}),
		})
		children.CreateTitle =
			e(C.Label, { Text = "START ONE", Bold = true, TextSize = 14, Color = Theme.Accent, LayoutOrder = 13 })
		children.Create = row(14, {
			Name = box({
				Text = name,
				Placeholder = "Squadron name",
				Width = 240,
				Max = Squadron.NAME_MAX,
				OnText = setName,
				Order = 1,
			}),
			Tag = box({
				Text = tag,
				Placeholder = "TAG",
				Width = 90,
				Max = Squadron.TAG_MAX,
				OnText = setTag,
				Order = 2,
			}),
			-- A setting, not an action: it says who can join (click to switch)
			Open = e(C.Button, {
				Text = if open then "ANYONE CAN JOIN ⇄" else "INVITE ONLY ⇄",
				Style = "Ghost",
				Size = UDim2.fromOffset(160, 32),
				TextSize = 12,
				LayoutOrder = 3,
				OnClick = function()
					setOpen(not open)
				end,
			}),
			Go = e(C.Button, {
				Text = `CREATE  ·  {C.number(view.cost)} Cr`,
				Style = "Primary",
				Size = UDim2.fromOffset(200, 32),
				TextSize = 13,
				Pending = busy,
				Disabled = #name < Squadron.NAME_MIN or #tag < Squadron.TAG_MIN,
				LayoutOrder = 4,
				OnClick = function()
					act(if open then "Create" else "CreateClosed", name, tag)
				end,
			}),
		})
	else
		local manage = squad.role == "Owner" or squad.role == "Officer"
		children.Head = row(1, {
			Title = e(C.Label, {
				Text = `[{squad.tag}] {string.upper(squad.name)}`,
				Size = UDim2.fromOffset(420, 32),
				Heavy = true,
				TextSize = 22,
				Color = Theme.Accent,
				LayoutOrder = 1,
			}),
			Info = e(C.Label, {
				Text = `{#squad.members}/{squad.max} pilots  ·  {if squad.open then "open" else "invite-only"}  ·  you're {string.lower(
					squad.role or "a member"
				)}`,
				Size = UDim2.fromOffset(360, 32),
				TextSize = 13,
				Color = Theme.Dim,
				LayoutOrder = 2,
			}),
		})
		children.Week = row(2, {
			Bar = e(C.Bar, {
				Value = squad.score / view.goal,
				Size = UDim2.fromOffset(320, 14),
				Color = if squad.score >= view.goal then Theme.Good else Theme.Accent,
				LayoutOrder = 1,
			}),
			Score = e(C.Label, {
				Text = `{C.number(squad.score)} / {view.goal} points this week`,
				Size = UDim2.fromOffset(220, 32),
				Bold = true,
				TextSize = 13,
				LayoutOrder = 2,
			}),
			Claim = e(C.Button, {
				Text = if squad.claimed then "CLAIMED ✓" else `CLAIM {C.number(view.reward)} Cr`,
				Style = "Primary",
				Color = Theme.Good,
				Size = UDim2.fromOffset(180, 32),
				TextSize = 13,
				Pending = busy,
				Disabled = squad.claimed or squad.score < view.goal,
				LayoutOrder = 3,
				OnClick = function()
					act("Claim")
				end,
			}),
		})
		for i, member in squad.members do
			local isMe = member.userId == me
			local buttons: { [string]: any } = {}
			if squad.role == "Owner" and not isMe then
				buttons.Promote = e(C.Button, {
					Text = if member.role == "Officer" then "MAKE MEMBER" else "MAKE OFFICER",
					Style = "Ghost",
					Size = UDim2.fromOffset(120, 26),
					TextSize = 11,
					LayoutOrder = 3,
					OnClick = function()
						act("Role", member.userId, if member.role == "Officer" then "Member" else "Officer")
					end,
				})
			end
			local canKick = manage
				and not isMe
				and member.role ~= "Owner"
				and (squad.role == "Owner" or member.role == "Member")
			if canKick then
				buttons.Kick = e(C.Button, {
					Text = "REMOVE",
					Style = "Ghost",
					Size = UDim2.fromOffset(80, 26),
					TextSize = 11,
					LayoutOrder = 4,
					OnClick = function()
						act("Kick", member.userId)
					end,
				})
			end
			buttons.Name = e(C.Label, {
				Text = (if member.online then `<font color="#{Theme.Good:ToHex()}">●</font>  ` else "   ")
					.. member.name
					.. (if isMe then "  (you)" else ""),
				Rich = true,
				Size = UDim2.fromOffset(260, 26),
				Bold = true,
				TextSize = 14,
				LayoutOrder = 1,
			})
			buttons.Role = e(C.Label, {
				Text = string.upper(member.role),
				Size = UDim2.fromOffset(90, 26),
				TextSize = 12,
				Bold = true,
				Color = if member.role == "Owner"
					then GOLD
					elseif member.role == "Officer" then Theme.Accent
					else Theme.Dim,
				LayoutOrder = 2,
			})
			children[`M{i}`] = row(10 + i, buttons, 26)
		end
		local tools: { [string]: any } = {}
		if manage then
			tools.Invite = e(C.Button, {
				Text = if inviting then "CLOSE" else "INVITE",
				Size = UDim2.fromOffset(100, 32),
				TextSize = 13,
				LayoutOrder = 1,
				OnClick = function()
					setInviting(not inviting)
				end,
			})
			tools.Open = e(C.Button, {
				Text = if squad.open then "MAKE INVITE-ONLY" else "MAKE OPEN",
				Style = "Ghost",
				Size = UDim2.fromOffset(170, 32),
				TextSize = 12,
				LayoutOrder = 2,
				OnClick = function()
					act("Open", not squad.open)
				end,
			})
		end
		tools.Leave = e(C.Button, {
			Text = "LEAVE",
			Style = "Danger",
			Size = UDim2.fromOffset(100, 32),
			TextSize = 13,
			Pending = busy,
			LayoutOrder = 3,
			OnClick = function()
				act("Leave")
			end,
		})
		children.Tools = row(100, tools)
		if inviting then
			local members = {}
			for _, member in squad.members do
				members[member.userId] = true
			end
			local list: { [string]: any } = {}
			local count = 0
			for _, player in Players:GetPlayers() do
				if not members[player.UserId] then
					count += 1
					list[`P{player.UserId}`] = e(C.Button, {
						Text = player.DisplayName,
						Size = UDim2.fromOffset(160, 28),
						TextSize = 12,
						LayoutOrder = count,
						OnClick = function()
							act("Invite", player.UserId)
						end,
					})
				end
			end
			if count == 0 then
				list.None = e(C.Label, {
					Text = "Nobody here to invite. Open squadrons can be joined by tag from any server.",
					Size = UDim2.fromOffset(520, 28),
					TextSize = 12,
					Color = Theme.Dim,
				})
			end
			children.Invites = row(101, list, 28)
		end
	end
	if message then
		children.Message = e(
			C.Label,
			{ Text = message, Size = UDim2.new(1, 0, 0, 18), TextSize = 13, Color = Theme.Warn, LayoutOrder = 200 }
		)
	end
	return e("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.Order,
	}, children)
end

return SquadronPanel
