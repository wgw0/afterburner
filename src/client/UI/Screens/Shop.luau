--!strict
-- Shop (UI-07, first pass; DESIGN §8). Your Wings, the Wings packs, the Tier Unlock and the game passes, each
-- with its Robux price. A product or pass that isn't created on the dashboard yet says "Coming soon" instead
-- of a buy button. What's still to come (VIP, boosters, season pass, the starter bundle, premium jets) is
-- listed at the bottom.
-- props: Data, OnBuyProduct(key) -> (ok, err), OnBuyPass(key) -> (ok, err), OnTechTree()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Passes = require(Shared.Config.Passes)
local Products = require(Shared.Config.Products)
local Shop = require(Shared.Shop)
local Skins = require(Shared.Skins)

local UI = script.Parent.Parent
local C = require(UI.Components)
local Theme = require(UI.Theme)

local e = React.createElement
local TIER_NAMES = { "I", "II", "III", "IV", "V" }
local CARD_W, CARD_H = 230, 150

local function section(title: string, order: number)
	return e(C.Label, {
		Text = title,
		Size = UDim2.new(1, 0, 0, 24),
		Heavy = true,
		TextSize = 18,
		Color = Theme.Accent,
		LayoutOrder = order,
	})
end

-- A card with a title, a line of detail and an action (or "Coming soon" / a status).
local function Card(props: {
	Title: string,
	Detail: string,
	Action: string?,
	Status: string?,
	Highlight: Color3?,
	Order: number,
	OnClick: (() -> (boolean, string?))?,
})
	local message, setMessage = React.useState(nil :: string?)
	return e(C.Panel, {
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		Padding = 14,
		LayoutOrder = props.Order,
		StrokeColor = props.Highlight,
	}, {
		Title = e(C.Label, {
			Text = props.Title,
			Size = UDim2.new(1, 0, 0, 24),
			Heavy = true,
			TextSize = 20,
			Color = props.Highlight or Theme.Text,
		}),
		Detail = e(C.Label, {
			Text = message or props.Detail,
			Size = UDim2.new(1, 0, 0, 52),
			Position = UDim2.fromOffset(0, 30),
			TextSize = 13,
			Wrap = true,
			AlignY = "Top",
			Color = if message then Theme.Warn else Theme.Dim,
		}),
		Action = if props.Action and props.OnClick
			then e(C.Button, {
				Text = props.Action,
				Style = "Primary",
				Size = UDim2.new(1, 0, 0, 36),
				Position = UDim2.new(0, 0, 1, -36),
				TextSize = 14,
				OnClick = function()
					local ok, err = (props.OnClick :: any)()
					setMessage(if ok then nil else err)
				end,
			})
			else e(C.Label, {
				Text = props.Status or "Coming soon",
				Size = UDim2.new(1, 0, 0, 36),
				Position = UDim2.new(0, 0, 1, -36),
				Bold = true,
				TextSize = 14,
				Align = "Center",
				Color = Theme.Dim,
			}),
	})
end

local function row(order: number, cards: { [string]: any })
	cards.Layout = C.List({ Horizontal = true, Gap = 14 })
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, CARD_H),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, cards)
end

local function ShopScreen(props: any)
	local data = props.Data
	local children: { [string]: any } = {
		Layout = C.List({ Gap = 14 }),
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, 24),
			PaddingLeft = UDim.new(0, 40),
			PaddingRight = UDim.new(0, 40),
			PaddingBottom = UDim.new(0, 30),
		}),
		Balance = e(C.Label, {
			Text = `YOU HAVE {C.number(data.Wings or 0)} WINGS`,
			Size = UDim2.new(1, 0, 0, 30),
			Heavy = true,
			TextSize = 24,
			Color = Theme.Wings,
			LayoutOrder = 0,
		}),
		Explain = e(C.Label, {
			Text = `Wings buy cosmetics. Every skin sold for Credits can also be bought straight away for {Skins.WINGS_PRICE} Wings on its jet's page.`,
			Size = UDim2.new(1, 0, 0, 18),
			TextSize = 14,
			Color = Theme.Dim,
			LayoutOrder = 1,
		}),
	}

	-- Wings packs, smallest first
	children.WingsTitle = section("WINGS", 10)
	local packs = {}
	for key, product in Products.LIST do
		if product.Kind == "Wings" then
			table.insert(packs, key)
		end
	end
	table.sort(packs, function(a, b)
		return Products.LIST[a].Price < Products.LIST[b].Price
	end)
	local packCards = {}
	for i, key in packs do
		local product = Products.LIST[key]
		local base = Products.LIST[packs[1]]
		local perRobux = (product.Amount :: number) / product.Price
		local bonus = math.round((perRobux / ((base.Amount :: number) / base.Price) - 1) * 100)
		packCards[key] = e(Card, {
			Title = `{C.number(product.Amount :: number)} Wings`,
			Detail = if bonus > 0 then `{bonus}% more Wings per Robux` else "Enough for one skin",
			Action = if Products.idFor(key) then `R$ {product.Price}` else nil,
			Highlight = Theme.Wings,
			Order = i,
			OnClick = function()
				return props.OnBuyProduct(key)
			end,
		})
	end
	children.Packs = row(11, packCards)

	-- Tier Unlock: the next one, if there is one
	local offer = Shop.tierUnlockOffer(data)
	children.UnlockTitle = section("SKIP AHEAD", 20)
	local unlockCards = {}
	if offer then
		local key = Products.tierUnlockKey(offer.tier) :: string
		unlockCards.Next = e(Card, {
			Title = `Unlock Tier {TIER_NAMES[offer.tier]}`,
			Detail = `Pick {Products.UNLOCK_JETS} Tier {TIER_NAMES[offer.tier]} jets to own straight away. R$ {Products.LIST[key].Price}.`,
			Action = "PICK JETS",
			Order = 1,
			OnClick = function()
				props.OnTechTree()
				return true, nil
			end,
		})
	else
		unlockCards.Done = e(Card, {
			Title = "Tier Unlocks",
			Detail = "You're past Tier V: from here every jet is earned in the air.",
			Status = "Done",
			Order = 1,
		})
	end
	children.Unlock = row(21, unlockCards)

	-- Game passes
	children.PassTitle = section("PASSES", 30)
	local passCards = {}
	local i = 0
	for key, pass in Passes.LIST do
		i += 1
		local owned = Players.LocalPlayer:GetAttribute(Passes.attribute(key)) == true
		passCards[key] = e(Card, {
			Title = pass.DisplayName,
			Detail = pass.Description,
			Action = if not owned and Passes.idFor(key) then `R$ {pass.Price}` else nil,
			Status = if owned then "Owned" else nil,
			Order = i,
			OnClick = function()
				return props.OnBuyPass(key)
			end,
		})
	end
	children.Passes = row(31, passCards)

	-- Still to come (DESIGN §8.2)
	children.SoonTitle = section("COMING LATER", 40)
	children.Soon = row(41, {
		VIP = e(
			Card,
			{ Title = "VIP Pilot", Detail = "+25% Credits, a VIP name tag and an exclusive camo.", Order = 1 }
		),
		Boosters = e(Card, { Title = "Boosters", Detail = "Double RP or Credits for an hour.", Order = 2 }),
		Season = e(Card, { Title = "Season Pass", Detail = "A free and a premium track of rewards.", Order = 3 }),
		Starter = e(Card, { Title = "Starter Bundle", Detail = "A camo, a booster and Wings, once.", Order = 4 }),
		Premium = e(Card, { Title = "Premium Jets", Detail = "Named variants with a unique camo.", Order = 5 }),
	})

	return e("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, children)
end

return ShopScreen
