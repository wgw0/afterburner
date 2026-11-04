--!strict
-- Shop (UI-07; DESIGN §8; layout for conversion in DEVELOPMENT.md §27.9). Top to bottom: VIP Pilot as a
-- banner (or a thank-you once owned), the game passes still to buy as big cards with their benefits,
-- boosters, the next Tier Unlock (while there is one), Wings packs, cosmetics bought with Wings (SHP-07: buy,
-- equip, take off), the passes you own in one line, then what's coming. Rows wrap on narrow screens. Every
-- price is shown before the purchase window; nothing is random or on a fake timer. A product or pass that
-- isn't created on the dashboard yet says "Coming soon" instead of a buy button. What's still to come (the
-- season pass, the starter bundle, premium jets) is listed at the bottom.
-- The Starter Bundle (once per player) sits under the VIP banner until it's bought; the season pass and this
-- week's bundle (SHP-05, LIV-04) have their own panels.
-- props: Data, OnBuyProduct(key) -> (ok, err), OnBuyPass(key) -> (ok, err), OnTechTree(), OnSeason(),
--   OnBuyCosmetic(id) -> (ok, err), OnEquipCosmetic(kind, id) -> (ok, err), OnChooseStarter(camoId) -> (ok, err),
--   OnBuyBundle(bundleId) -> (ok, err)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalogue = require(Shared.Config.Cosmetics)
local Cosmetics = require(Shared.Cosmetics)
local Passes = require(Shared.Config.Passes)
local Perks = require(Shared.Perks)
local Products = require(Shared.Config.Products)
local Season = require(Shared.Season)
local Seasons = require(Shared.Config.Seasons)
local Shop = require(Shared.Shop)
local Skins = require(Shared.Skins)

local UI = script.Parent.Parent
local C = require(UI.Components)
local Theme = require(UI.Theme)

local e = React.createElement
local TIER_NAMES = { "I", "II", "III", "IV", "V" }
local CARD_W, CARD_H = 230, 150
local BANNER_H = 112 -- a camo card's picture, across the top

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
		Banner: string?, -- a big picture across the top (camos: the jet in it, on a transparent background)
		Ribbon: string?, -- a tag in the top right ("BEST VALUE")
		Order: number,
		OnClick: (() -> (boolean, string?))?,
	}
)
	local message, setMessage = React.useState(nil :: string?)
	local top = if props.Banner then BANNER_H + 8 else 0 -- everything else moves down under the banner
	return e(C.Panel, {
		Size = UDim2.fromOffset(CARD_W, CARD_H + top),
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
		Banner = if props.Banner
			then e("Frame", {
				Size = UDim2.new(1, 0, 0, BANNER_H),
				BackgroundColor3 = Theme.Background,
			}, {
				Corner = C.corner(8),
				-- A soft glow in the card's colour behind the jet, so pale camos stand off the dark
				Glow = e("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = props.Highlight or Theme.Accent,
					BackgroundTransparency = 0.82,
				}, {
					Corner = C.corner(8),
					Gradient = e("UIGradient", {
						Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, 0.2),
							NumberSequenceKeypoint.new(1, 1),
						}),
						Rotation = 90,
					}),
				}),
				Jet = e("ImageLabel", {
					Image = props.Banner,
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					ScaleType = Enum.ScaleType.Fit,
				}),
			})
			else nil,
		Title = e(C.Label, {
			Text = props.Title,
			Position = UDim2.fromOffset(0, top),
			Size = UDim2.new(1, if props.Image then -68 else 0, 0, 24),
			Heavy = true,
			TextSize = 20,
			Color = props.Highlight or Theme.Text,
		}),
		Detail = e(C.Label, {
			Text = message or props.Detail,
			Size = UDim2.new(1, 0, 0, 52),
			Position = UDim2.fromOffset(0, top + 30),
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

-- A game pass still to buy: a coloured card with a big icon, its benefits and the price.
local function PassCard(props: {
	Key: string,
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
		StrokeColor = style.Colour,
		Color = UNDER_WASH,
	}, {
		Wash = wash(style.Colour, 0.25),
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
		Action = if props.Buyable
			then e(C.Button, {
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

-- Cards that wrap onto as many lines as they need (taller ones for camos, which carry a banner; wider ones
-- for the passes), so a narrow screen stacks them instead of cutting them off
local function grid(order: number, cards: { [string]: any }, height: number?, width: number?)
	cards.Layout = e("UIGridLayout", {
		CellSize = UDim2.fromOffset(width or CARD_W, height or CARD_H),
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
		action = "TAKE OFF"
		onClick = function()
			return props.OnEquipCosmetic(item.Kind, "")
		end
	elseif owned then
		action = "EQUIP"
		onClick = function()
			return props.OnEquipCosmetic(item.Kind, id)
		end
	elseif item.Wings then
		action = `BUY · {C.number(item.Wings)} WINGS`
		onClick = function()
			return props.OnBuyCosmetic(id)
		end
	else
		status = if item.Pass == "VIP" then "Free with VIP Pilot" else "Not for sale"
	end
	local colour = if item.Colours then item.Colours[1] else item.Colour
	return e(Card, {
		Title = if item.Glyph then `{item.DisplayName}  {string.rep(item.Glyph, 3)}` else item.DisplayName,
		Detail = if equipped then "✓ Equipped" else KIND_DETAIL[item.Kind],
		Action = action,
		Status = status,
		Highlight = if equipped then Theme.Good else colour,
		Image = if item.Images and item.Kind ~= "Camo" then item.Images[1] else nil,
		Banner = if item.Images and item.Kind == "Camo" then item.Images[1] else nil,
		Order = order,
		OnClick = onClick,
	})
end

local STARTER = Color3.fromRGB(120, 230, 180)

-- The Starter Bundle: pick a camo from the strip, then buy. Shown until it's bought.
local function StarterBanner(props: { Camos: { string }, Order: number, OnChoose: (string) -> (boolean, string?) })
	local picked, setPicked = React.useState(props.Camos[1] or "")
	local message, setMessage = React.useState(nil :: string?)
	local strip: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = 8 }) }
	for i, id in props.Camos do
		local item = Catalogue.LIST[id]
		strip[id] = e("ImageButton", {
			Image = if item.Images then item.Images[1] else "",
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(120, 64),
			BackgroundColor3 = Theme.Background,
			AutoButtonColor = true,
			LayoutOrder = i,
			[React.Event.Activated] = function()
				setPicked(id)
			end,
		}, {
			Corner = C.corner(8),
			Stroke = if picked == id then C.stroke(STARTER, 2) else nil,
			Name = e(C.Label, {
				Text = item.DisplayName,
				Size = UDim2.new(1, 0, 0, 14),
				Position = UDim2.new(0, 0, 1, -14),
				TextSize = 11,
				Bold = true,
				Align = "Center",
				Color = if picked == id then STARTER else Theme.Dim,
			}),
		})
	end
	local camoWings = if picked ~= "" then Catalogue.LIST[picked].Wings or 0 else 0
	local boosterRobux = Products.LIST.CreditsBooster.Price * Shop.STARTER.BoosterHours
	return e(C.Panel, {
		Size = UDim2.new(1, 0, 0, 186),
		Padding = 18,
		LayoutOrder = props.Order,
		StrokeColor = STARTER,
		Color = UNDER_WASH,
	}, {
		Wash = wash(STARTER, 0.22),
		Ribbon = e(C.Pill, {
			Text = "ONCE ONLY",
			Size = UDim2.fromOffset(100, 22),
			Position = UDim2.fromScale(1, 0),
			AnchorPoint = Vector2.new(1, 0),
			Color = STARTER,
			TextColor = Theme.Background,
		}),
		Title = e(C.Label, {
			Text = "STARTER BUNDLE",
			Size = UDim2.new(0.5, 0, 0, 30),
			Heavy = true,
			TextSize = 26,
			Color = STARTER,
		}),
		Contents = e(C.Label, {
			Text = `{if #props.Camos > 0 then "A camo you pick" else "A camo's worth of Wings (you own every camo)"}  ·  {Shop.STARTER.BoosterHours} hours of 2x Credits  ·  {Shop.STARTER.Wings} Wings`,
			Size = UDim2.new(0.6, 0, 0, 18),
			Position = UDim2.fromOffset(0, 34),
			Bold = true,
			TextSize = 14,
		}),
		Worth = e(C.Label, {
			Text = `On their own: {C.number(camoWings + Shop.STARTER.Wings)} Wings and R$ {boosterRobux} of boosters.`,
			Size = UDim2.new(0.6, 0, 0, 16),
			Position = UDim2.fromOffset(0, 56),
			TextSize = 13,
			Color = Theme.Dim,
		}),
		Strip = e("Frame", {
			Size = UDim2.new(1, -300, 0, 64),
			Position = UDim2.new(0, 0, 1, -64),
			BackgroundTransparency = 1,
		}, strip),
		Buy = if Products.idFor("Starter")
			then e(C.Button, {
				Text = `GET IT  ·  R$ {Products.LIST.Starter.Price}`,
				Style = "Primary",
				Color = STARTER,
				TextColor = Theme.Background,
				Size = UDim2.fromOffset(260, 52),
				Position = UDim2.fromScale(1, 1),
				AnchorPoint = Vector2.new(1, 1),
				TextSize = 18,
				OnClick = function()
					local ok, err = props.OnChoose(picked)
					setMessage(if ok then nil else err)
				end,
			})
			else e(C.Label, {
				Text = "Coming soon",
				Size = UDim2.fromOffset(260, 52),
				Position = UDim2.fromScale(1, 1),
				AnchorPoint = Vector2.new(1, 1),
				Align = "Center",
				Color = Theme.Dim,
			}),
		Message = if message
			then e(C.Label, {
				Text = message,
				Size = UDim2.fromOffset(260, 16),
				Position = UDim2.new(1, 0, 1, -58),
				AnchorPoint = Vector2.new(1, 1),
				Align = "Center",
				TextSize = 13,
				Color = Theme.Warn,
			})
			else nil,
	})
end

-- The season pass: where you are and what it costs; the Season tab has the track.
local function SeasonPanel(props: { Data: any, Order: number, OnSeason: () -> () })
	local now = workspace:GetServerTimeNow()
	local season = Seasons.at(now)
	local saved = props.Data.Season or Season.newState()
	local premium = season ~= nil and saved.Id == season.Id and saved.Premium == true
	local detail
	if not season then
		detail = "The next season is coming soon."
	elseif premium then
		detail = `You have the premium pass. Tier {Season.tierFor(saved.XP)} of {Seasons.TIERS}.`
	else
		detail = `{Seasons.TIERS} tiers of rewards; premium adds season-only cosmetics and gives back most of its `
			.. `price in Wings. {C.number(Seasons.PASS_WINGS)} Wings or R$ {Products.LIST.SeasonPass.Price}.`
	end
	return e(C.Panel, {
		Size = UDim2.new(1, 0, 0, 84),
		Padding = 16,
		LayoutOrder = props.Order,
		StrokeColor = GOLD,
	}, {
		Title = e(C.Label, {
			Text = if season then `SEASON PASS  ·  {string.upper(season.Name)}` else "SEASON PASS",
			Size = UDim2.new(1, -240, 0, 24),
			Heavy = true,
			TextSize = 20,
			Color = GOLD,
		}),
		Detail = e(C.Label, {
			Text = detail,
			Size = UDim2.new(1, -240, 0, 30),
			Position = UDim2.fromOffset(0, 26),
			TextSize = 13,
			Wrap = true,
			AlignY = "Top",
			Color = Theme.Dim,
		}),
		Open = e(C.Button, {
			Text = if premium or not season then "SEE THE SEASON" else "SEE THE PASS",
			Style = "Primary",
			Color = GOLD,
			TextColor = Theme.Background,
			Size = UDim2.fromOffset(220, 44),
			Position = UDim2.fromScale(1, 0.5),
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = 15,
			OnClick = props.OnSeason,
		}),
	})
end

-- This week's featured bundle: its items, what it would cost you (owned items aren't charged) and the day it
-- changes (a real date, not a countdown to pressure anyone).
local function BundlePanel(props: { Data: any, Order: number, OnBuy: (string) -> (boolean, string?) })
	local message, setMessage = React.useState(nil :: string?)
	local now = workspace:GetServerTimeNow()
	local bundle = Shop.bundleFor(now)
	local price, items, full = Shop.bundlePrice(props.Data, bundle)
	local names, camo = {}, nil
	for _, id in bundle.Items do
		local item = Catalogue.LIST[id]
		table.insert(names, if Cosmetics.owns(props.Data, id) then `<s>{item.DisplayName}</s>` else item.DisplayName)
		if item.Kind == "Camo" and item.Images then
			camo = item.Images[1]
		end
	end
	local left = if camo then 166 else 0 -- the text starts after the camo's picture
	local _, nextAt = Shop.week(now)
	local nextDay = os.date("!%A %d %B", nextAt)
	local action
	if #items == 0 then
		action = e(C.Label, {
			Text = "OWNED  ✓",
			Size = UDim2.fromOffset(220, 44),
			Position = UDim2.fromScale(1, 0.5),
			AnchorPoint = Vector2.new(1, 0.5),
			Bold = true,
			Align = "Center",
			Color = Theme.Good,
		})
	else
		action = e(C.Button, {
			Text = `{C.number(price)} WINGS`,
			Style = "Primary",
			Color = Theme.Wings,
			Size = UDim2.fromOffset(220, 44),
			Position = UDim2.fromScale(1, 0.5),
			AnchorPoint = Vector2.new(1, 0.5),
			TextSize = 16,
			OnClick = function()
				local ok, err = props.OnBuy(bundle.Id)
				setMessage(if ok then nil else err)
			end,
		})
	end
	local detail = if #items > 0
		then `{C.number(full - price)} Wings off the items on their own. Next bundle {nextDay}.`
		else `Next bundle {nextDay}.`
	return e(C.Panel, {
		Size = UDim2.new(1, 0, 0, 110),
		Padding = 14,
		LayoutOrder = props.Order,
		StrokeColor = Theme.Wings,
	}, {
		Picture = if camo
			then e("ImageLabel", {
				Image = camo,
				Size = UDim2.fromOffset(150, 82),
				BackgroundColor3 = Theme.Background,
				ScaleType = Enum.ScaleType.Fit,
			}, { Corner = C.corner(8) })
			else nil,
		Title = e(C.Label, {
			Text = `THIS WEEK  ·  {string.upper(bundle.DisplayName)} BUNDLE`,
			Size = UDim2.new(1, -(left + 250), 0, 24),
			Position = UDim2.fromOffset(left, 0),
			Heavy = true,
			TextSize = 20,
			Color = Theme.Wings,
		}),
		Items = e(C.Label, {
			Text = table.concat(names, "  ·  "),
			Rich = true,
			Size = UDim2.new(1, -(left + 250), 0, 18),
			Position = UDim2.fromOffset(left, 28),
			Bold = true,
			TextSize = 14,
		}),
		Detail = e(C.Label, {
			Text = message or detail,
			Size = UDim2.new(1, -(left + 250), 0, 32),
			Position = UDim2.fromOffset(left, 50),
			TextSize = 13,
			Wrap = true,
			AlignY = "Top",
			Color = if message then Theme.Warn else Theme.Dim,
		}),
		Action = action,
	})
end

local function clock(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function ShopScreen(props: any)
	local data = props.Data
	-- Opened at a section (props.Focus, e.g. "Wings" from the top bar's +): scroll its title to the top
	local scroller = React.useRef(nil)
	React.useEffect(function()
		local frame = scroller.current :: ScrollingFrame?
		if not (frame and props.Focus) then
			return nil
		end
		task.defer(function() -- once the layout has placed the sections
			local title = frame:FindFirstChild(`{props.Focus}Title`) :: GuiObject?
			if title then
				local y = title.AbsolutePosition.Y - frame.AbsolutePosition.Y + frame.CanvasPosition.Y - 8
				frame.CanvasPosition = Vector2.new(0, math.max(0, y))
			end
		end)
		return nil
	end, { props.FocusKey })
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
			LayoutOrder = 1,
		}),
	}
	-- The order (Will: usability and engagement): the headline offers, then what Wings buy (the cosmetics),
	-- then the season, Wings packs, passes, boosters and the skip-ahead

	-- Wings packs, smallest first
	children.WingsTitle = section("WINGS", 31)
	local packs = {}
	for key, product in Products.LIST do
		if product.Kind == "Wings" then
			table.insert(packs, key)
		end
	end
	table.sort(packs, function(a, b)
		return Products.LIST[a].Price < Products.LIST[b].Price
	end)
	-- The cheapest camo, so the smallest pack that covers one can say so
	local camoPrice = math.huge
	for _, item in Catalogue.LIST do
		if item.Kind == "Camo" and item.Wings then
			camoPrice = math.min(camoPrice, item.Wings)
		end
	end
	local camoPack = nil
	for _, key in packs do
		if (Products.LIST[key].Amount :: number) >= camoPrice then
			camoPack = key
			break
		end
	end
	local packCards = {}
	for i, key in packs do
		local product = Products.LIST[key]
		local base = Products.LIST[packs[1]]
		local perRobux = (product.Amount :: number) / product.Price
		local bonus = math.round((perRobux / ((base.Amount :: number) / base.Price) - 1) * 100)
		packCards[key] = e(Card, {
			Title = `{C.number(product.Amount :: number)} Wings`,
			Detail = (if bonus > 0 then `{bonus}% more Wings per Robux` else "Enough for one jet's skin")
				.. (if key == camoPack then "\nEnough for a camo on every jet" else ""),
			Ribbon = if i == #packs then "BEST VALUE" else nil, -- the most Wings per Robux
			Action = if Products.idFor(key) then `R$ {product.Price}` else nil,
			Highlight = Theme.Wings,
			Order = i,
			OnClick = function()
				return props.OnBuyProduct(key)
			end,
		})
	end
	children.Packs = grid(32, packCards)

	-- Cosmetics (SHP-07), a section per kind
	for k, kind in Catalogue.KINDS do
		children[kind .. "Title"] = section(string.upper(Catalogue.KIND_NAMES[kind]), 10 + k * 2)
		local cards = {}
		for i, id in Catalogue.ofKind(kind) do
			cards[id] = cosmeticCard(props, data, id, i)
		end
		children[kind] = grid(11 + k * 2, cards, if kind == "Camo" then CARD_H + BANNER_H + 8 else nil)
	end

	-- Tier Unlock: the next one, if there is one
	local offer = Shop.tierUnlockOffer(data)
	if offer then
		children.UnlockTitle = section("SKIP AHEAD", 37)
		local key = Products.tierUnlockKey(offer.tier) :: string
		children.Unlock = grid(38, {
			Next = e(Card, {
				Title = `Unlock Tier {TIER_NAMES[offer.tier]}`,
				Detail = `Pick {Products.UNLOCK_JETS} Tier {TIER_NAMES[offer.tier]} jets to own straight away. R$ {Products.LIST[key].Price}.`,
				Action = "PICK JETS",
				Order = 1,
				OnClick = function()
					props.OnTechTree()
					return true, nil
				end,
			}),
		})
	end

	-- Boosters (SHP-03): an hour of double Credits or RP; buying another adds an hour
	children.BoosterTitle = section("BOOSTERS", 35)
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
	children.Boosters = grid(36, boosterCards)

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
	local passCards, ownedNames = {}, {}
	for i, key in PASS_ORDER do
		if owns(key) then
			local style = PASS_STYLE[key]
			table.insert(
				ownedNames,
				`<font color="#{style.Colour:ToHex()}">{style.Icon}</font>  {Passes.LIST[key].DisplayName}`
			)
			continue
		elseif key == "VIP" then
			continue -- the banner above is its card
		end
		passCards[key] = e(PassCard, {
			Key = key,
			Buyable = Passes.idFor(key) ~= nil,
			Order = i,
			OnBuy = function()
				return props.OnBuyPass(key)
			end,
		})
	end
	if next(passCards) then
		children.PassTitle = section("GAME PASSES  ·  BUY ONCE, KEEP FOREVER", 33)
		children.Passes = grid(34, passCards, PASS_H, PASS_W)
	end
	if #ownedNames > 0 then
		children.Owned = e(C.Label, {
			Text = `<font color="#{Theme.Good:ToHex()}">YOUR PASSES  ✓</font>     {table.concat(ownedNames, "     ")}`,
			Rich = true,
			Size = UDim2.new(1, 0, 0, 24),
			Bold = true,
			TextSize = 15,
			Color = Theme.Text,
			LayoutOrder = 39,
		})
	end

	-- The Starter Bundle, once per player, under VIP
	local starter = Shop.starterOffer(data)
	if starter then
		children.Starter = e(StarterBanner, { Camos = starter, Order = 3, OnChoose = props.OnChooseStarter })
	end
	children.Season = e(SeasonPanel, { Data = data, Order = 30, OnSeason = props.OnSeason })
	children.Bundle = e(BundlePanel, { Data = data, Order = 4, OnBuy = props.OnBuyBundle })

	-- Still to come (DESIGN §8.2)
	children.SoonTitle = section("COMING LATER", 40)
	children.Soon = grid(41, {
		Premium = e(Card, { Title = "Premium Jets", Detail = "Named variants with a unique camo.", Order = 5 }),
	})

	return e("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ref = scroller,
	}, children)
end

return ShopScreen
