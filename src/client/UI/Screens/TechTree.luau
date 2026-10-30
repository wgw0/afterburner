--!strict
-- Tech tree (UI-03): three branch columns by tier. Each jet shows its state (locked, researchable,
-- researched, owned), RP progress toward research, its costs, and Research / Buy buttons. Every action
-- waits for the server and shows its answer. Above the tree, the Tier Unlock (DESIGN §8.2): skip to the next
-- tier for Robux by picking two of its jets.
-- props: Data, OnResearch(id) -> (ok, err), OnBuy(id) -> (ok, err), OnDetails(id),
--   OnChooseTierUnlock(picks) -> (ok, err)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local TechTree = require(Shared.TechTree)
local LiveConfig = require(Shared.LiveConfig)
local Products = require(Shared.Config.Products)
local Shop = require(Shared.Shop)

local UI = script.Parent.Parent
local C = require(UI.Components)
local Theme = require(UI.Theme)

local e = React.createElement
local TIER_NAMES = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII" }
local BRANCH_NAMES = { NATO = "NATO / US", East = "SOVIET / RUSSIA", Europe = "EUROPE" }
local CARD_H = 150
local UNLOCK_H = 76 -- the Tier Unlock banner, closed
local TIERS_W, COLUMN_W, GAP_X = 90, 290, 18 -- the tier labels, each region's column, the gap between them
local UNLOCK_OPEN_H = 160

-- RP available toward a node: the best owned prerequisite's RP plus the free pool.
local function availableRP(data: any, node: TechTree.Node): number
	local best = 0
	for _, req in node.Requires do
		local entry = data.Aircraft[req]
		if entry and entry.Owned then
			best = math.max(best, entry.RP)
		end
	end
	return best + data.FreeRP
end

local function nodeState(data: any, node: TechTree.Node): string
	local entry = data.Aircraft[node.Id]
	if entry and entry.Owned then
		return "Owned"
	elseif entry and entry.Researched then
		return "Researched"
	end
	for _, req in node.Requires do
		local owned = data.Aircraft[req]
		if owned and owned.Owned then
			return "Researchable"
		end
	end
	return "Locked"
end

local function NodeCard(props: any)
	local node: TechTree.Node, data = props.Node, props.Data
	local airframe = AircraftData.get(node.Id) :: any
	local pending, setPending = React.useState(false)
	local message, setMessage = React.useState(nil :: string?)
	local state = nodeState(data, node)
	local stateColor = if state == "Owned"
		then Theme.Good
		elseif state == "Researched" then Theme.Accent
		elseif state == "Researchable" then Theme.Warn
		else Theme.Locked

	local function run(action: (string) -> (boolean, string?))
		setPending(true)
		setMessage(nil)
		task.spawn(function()
			local ok, err = action(node.Id)
			setPending(false)
			setMessage(if ok then nil else err or "Refused")
		end)
	end

	local children: { [string]: any } = {
		Name = e(C.Label, {
			Text = airframe and airframe.DisplayName or node.Id,
			Size = UDim2.new(1, -90, 0, 22),
			Position = UDim2.fromOffset(12, 10),
			Bold = true,
			TextSize = 16,
		}),
		BR = e(C.Label, {
			Text = `BR {airframe and LiveConfig.battleRating(node.Id) or "?"}`,
			Size = UDim2.new(1, -24, 0, 18),
			Position = UDim2.fromOffset(12, 34),
			Color = Theme.Dim,
			TextSize = 13,
		}),
	}
	children.State = e("Frame", {
		Size = UDim2.fromOffset(100, 20),
		Position = UDim2.new(1, -110, 0, 11),
		BackgroundTransparency = 1,
	}, {
		Pill = e(C.Pill, {
			Text = string.upper(state),
			Color = Theme.Background,
			TextColor = stateColor,
			Size = UDim2.fromScale(1, 1),
		}),
	})

	if state == "Researchable" or state == "Locked" then
		local have = availableRP(data, node)
		children.Progress = e(C.Bar, {
			Value = if node.RP > 0 then have / node.RP else 1,
			Size = UDim2.new(1, -24, 0, 14),
			Position = UDim2.fromOffset(12, 60),
			Color = if have >= node.RP then Theme.Good else Theme.Warn,
			Text = `{C.number(math.min(have, node.RP))} / {C.number(node.RP)} RP`,
		})
		children.Cost = e(C.Label, {
			Text = `Then {C.number(node.Credits)} Credits to buy`,
			Size = UDim2.new(1, -24, 0, 16),
			Position = UDim2.fromOffset(12, 78),
			Color = Theme.Dim,
			TextSize = 12,
		})
		children.Action = e(C.Button, {
			Text = "RESEARCH",
			Style = "Primary",
			Size = UDim2.new(1, -24, 0, 40),
			Position = UDim2.fromOffset(12, 100),
			TextSize = 14,
			Pending = pending,
			Disabled = state == "Locked" or have < node.RP,
			OnClick = function()
				run(props.OnResearch)
			end,
		})
	elseif state == "Researched" then
		children.Cost = e(C.Label, {
			Text = `{C.number(node.Credits)} Credits  ·  you have {C.number(data.Credits)}`,
			Size = UDim2.new(1, -24, 0, 18),
			Position = UDim2.fromOffset(12, 64),
			Color = if data.Credits >= node.Credits then Theme.Text else Theme.Bad,
			TextSize = 13,
		})
		children.Action = e(C.Button, {
			Text = `BUY  ·  {C.number(node.Credits)} Cr`,
			Style = "Primary",
			Size = UDim2.new(1, -24, 0, 40),
			Position = UDim2.fromOffset(12, 100),
			TextSize = 14,
			Pending = pending,
			Disabled = data.Credits < node.Credits,
			OnClick = function()
				run(props.OnBuy)
			end,
		})
	else
		local entry = data.Aircraft[node.Id]
		children.RP = e(C.Label, {
			Text = `{C.number(entry.RP)} RP earned in this jet`,
			Size = UDim2.new(1, -24, 0, 18),
			Position = UDim2.fromOffset(12, 64),
			Color = Theme.Good,
			TextSize = 13,
		})
		children.Action = e(C.Button, {
			Text = "DETAILS & MODULES",
			Style = "Ghost",
			Size = UDim2.new(1, -24, 0, 40),
			Position = UDim2.fromOffset(12, 100),
			TextSize = 14,
			OnClick = function()
				props.OnDetails(node.Id)
			end,
		})
	end
	if message then
		children.Message = e(C.Label, {
			Text = message,
			Size = UDim2.new(1, -24, 0, 16),
			Position = UDim2.fromOffset(12, 82),
			Color = Theme.Bad,
			TextSize = 12,
		})
	end

	return e(C.Panel, {
		Size = UDim2.new(1, 0, 0, CARD_H),
		LayoutOrder = props.Order,
		Color = if state == "Locked" then Theme.Background else Theme.Panel,
		StrokeColor = stateColor,
	}, children)
end

-- The Tier Unlock: closed, a banner with the price; open, the next tier's jets to pick two from and BUY.
local function TierUnlock(props: {
	Data: any,
	Offer: Shop.Offer,
	Open: boolean,
	SetOpen: (boolean) -> (),
	OnChoose: ({ string }) -> (boolean, string?),
})
	local offer = props.Offer
	local product = Products.LIST[Products.tierUnlockKey(offer.tier) :: string]
	local open, setOpen = props.Open, props.SetOpen
	local picks, setPicks = React.useState({} :: { string })
	local pending, setPending = React.useState(false)
	local message, setMessage = React.useState(nil :: string?)
	local tierName = TIER_NAMES[offer.tier]

	local children: { [string]: any } = {
		Title = e(C.Label, {
			Text = `SKIP AHEAD: UNLOCK TIER {tierName}`,
			Size = UDim2.new(0.6, 0, 0, 22),
			Heavy = true,
			TextSize = 18,
			Color = Theme.Accent,
		}),
		Text = e(C.Label, {
			Text = `Pick {Products.UNLOCK_JETS} Tier {tierName} jets to own straight away, then carry on researching from there. One tier at a time, up to Tier V.`,
			Size = UDim2.new(0.7, 0, 0, 18),
			Position = UDim2.fromOffset(0, 26),
			TextSize = 13,
			Color = Theme.Dim,
		}),
		Toggle = e(C.Button, {
			Text = if open then "CLOSE" else `CHOOSE JETS  ·  R$ {product.Price}`,
			Style = if open then "Ghost" else "Primary",
			Size = UDim2.fromOffset(220, 36),
			Position = UDim2.new(1, -220, 0, 0),
			TextSize = 14,
			OnClick = function()
				setOpen(not open)
				setMessage(nil)
			end,
		}),
	}
	if open then
		local row: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = 8, AlignY = "Center" }) }
		for i, id in offer.jets do
			local airframe = AircraftData.get(id)
			local chosen = table.find(picks, id) ~= nil
			row[id] = e(C.Button, {
				Text = if airframe then airframe.DisplayName else id,
				Style = if chosen then "Primary" else "Ghost",
				Size = UDim2.fromOffset(170, 36),
				TextSize = 13,
				LayoutOrder = i,
				OnClick = function()
					local nextPicks = table.clone(picks)
					local at = table.find(nextPicks, id)
					if at then
						table.remove(nextPicks, at)
					elseif #nextPicks < Products.UNLOCK_JETS then
						table.insert(nextPicks, id)
					end
					setPicks(nextPicks)
					setMessage(nil)
				end,
			})
		end
		row.Buy = e(C.Button, {
			Text = `BUY  ·  R$ {product.Price}`,
			Style = "Primary",
			Size = UDim2.fromOffset(150, 36),
			TextSize = 14,
			Pending = pending,
			Disabled = #picks ~= Products.UNLOCK_JETS,
			LayoutOrder = 99,
			OnClick = function()
				setPending(true)
				task.spawn(function()
					local ok, err = props.OnChoose(picks)
					setPending(false)
					setMessage(
						if ok then "Complete the purchase in the Roblox window" else err or "Try again in a moment."
					)
				end)
			end,
		})
		children.Jets = e("Frame", {
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, 54),
			BackgroundTransparency = 1,
		}, row)
		children.Message = e(C.Label, {
			Text = message
				or `{#picks} of {Products.UNLOCK_JETS} picked. They're yours to fly and upgrade; the rest of the tier is researched as usual.`,
			Size = UDim2.new(1, 0, 0, 18),
			Position = UDim2.fromOffset(0, 102),
			TextSize = 13,
			Color = Theme.Dim,
		})
	end
	return e(C.Panel, {
		Size = UDim2.fromOffset(1000, (if open then UNLOCK_OPEN_H else UNLOCK_H) - 10),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Padding = 12,
		StrokeColor = Theme.Accent,
	}, children)
end

local function TechTreeScreen(props: any)
	local data = props.Data
	local offer = Shop.tierUnlockOffer(data)
	local bannerOpen, setBannerOpen = React.useState(false)
	local top = if offer then (if bannerOpen then UNLOCK_OPEN_H else UNLOCK_H) else 0
	local columns: { [string]: any } = {
		Layout = C.List({ Horizontal = true, Gap = GAP_X, Align = "Center" }),
	}
	-- Each tier's row is as tall as its tallest branch (several jets in a tier stack in one row)
	local rowHeight: { [number]: number } = {}
	local total = 30
	for tier = 1, TechTree.MAX_TIER do
		local most = 1
		for _, branch in TechTree.BRANCHES do
			local count = 0
			for _, node in TechTree.branch(branch) do
				if node.Tier == tier then
					count += 1
				end
			end
			most = math.max(most, count)
		end
		rowHeight[tier] = most * CARD_H + (most - 1) * 8
		total += 14 + rowHeight[tier]
	end
	-- Tier labels down the left
	local tiers: { [string]: any } = { Layout = C.List({ Gap = 14 }) }
	tiers.Head = e(C.Label, { Text = "", Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 0 })
	for tier = 1, TechTree.MAX_TIER do
		tiers[`T{tier}`] = e(C.Label, {
			Text = `TIER {TIER_NAMES[tier]}`,
			Size = UDim2.new(1, 0, 0, rowHeight[tier]),
			Color = Theme.Dim,
			Heavy = true,
			TextSize = 18,
			Align = "Center",
			LayoutOrder = tier,
		})
	end
	columns.Tiers =
		e("Frame", { Size = UDim2.new(0, TIERS_W, 1, 0), BackgroundTransparency = 1, LayoutOrder = 0 }, tiers)
	for i, branch in TechTree.BRANCHES do
		local cards: { [string]: any } = { Layout = C.List({ Gap = 14 }) }
		cards.Head = e(C.Label, {
			Text = BRANCH_NAMES[branch] or branch,
			Size = UDim2.new(1, 0, 0, 30),
			Bold = true,
			Color = Theme.Accent,
			Align = "Center",
			TextSize = 16,
			LayoutOrder = 0,
		})
		-- One row per tier; several jets in a tier share the row
		for tier = 1, TechTree.MAX_TIER do
			local row: { [string]: any } = { Layout = C.List({ Gap = 8 }) }
			local count = 0
			for _, node in TechTree.branch(branch) do
				if node.Tier == tier then
					count += 1
					row[node.Id] = e(NodeCard, {
						Node = node,
						Data = data,
						Order = count,
						OnResearch = props.OnResearch,
						OnBuy = props.OnBuy,
						OnDetails = props.OnDetails,
					})
				end
			end
			cards[`T{tier}`] = e("Frame", {
				Size = UDim2.new(1, 0, 0, rowHeight[tier]),
				BackgroundTransparency = 1,
				LayoutOrder = tier,
			}, row)
		end
		columns[branch] =
			e("Frame", { Size = UDim2.new(0, COLUMN_W, 1, 0), BackgroundTransparency = 1, LayoutOrder = i }, cards)
	end

	-- Faint grey lines between the region columns (and the tier labels) and between the tier rows, in the
	-- gaps between the cards: the same width as the columns' row, centred like it. Default ZIndex: at 0 they'd
	-- sit under the menu's dark backdrop (ZIndexBehavior Global) and barely show.
	local width = TIERS_W + #TechTree.BRANCHES * (COLUMN_W + GAP_X)
	local lines: { [string]: any } = {}
	local function line(name: string, position: UDim2, size: UDim2)
		lines[name] = e("Frame", {
			Position = position,
			Size = size,
			BackgroundColor3 = Theme.Stroke,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
		})
	end
	for i = 0, #TechTree.BRANCHES - 1 do
		local x = TIERS_W + GAP_X / 2 + i * (COLUMN_W + GAP_X)
		line(`V{i}`, UDim2.fromOffset(x - 1, 30), UDim2.fromOffset(2, total - 30))
	end
	local y = 30
	for tier = 1, TechTree.MAX_TIER - 1 do
		y += 14 + rowHeight[tier]
		line(`H{tier}`, UDim2.fromOffset(0, y + 6), UDim2.fromOffset(width, 2))
	end

	return e("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, {
		Padding = e("UIPadding", { PaddingTop = UDim.new(0, 20), PaddingBottom = UDim.new(0, 20) }),
		Unlock = if offer
			then e(TierUnlock, {
				Data = data,
				Offer = offer,
				Open = bannerOpen,
				SetOpen = setBannerOpen,
				OnChoose = props.OnChooseTierUnlock,
			})
			else nil,
		Grid = e("Frame", {
			Size = UDim2.fromOffset(width, total),
			Position = UDim2.new(0.5, 0, 0, top),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
		}, lines),
		Row = e("Frame", {
			Size = UDim2.new(1, 0, 0, total),
			Position = UDim2.fromOffset(0, top),
			BackgroundTransparency = 1,
		}, columns),
		Hint = e(C.Label, {
			Text = `Free RP: {C.number(data.FreeRP)}  ·  Research spends RP from the best jet you own that leads to it, then free RP.`,
			Size = UDim2.new(1, 0, 0, 20),
			Position = UDim2.fromOffset(0, top + total + 16), -- below everything
			Align = "Center",
			Color = Theme.Dim,
			TextSize = 13,
		}),
	})
end

return TechTreeScreen
