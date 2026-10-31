--!strict
-- Shop (UI-07; DESIGN §8; layout for conversion in DEVELOPMENT.md §27.9). Top to bottom: VIP Pilot as a
-- banner (or a thank-you once owned), the game passes as big cards with their benefits, boosters, the Tier
-- Unlock, Wings packs, cosmetics bought with Wings (SHP-07: buy, equip, take off), then what's coming. Every
-- price is shown before the purchase window; nothing is random or on a fake timer. A product or pass that
-- isn't created on the dashboard yet says "Coming soon" instead of a buy button. What's still to come (the
-- season pass, the starter bundle, premium jets) is listed at the bottom.
-- props: Data, OnBuyProduct(key) -> (ok, err), OnBuyPass(key) -> (ok, err), OnTechTree(),
--   OnBuyCosmetic(id) -> (ok, err), OnEquipCosmetic(kind, id) -> (ok, err)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalogue = require(Shared.Config.Cosmetics)
local Cosmetics = require(Shared.Cosmetics)
local Passes = require(Shared.Config.Passes)
local Perks = require(Shared.Perks)
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
local function Card(
	props: {
		Title: string,
		Detail: string,
		Action: string?,
		Status: string?,
		Highlight: Color3?,
		Image: string?, -- a picture in the top right (wing art)
		Ribbon: string?, -- a tag in the top right ("BEST VALUE")
		Order: number,
		OnClick: (() -> (boolean, string?))?,
	}
)
	local message, setMessage = React.useState(nil :: string?)
	return e(C.Panel, {
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		Padding = 14,
		LayoutOrder = props.Order,
		StrokeColor = props.Highlight,
	}, {
		Ribbon = if props.Ribbon
			then e(C.Pill, {
				Text = props.Ribbon,
				Size = UDim2.fromOffset(92, 20),
				Position = UDim2.new(1, 0, 0, -14), -- on the top edge, clear of the title
				AnchorPoint = Vector2.new(1, 0.5),
				Color = props.Highlight or Theme.Accent,
				TextColor = Theme.Background,
			})
			else nil,
		Picture = if props.Image
			then e("ImageLabel", {
				Image = props.Image,
				Size = UDim2.fromOffset(64, 32),
				Position = UDim2.fromScale(1, 0),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
			})
			else nil,
		Title = e(C.Label, {
			Text = props.Title,
			Size = UDim2.new(1, if props.Image then -68 else 0, 0, 24),
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

local GOLD = Color3.fromRGB(255, 201, 60) -- the VIP gold
local PASS_STYLE = {
	VIP = { Icon = "★", Colour = GOLD },
	ExtraLineupSlot = { Icon = "+", Colour = Color3.fromRGB(110, 205, 255) },
	CustomCallsign = { Icon = "Aa", Colour = Color3.fromRGB(120, 230, 180), TextSize = 28 }, -- letters read bigger
}
local PASS_ORDER = { "VIP", "ExtraLineupSlot", "CustomCallsign" }
local PASS_W, PASS_H = 300, 250

-- A dark panel washed with a colour from the top, for the pass cards and the VIP banner. A UIGradient
-- multiplies the panel's colour, so a washed panel is white underneath (Color = UNDER_WASH).
local UNDER_WASH = Color3.new(1, 1, 1)
local function wash(colour: Color3, strength: number)
	return e("UIGradient", {
		Color = ColorSequence.new(Theme.Panel:Lerp(colour, strength), Theme.Panel),
		Rotation = 90,
	})
end

local function bullets(list: { string }, colour: Color3, textSize: number)
	local children: { [string]: any } = { Layout = C.List({ Gap = 4 }) }
	for i, text in list do
		children[`B{i}`] = e(C.Label, {
			Text = `<font color="#{colour:ToHex()}">✓</font>  {text}`,
			Rich = true,
			Size = UDim2.new(1, 0, 0, textSize + 6),
			TextSize = textSize,
			Color = Theme.Text,
			LayoutOrder = i,
		})
	end
	return children
end

-- VIP Pilot across the top: the strongest offer, with its benefits and price. Once owned, a thank-you.
local function VipBanner(props: { Owned: boolean, Buyable: boolean, OnBuy: () -> (boolean, string?), Order: number })
	local pass = Passes.LIST.VIP
	local message, setMessage = React.useState(nil :: string?)
	if props.Owned then
		return e(C.Panel, {
			Size = UDim2.new(1, 0, 0, 56),
			Padding = 14,
			LayoutOrder = props.Order,
			StrokeColor = GOLD,
			Color = UNDER_WASH,
		}, {
			Wash = wash(GOLD, 0.2),
			Text = e(C.Label, {
				Text = "★  YOU'RE A VIP PILOT  ·  +25% Credits on every match, gold tag and contrails, an extra reroll",
				Size = UDim2.fromScale(1, 1),
				Bold = true,
				TextSize = 16,
				Color = GOLD,
			}),
		})
	end
	return e(C.Panel, {
		Size = UDim2.new(1, 0, 0, 206),
		Padding = 20,
		LayoutOrder = props.Order,
		StrokeColor = GOLD,
		Color = UNDER_WASH,
	}, {
		Wash = wash(GOLD, 0.35),
		Ribbon = e(C.Pill, {
			Text = "OUR TOP PICK",
			Size = UDim2.fromOffset(120, 22),
			Position = UDim2.fromScale(1, 0),
			AnchorPoint = Vector2.new(1, 0),
			Color = GOLD,
			TextColor = Theme.Background,
		}),
		Title = e(C.Label, {
			Text = `★  {string.upper(pass.DisplayName)}`,
			Size = UDim2.new(0.6, 0, 0, 36),
			Heavy = true,
			TextSize = 32,
			Color = GOLD,
		}),
		Sub = e(C.Label, {
			Text = "One payment. Yours forever, on every jet.",
			Size = UDim2.new(0.6, 0, 0, 20),
			Position = UDim2.fromOffset(0, 40),
			TextSize = 15,
			Color = Theme.Dim,
		}),
		Benefits = e("Frame", {
			Size = UDim2.new(0.6, 0, 0, 90),
			Position = UDim2.fromOffset(0, 68),
			BackgroundTransparency = 1,
		}, bullets(pass.Benefits, GOLD, 15)),
		Buy = if props.Buyable
			then e(C.Button, {
				Text = `GET VIP  ·  R$ {pass.Price}`,
				Style = "Primary",
				Color = GOLD,
				TextColor = Theme.Background,
				Size = UDim2.fromOffset(260, 56),
				Position = UDim2.fromScale(1, 1),
				AnchorPoint = Vector2.new(1, 1),
				TextSize = 20,
				OnClick = function()
					local ok, err = props.OnBuy()
					setMessage(if ok then nil else err)
				end,
			})
			else e(C.Label, {
				Text = "Coming soon",
				Size = UDim2.fromOffset(260, 56),
				Position = UDim2.fromScale(1, 1),
				AnchorPoint = Vector2.new(1, 1),
				Align = "Center",
				Color = Theme.Dim,
			}),
		Message = if message
			then e(C.Label, {
				Text = message,
				Size = UDim2.fromOffset(260, 18),
				Position = UDim2.new(1, 0, 1, -62),
				AnchorPoint = Vector2.new(1, 1),
				Align = "Center",
				TextSize = 13,
				Color = Theme.Warn,
			})
			else nil,
	})
end

-- A game pass: a coloured card with a big icon, its benefits and the price, or OWNED.
local function PassCard(props: {
	Key: string,
	Owned: boolean,
	Buyable: boolean,
	Order: number,
	OnBuy: () -> (boolean, string?),
})
	local pass = Passes.LIST[props.Key] :: any
	local style: { Icon: string, Colour: Color3, TextSize: number? } = PASS_STYLE[props.Key]
		or { Icon = "•", Colour = Theme.Accent }
	local message, setMessage = React.useState(nil :: string?)
	return e(C.Panel, {
		Size = UDim2.fromOffset(PASS_W, PASS_H),
		Padding = 16,
		LayoutOrder = props.Order,
		StrokeColor = if props.Owned then Theme.Good else style.Colour,
		Color = UNDER_WASH,
	}, {
		Wash = wash(style.Colour, if props.Owned then 0.1 else 0.25),
		Icon = e(C.Label, {
			Text = style.Icon,
			Size = UDim2.fromOffset(44, 44),
			Heavy = true,
			TextSize = style.TextSize or 38,
			Align = "Center",
			Color = style.Colour,
		}),
		Title = e(C.Label, {
			Text = pass.DisplayName,
			Size = UDim2.new(1, -52, 0, 26),
			Position = UDim2.fromOffset(52, 0),
			Heavy = true,
			TextSize = 20,
			Color = Theme.Text,
		}),
		Kind = e(C.Label, {
			Text = "GAME PASS  ·  ONE-TIME",
			Size = UDim2.new(1, -52, 0, 16),
			Position = UDim2.fromOffset(52, 26),
			Bold = true,
			TextSize = 11,
			Color = style.Colour,
		}),
		Benefits = e("Frame", {
			Size = UDim2.new(1, 0, 0, 100),
			Position = UDim2.fromOffset(0, 58),
			BackgroundTransparency = 1,
		}, bullets(message and { message } or pass.Benefits, style.Colour, 14)),
		Action = if props.Owned
			then e(C.Label, {
				Text = "OWNED  ✓",
				Size = UDim2.new(1, 0, 0, 42),
				Position = UDim2.new(0, 0, 1, -42),
				Bold = true,
				TextSize = 16,
				Align = "Center",
				Color = Theme.Good,
			})
			elseif props.Buyable then e(C.Button, {
				Text = `R$ {pass.Price}`,
				Style = "Primary",
				Color = style.Colour,
				TextColor = Theme.Background,
				Size = UDim2.new(1, 0, 0, 42),
				Position = UDim2.new(0, 0, 1, -42),
				TextSize = 18,
				OnClick = function()
					local ok, err = props.OnBuy()
					setMessage(if ok then nil else err)
				end,
			})
			else e(C.Label, {
				Text = "Coming soon",
				Size = UDim2.new(1, 0, 0, 42),
				Position = UDim2.new(0, 0, 1, -42),
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

-- Cards that wrap onto as many lines as they need
local function grid(order: number, cards: { [string]: any })
	cards.Layout = e("UIGridLayout", {
		CellSize = UDim2.fromOffset(CARD_W, CARD_H),
		CellPadding = UDim2.fromOffset(14, 14),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	return e("Frame", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, cards)
end

local KIND_DETAIL = {
	Camo = "Paints every jet you fly. Take it off to go back to each jet's own skin.",
	Trail = "Your contrails in this colour, and display smoke from the wingtips on afterburner.",
	Marker = "Your kill markers painted like this.",
	HUD = "Your HUD in this colour.",
	WingArt = "Painted on top of both wings.",
}

-- One cosmetic: buy it, equip it, or take it off.
local function cosmeticCard(props: any, data: any, id: string, order: number)
	local item = Catalogue.LIST[id]
	local owned = Cosmetics.owns(data, id)
	local equipped = Cosmetics.equipped(data, item.Kind) == id
	local action, status, onClick
	if not Cosmetics.ready(id) then
		status = "Coming soon"
	elseif equipped then
		action = "EQUIPPED (TAKE OFF)"
		onClick = function()
			return props.OnEquipCosmetic(item.Kind, "")
		end
	elseif owned then
		action = "EQUIP"
		onClick = function()
			return props.OnEquipCosmetic(item.Kind, id)
		end
	elseif item.Wings then
		action = `{C.number(item.Wings)} WINGS`
		onClick = function()
			return props.OnBuyCosmetic(id)
		end
	else
		status = if item.Pass == "VIP" then "Free with VIP Pilot" else "Not for sale"
	end
	local colour = if item.Colours then item.Colours[1] else item.Colour
	return e(Card, {
		Title = if item.Glyph then `{item.DisplayName}  {string.rep(item.Glyph, 3)}` else item.DisplayName,
		Detail = KIND_DETAIL[item.Kind],
		Action = action,
		Status = status,
		Highlight = if equipped then Theme.Good else colour,
		Image = if item.Images then item.Images[1] else nil,
		Order = order,
		OnClick = onClick,
	})
end

local function clock(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function ShopScreen(props: any)
	local data = props.Data
	-- Tick once a second so running boosters count down
	local now, setNow = React.useState(os.time())
	React.useEffect(function()
		local running = true
		task.spawn(function()
			while running do
				task.wait(1)
				setNow(os.time())
			end
		end)
		return function()
			running = false
		end
	end, {})
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
			Text = `Wings buy the cosmetics below. Every skin sold for Credits can also be bought straight away for {Skins.WINGS_PRICE} Wings on its jet's page.`,
			Size = UDim2.new(1, 0, 0, 18),
			TextSize = 14,
			Color = Theme.Dim,
			LayoutOrder = 12,
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
			Ribbon = if i == #packs then "BEST VALUE" else nil, -- the most Wings per Robux
			Action = if Products.idFor(key) then `R$ {product.Price}` else nil,
			Highlight = Theme.Wings,
			Order = i,
			OnClick = function()
				return props.OnBuyProduct(key)
			end,
		})
	end
	children.Packs = row(11, packCards)

	-- Cosmetics (SHP-07), a section per kind
	for k, kind in Catalogue.KINDS do
		children[kind .. "Title"] = section(string.upper(Catalogue.KIND_NAMES[kind]), 12 + k * 2)
		local cards = {}
		for i, id in Catalogue.ofKind(kind) do
			cards[id] = cosmeticCard(props, data, id, i)
		end
		children[kind] = grid(13 + k * 2, cards)
	end

	-- Tier Unlock: the next one, if there is one
	local offer = Shop.tierUnlockOffer(data)
	children.UnlockTitle = section("SKIP AHEAD", 7)
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
	children.Unlock = row(8, unlockCards)

	-- Boosters (SHP-03): an hour of double Credits or RP; buying another adds an hour
	children.BoosterTitle = section("BOOSTERS", 5)
	local boosterCards = {}
	for i, key in { "CreditsBooster", "RPBooster" } do
		local product = Products.LIST[key]
		local left = Perks.boosterLeft(data, product.Booster :: string, now)
		boosterCards[key] = e(Card, {
			Title = if product.Booster == "Credits" then "2x Credits" else "2x RP",
			Detail = if left > 0
				then `Running: {clock(left)} left. Another adds an hour.`
				else `Double the {if product.Booster == "Credits" then "Credits" else "research points"} from every match for an hour.`,
			Action = if Products.idFor(key) then `R$ {product.Price}` else nil,
			Highlight = if left > 0 then Theme.Good else nil,
			Order = i,
			OnClick = function()
				return props.OnBuyProduct(key)
			end,
		})
	end
	children.Boosters = row(6, boosterCards)

	-- VIP Pilot up top, then every pass as a big card (owned ones last)
	local function owns(key: string): boolean
		return Players.LocalPlayer:GetAttribute(Passes.attribute(key)) == true
	end
	children.Vip = e(VipBanner, {
		Owned = owns("VIP"),
		Buyable = Passes.idFor("VIP") ~= nil,
		Order = 2,
		OnBuy = function()
			return props.OnBuyPass("VIP")
		end,
	})
	children.PassTitle = section("GAME PASSES  ·  BUY ONCE, KEEP FOREVER", 3)
	local passCards = {}
	for i, key in PASS_ORDER do
		passCards[key] = e(PassCard, {
			Key = key,
			Owned = owns(key),
			Buyable = Passes.idFor(key) ~= nil,
			Order = if owns(key) then 10 + i else i,
			OnBuy = function()
				return props.OnBuyPass(key)
			end,
		})
	end
	passCards.Layout = C.List({ Horizontal = true, Gap = 14 })
	children.Passes =
		e("Frame", { Size = UDim2.new(1, 0, 0, PASS_H), BackgroundTransparency = 1, LayoutOrder = 4 }, passCards)

	-- Still to come (DESIGN §8.2)
	children.SoonTitle = section("COMING LATER", 40)
	children.Soon = row(41, {
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
