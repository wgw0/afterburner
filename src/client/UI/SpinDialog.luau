--!strict
-- The free-spin window (Shared/Spin): a CS:GO-style reel. SPIN asks the server, which rolls and grants the
-- prize; the reel is then filled with random prize cards (each bordered in its rarity's colour) with the
-- prize at the stop, and slides to it, slowing down; then NICE! closes it. The (i) button shows the odds.
-- Spins are never sold.
-- props: OnSpin() -> (prize?, err), OnClose()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Spin = require(Shared.Spin)

local C = require(script.Parent.Components)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local CARD_W, CARD_H, GAP = 140, 160, 10
local VIEW_W = 900
local WIN_INDEX = 42 -- the prize's place in the reel
local REEL_LENGTH = WIN_INDEX + 6
local SPIN_SECONDS = 6
local REEL_Y = 10 -- the cards' gap from the top of the window
-- How often each rarity shows up among the reel's filler cards. Only the look: the prize is the server's,
-- rolled with the real odds (Spin.TIERS, shown behind (i)); a reel of nothing but grey looked hopeless.
local FILLER_WEIGHTS = { 45, 24, 15, 10, 6 }

type Card = { Rarity: string, Kind: string, Title: string, Sub: string }

local function short(n: number): string
	return if n >= 1000 then string.format("%s,%03d", tostring(n // 1000), n % 1000) else tostring(n)
end

-- A card for a prize the server gave.
local function prizeCard(prize: Spin.Prize): Card
	local jet = prize.Airframe and AircraftData.get(prize.Airframe)
	local jetName = if jet then jet.DisplayName else ""
	if prize.Kind == "Module" then
		return { Rarity = prize.Rarity, Kind = "Module", Title = "UPGRADE", Sub = `{prize.Label}\n{jetName}` }
	elseif prize.Kind == "Skin" then
		return { Rarity = prize.Rarity, Kind = "Skin", Title = "SKIN", Sub = `{prize.Label}\n{jetName}` }
	end
	return {
		Rarity = prize.Rarity,
		Kind = prize.Kind,
		Title = short(prize.Amount :: number),
		Sub = if prize.Kind == "Wings" then "WINGS" else "CREDITS",
	}
end

-- A card standing in for a tier's prize (the reel's filler).
local function tierCard(index: number): Card
	local tier = Spin.TIERS[index]
	if tier.Kind == "Module" then
		return { Rarity = tier.Rarity, Kind = "Module", Title = "UPGRADE", Sub = "for a jet you own" }
	elseif tier.Kind == "Skin" then
		return { Rarity = tier.Rarity, Kind = "Skin", Title = "SKIN", Sub = "for a jet you own" }
	end
	return {
		Rarity = tier.Rarity,
		Kind = tier.Kind,
		Title = short(tier.Amount :: number),
		Sub = if tier.Kind == "Wings" then "WINGS" else "CREDITS",
	}
end

-- A filler card's tier: weighted by FILLER_WEIGHTS, never a third of the same rarity in a row.
local function fillerTier(cards: { Card }, index: number): number
	local function pick(): number
		local total = 0
		for _, w in FILLER_WEIGHTS do
			total += w
		end
		local at = math.random() * total
		for i, w in FILLER_WEIGHTS do
			at -= w
			if at < 0 then
				return i
			end
		end
		return 1
	end
	local a, b = cards[index - 1], cards[index - 2]
	for _ = 1, 10 do
		local tier = pick()
		local rarity = Spin.TIERS[tier].Rarity
		if not (a and b and a.Rarity == rarity and b.Rarity == rarity) then
			return tier
		end
	end
	return pick()
end

local function cardElement(card: Card, order: number)
	local colour = Theme.Rarity[card.Rarity] or Theme.Text
	local accent = if card.Kind == "Wings" then Theme.Wings elseif card.Kind == "Credits" then Theme.Text else colour
	return e("Frame", {
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = Color3.new(1, 1, 1), -- coloured by the gradient
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, {
		Corner = C.corner(),
		Stroke = e("UIStroke", { Color = colour, Thickness = 3 }),
		-- Dark behind the text, warming into the rarity's colour towards the bottom
		Shade = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Panel),
				ColorSequenceKeypoint.new(0.6, Theme.Panel),
				ColorSequenceKeypoint.new(1, Theme.Panel:Lerp(colour, 0.45)),
			}),
		}),
		Title = e(C.Label, {
			Text = card.Title,
			Size = UDim2.new(1, -10, 0, 40),
			Position = UDim2.fromOffset(5, 30),
			Heavy = true,
			TextSize = if #card.Title > 6 then 22 else 30,
			Align = "Center",
			Color = accent,
		}),
		Sub = e(C.Label, {
			Text = card.Sub,
			Size = UDim2.new(1, -10, 0, 44),
			Position = UDim2.fromOffset(5, 76),
			TextSize = 12,
			Wrap = true,
			Align = "Center",
			AlignY = "Top",
			Color = Theme.Dim,
		}),
		Band = e("Frame", {
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.new(0, 0, 1, -22),
			BackgroundColor3 = colour,
			BorderSizePixel = 0,
		}, {
			Corner = C.corner(),
			Label = e(C.Label, {
				Text = string.upper(card.Rarity),
				Size = UDim2.fromScale(1, 1),
				Bold = true,
				TextSize = 11,
				Align = "Center",
				Color = Theme.Background,
			}),
		}),
	})
end

-- "Next free spin in 12:34", from the server's SpinNextAt (one every 20 minutes you play).
local function nextSpinText(now: number): string
	local nextAt = (Players.LocalPlayer:GetAttribute("SpinNextAt") :: number?) or 0
	if nextAt == 0 then
		return "One free spin every 20 minutes you play"
	end
	local left = math.max(math.ceil(nextAt - now), 0)
	return if left > 0
		then string.format("Next free spin in %d:%02d", left // 60, left % 60)
		else "Your next free spin is nearly ready"
end

local function SpinDialog(props: { OnSpin: () -> (Spin.Prize?, string?), OnClose: () -> () })
	local reel, setReel = React.useState(nil :: { Card }?)
	local phase, setPhase = React.useState("idle") -- idle | asking | spinning | result
	local prize, setPrize = React.useState(nil :: Spin.Prize?)
	local message, setMessage = React.useState(nil :: string?)
	local showOdds, setShowOdds = React.useState(false)
	local banked, setBanked = React.useState((Players.LocalPlayer:GetAttribute("SpinsBanked") :: number?) or 0)
	local strip = React.useRef(nil)
	local now, setNow = React.useState(workspace:GetServerTimeNow())
	React.useEffect(function()
		local running = true
		task.spawn(function()
			while running do
				task.wait(0.5)
				setNow(workspace:GetServerTimeNow())
			end
		end)
		return function()
			running = false
		end
	end, {})

	React.useEffect(function()
		local connection = Players.LocalPlayer:GetAttributeChangedSignal("SpinsBanked"):Connect(function()
			setBanked((Players.LocalPlayer:GetAttribute("SpinsBanked") :: number?) or 0)
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	-- Slide the reel to the prize once it's built
	React.useEffect(function()
		local frame = strip.current
		if not (reel and frame and phase == "spinning") then
			return
		end
		local jitter = (math.random() - 0.5) * (CARD_W * 0.7) -- stop somewhere on the card, not dead centre
		local target = -(WIN_INDEX - 1) * (CARD_W + GAP) - CARD_W / 2 + VIEW_W / 2 + jitter
		frame.Position = UDim2.fromOffset(0, REEL_Y)
		local tween = TweenService:Create(
			frame,
			TweenInfo.new(SPIN_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(target, REEL_Y) }
		)
		local done = tween.Completed:Connect(function()
			setPhase("result")
		end)
		tween:Play()
		return function()
			done:Disconnect()
			tween:Cancel()
		end
	end, { reel, phase } :: { any })

	local function spin()
		setPhase("asking")
		setMessage(nil)
		task.spawn(function()
			local won, why = props.OnSpin()
			if not won then
				setPhase("idle")
				setMessage(why or "Try again in a moment.")
				return
			end
			local cards = {}
			for i = 1, REEL_LENGTH do
				cards[i] = if i == WIN_INDEX then prizeCard(won) else tierCard(fillerTier(cards, i))
			end
			setPrize(won)
			setReel(cards)
			setPhase("spinning")
		end)
	end

	local cards: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = GAP }) }
	for i, card in reel or {} do
		cards[`C{i}`] = cardElement(card, i)
	end
	if not reel then
		-- Before the first spin: one of each, rarest last, so you see what's on offer
		for i in Spin.TIERS do
			cards[`T{i}`] = cardElement(tierCard(i), i)
		end
	end

	local odds: { [string]: any } = { Layout = C.List({ Gap = 6 }) }
	odds.Title =
		e(C.Label, { Text = "ODDS PER SPIN", Bold = true, TextSize = 14, Color = Theme.Accent, LayoutOrder = 0 })
	for i, tier in Spin.TIERS do
		local card = tierCard(i)
		local what = if tier.Kind == "Credits" or tier.Kind == "Wings"
			then `{card.Title} {string.lower(card.Sub)}`
			elseif tier.Kind == "Module" then "A free upgrade for a jet you own"
			else "A skin for a jet you own (not level skins)"
		odds[`R{i}`] = e(C.Label, {
			Text = `<font color="#{(Theme.Rarity[tier.Rarity] :: Color3):ToHex()}"><b>{string.upper(tier.Rarity)}</b></font>  {what}  ·  {tier.Weight}%`,
			Rich = true,
			TextSize = 13,
			Size = UDim2.new(1, 0, 0, 18),
			LayoutOrder = i,
		})
	end
	odds.Note = e(C.Label, {
		Text = "No upgrade or skin left to win? You get 750 Credits or 150 Wings instead. Spins are free and never sold.",
		Wrap = true,
		TextSize = 12,
		Color = Theme.Dim,
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = 99,
	})

	local resultText = if phase == "result" and prize
		then `<font color="#{(Theme.Rarity[prize.Rarity] :: Color3):ToHex()}"><b>{string.upper(prize.Rarity)}</b></font>  You won {prize.Label}{if prize.Airframe
			then " for the " .. ((AircraftData.get(prize.Airframe) :: any) or { DisplayName = prize.Airframe }).DisplayName
			else ""}!`
		elseif phase == "spinning" or phase == "asking" then "Good luck…"
		else message or (if banked > 0
			then `{banked} spin{if banked == 1 then "" else "s"} ready`
			else nextSpinText(now))

	return e("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
	}, {
		Panel = e(C.Panel, {
			Size = UDim2.fromOffset(VIEW_W + 60, 420),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Padding = 30,
			StrokeColor = Theme.Rarity.Legendary,
		}, {
			Title = e(C.Label, {
				Text = "FREE SPIN",
				Size = UDim2.new(1, 0, 0, 34),
				Heavy = true,
				TextSize = 30,
				Color = Theme.Rarity.Legendary,
			}),
			Info = e(C.Button, {
				Text = "i",
				Style = if showOdds then "Primary" else "Ghost",
				Size = UDim2.fromOffset(34, 34),
				Position = UDim2.new(1, -84, 0, 0),
				TextSize = 16,
				OnClick = function()
					setShowOdds(not showOdds)
				end,
			}),
			Close = e(C.Button, {
				Text = "X",
				Style = "Ghost",
				Size = UDim2.fromOffset(34, 34),
				Position = UDim2.new(1, -34, 0, 0),
				TextSize = 16,
				Disabled = phase == "spinning" or phase == "asking",
				OnClick = props.OnClose,
			}),
			Window = e("Frame", {
				Size = UDim2.fromOffset(VIEW_W, CARD_H + 20),
				Position = UDim2.fromOffset(0, 54),
				BackgroundColor3 = Theme.Background,
				ClipsDescendants = true,
				Visible = not showOdds,
			}, {
				Corner = C.corner(),
				Strip = e("Frame", {
					Size = UDim2.fromOffset(REEL_LENGTH * (CARD_W + GAP), CARD_H),
					Position = UDim2.fromOffset(if reel then 0 else (VIEW_W - 5 * CARD_W - 4 * GAP) / 2, REEL_Y),
					BackgroundTransparency = 1,
					ref = strip,
				}, cards),
				-- The marker the reel stops under
				Marker = if reel
					then e("Frame", {
						Size = UDim2.new(0, 3, 1, 0),
						Position = UDim2.fromScale(0.5, 0),
						AnchorPoint = Vector2.new(0.5, 0),
						BackgroundColor3 = Theme.Rarity.Legendary,
						BorderSizePixel = 0,
						ZIndex = 5,
					})
					else nil,
			}),
			Odds = if showOdds
				then e("Frame", {
					Size = UDim2.fromOffset(VIEW_W, CARD_H + 20),
					Position = UDim2.fromOffset(0, 54),
					BackgroundTransparency = 1,
				}, odds)
				else nil,
			Result = e(C.Label, {
				Text = resultText,
				Rich = true,
				Size = UDim2.new(1, 0, 0, 26),
				Position = UDim2.fromOffset(0, 254),
				TextSize = 18,
				Bold = true,
				Align = "Center",
				Color = if message then Theme.Warn else Theme.Text,
			}),
			-- After a win: NICE! closes the window (open it again from the hangar to use another spin)
			Spin = e(C.Button, {
				Text = if phase == "result"
					then "NICE!"
					elseif phase == "spinning" or phase == "asking" then "SPINNING…"
					else "SPIN",
				Style = "Primary",
				Size = UDim2.fromOffset(260, 56),
				Position = UDim2.new(0.5, 0, 1, -56),
				AnchorPoint = Vector2.new(0.5, 0),
				TextSize = 24,
				Disabled = phase == "spinning" or phase == "asking" or (phase ~= "result" and banked < 1),
				OnClick = if phase == "result" then props.OnClose else spin,
			}),
		}),
	})
end

return SpinDialog
