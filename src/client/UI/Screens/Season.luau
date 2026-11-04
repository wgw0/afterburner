--!strict
-- The SEASON tab (UI-08; the pass is Shared/Season, the seasons Config/Seasons): the season's name and time
-- left, your tier and XP into the next, the premium track's price (Wings or Robux) or PREMIUM ✓, a CLAIM
-- button for every reward reached, and the track: a column per tier with its free reward over its premium
-- one, scrolled to where you are. Today's and this week's challenges are on the right (they earn season XP).
-- props: Data, OnClaimSeason() -> (ok, msg), OnBuySeasonPass(how: "Wings" | "Robux") -> (ok, msg),
--   OnReroll(index) -> (ok, err)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalogue = require(Shared.Config.Cosmetics)
local LevelRewards = require(Shared.Config.LevelRewards)
local Products = require(Shared.Config.Products)
local Season = require(Shared.Season)
local Seasons = require(Shared.Config.Seasons)

local UI = script.Parent.Parent
local C = require(UI.Components)
local ChallengesPanel = require(UI.ChallengesPanel)
local Theme = require(UI.Theme)

local e = React.createElement
local COLUMN_W, CARD_H = 132, 116
local GOLD = Color3.fromRGB(255, 201, 60) -- the premium track

local function duration(seconds: number): string
	local hours = math.max(0, seconds) // 3600
	if hours >= 24 then
		return `{hours // 24}d {hours % 24}h`
	end
	return `{hours}h {(math.max(0, seconds) % 3600) // 60}m`
end

-- What a reward is, in a few words, and a picture or swatch for it.
local function describe(reward: Seasons.Reward): (string, any)
	local amount = C.number(reward.Amount or 0)
	if reward.Kind == "Credits" then
		return `{amount} Cr`, e(C.Label, { Text = "Cr", Heavy = true, TextSize = 26, Align = "Center" })
	elseif reward.Kind == "FreeRP" then
		return `{amount} free RP`,
			e(C.Label, { Text = "RP", Heavy = true, TextSize = 26, Align = "Center", Color = Theme.Good })
	elseif reward.Kind == "Wings" then
		return `{amount} Wings`,
			e(C.Label, { Text = "WINGS", Heavy = true, TextSize = 20, Align = "Center", Color = Theme.Wings })
	elseif reward.Kind == "Title" then
		return `"{LevelRewards.titleName(reward.Id :: string) or reward.Id}" title`,
			e(C.Label, { Text = "TITLE", Heavy = true, TextSize = 20, Align = "Center", Color = GOLD })
	end
	local item = Catalogue.get(reward.Id :: string)
	if not item then
		return tostring(reward.Id), nil
	end
	local kind = string.lower(Catalogue.KIND_NAMES[item.Kind]):gsub("s$", "")
	local name = `{item.DisplayName} {kind}`
	if item.Kind == "WingArt" and item.Images and item.Images[1] ~= "" then
		return name,
			e("ImageLabel", {
				Image = item.Images[1],
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ScaleType = Enum.ScaleType.Fit,
			})
	elseif item.Kind == "Marker" then
		return name,
			e(C.Label, {
				Text = string.rep(item.Glyph or "", 3),
				TextSize = 24,
				Align = "Center",
				Color = item.Colour,
			})
	end
	-- Contrails and HUD themes: their colours side by side
	local swatches: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = 4, Align = "Center" }) }
	for i, colour in item.Colours or {} do
		swatches[`S{i}`] = e("Frame", {
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = colour,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, { Corner = C.corner(11) })
	end
	return name, e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, swatches)
end

-- One reward on the track: claimed (✓), ready to claim (lit), still to reach, or premium and not bought.
local function RewardCard(props: {
	Reward: Seasons.Reward,
	State: "Claimed" | "Ready" | "Locked" | "Premium",
	Premium: boolean,
	Order: number,
})
	local text, picture = describe(props.Reward)
	local ready = props.State == "Ready"
	local dim = props.State == "Locked" or props.State == "Premium"
	return e(C.Panel, {
		Size = UDim2.new(1, 0, 0, CARD_H),
		Padding = 8,
		LayoutOrder = props.Order,
		Color = if props.Premium then Theme.Panel:Lerp(GOLD, 0.12) else Theme.Panel,
		StrokeColor = if ready then Theme.Good elseif props.Premium then GOLD else nil,
		StrokeTransparency = if dim then 0.6 else 0,
	}, {
		Picture = e("Frame", {
			Size = UDim2.new(1, 0, 0, 48),
			BackgroundTransparency = 1,
		}, { Inner = picture }),
		Name = e(C.Label, {
			Text = text,
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.fromOffset(0, 50),
			TextSize = 12,
			Wrap = true,
			Align = "Center",
			Bold = true,
			Color = if dim then Theme.Dim else Theme.Text,
		}),
		Status = e(C.Label, {
			Text = if props.State == "Claimed"
				then "✓ CLAIMED"
				elseif ready then "READY"
				elseif props.State == "Premium" then "🔒 PREMIUM"
				else "",
			Size = UDim2.new(1, 0, 0, 14),
			Position = UDim2.new(0, 0, 1, -14),
			TextSize = 11,
			Bold = true,
			Align = "Center",
			Color = if props.State == "Claimed" then Theme.Good elseif ready then Theme.Good else Theme.Dim,
		}),
	})
end

local function SeasonScreen(props: any)
	local data = props.Data
	local message, setMessage = React.useState(nil :: string?)
	local pending, setPending = React.useState(false)
	local track = React.useRef(nil)
	local now = workspace:GetServerTimeNow()

	-- The season to show: the one running, else the one the save is for (ended), else the next to come
	local running = Seasons.at(now)
	local saved = data.Season or Season.newState()
	local season = running or Seasons.get(saved.Id)
	local upcoming = nil
	if not season then
		for _, s in Seasons.LIST do
			if s.Start > now and (not upcoming or s.Start < upcoming.Start) then
				upcoming = s
			end
		end
		season = upcoming
	end
	if not season then
		return e(C.Label, {
			Text = "The next season is coming soon.",
			Size = UDim2.fromScale(1, 1),
			Align = "Center",
			TextSize = 20,
			Color = Theme.Dim,
		})
	end
	-- A save that hasn't caught up with a new season yet shows the new one from the start
	local mine = saved.Id == season.Id
	local xp = if mine then saved.XP else 0
	local premium = mine and saved.Premium == true
	local freeClaimed = if mine then saved.FreeClaimed or 0 else 0
	local premiumClaimed = if mine then saved.PremiumClaimed or 0 else 0
	local tier = Season.tierFor(xp)
	local into, need = Season.progress(xp)
	local claimable = if mine then Season.claimable({ Season = table.clone(saved) }) else 0

	-- Scroll the track to the first reward waiting to be claimed, or else the tier you're on
	local first = math.min(freeClaimed + 1, if premium then premiumClaimed + 1 else math.huge, math.max(tier, 1))
	React.useEffect(function()
		local frame = track.current :: ScrollingFrame?
		if frame then
			task.defer(function()
				frame.CanvasPosition = Vector2.new(math.max(0, (first - 1) * (COLUMN_W + 10)), 0)
			end)
		end
		return nil
	end, { season.Id })

	local function act(fn: () -> (boolean, string?))
		setPending(true)
		task.spawn(function()
			local ok, msg = fn()
			setPending(false)
			setMessage(if ok then msg else msg or "Try again in a moment.")
		end)
	end

	local status
	if running and running.Id == season.Id then
		status = `ENDS IN {string.upper(duration(season.End - now))}`
	elseif season.Start > now then
		status = `STARTS IN {string.upper(duration(season.Start - now))}`
	else
		status = "ENDED  ·  THE NEXT SEASON IS COMING SOON"
	end
	local live = running ~= nil and running.Id == season.Id

	-- The track: a column per tier, free reward over premium
	local columns: { [string]: any } = { Layout = C.List({ Horizontal = true, Gap = 10 }) }
	for t = 1, Seasons.TIERS do
		local reached = t <= tier
		local function stateOf(isPremium: boolean): any
			if isPremium and not premium then
				return "Premium"
			elseif (if isPremium then premiumClaimed else freeClaimed) >= t then
				return "Claimed"
			end
			return if reached then "Ready" else "Locked"
		end
		columns[`T{t}`] = e("Frame", {
			Size = UDim2.new(0, COLUMN_W, 1, 0),
			BackgroundTransparency = 1,
			LayoutOrder = t,
		}, {
			Layout = C.List({ Gap = 8 }),
			Tier = e(C.Label, {
				Text = `TIER {t}`,
				Size = UDim2.new(1, 0, 0, 22),
				Heavy = true,
				TextSize = 16,
				Align = "Center",
				Color = if reached then Theme.Accent else Theme.Dim,
				LayoutOrder = 1,
			}),
			Free = e(RewardCard, { Reward = season.Free[t], State = stateOf(false), Premium = false, Order = 2 }),
			Paid = e(RewardCard, { Reward = season.Premium[t], State = stateOf(true), Premium = true, Order = 3 }),
		})
	end

	local buy = nil
	if premium then
		buy = e(C.Label, {
			Text = "★  PREMIUM PASS  ✓",
			Size = UDim2.fromOffset(260, 44),
			Heavy = true,
			TextSize = 18,
			Color = GOLD,
			Align = "Right",
		})
	elseif live then
		buy = e("Frame", { Size = UDim2.fromOffset(380, 44), BackgroundTransparency = 1 }, {
			Layout = C.List({ Horizontal = true, Gap = 10, Align = "Right" }),
			Wings = e(C.Button, {
				Text = `PREMIUM  ·  {C.number(Seasons.PASS_WINGS)} WINGS`,
				Style = "Primary",
				Color = Theme.Wings,
				Size = UDim2.fromOffset(220, 44),
				TextSize = 14,
				Pending = pending,
				Disabled = (data.Wings or 0) < Seasons.PASS_WINGS,
				LayoutOrder = 1,
				OnClick = function()
					act(function()
						return props.OnBuySeasonPass("Wings")
					end)
				end,
			}),
			Robux = e(C.Button, {
				Text = `R$ {Products.LIST.SeasonPass.Price}`,
				Style = "Primary",
				Color = GOLD,
				Size = UDim2.fromOffset(140, 44),
				TextSize = 16,
				Pending = pending,
				Disabled = Products.idFor("SeasonPass") == nil,
				LayoutOrder = 2,
				OnClick = function()
					act(function()
						return props.OnBuySeasonPass("Robux")
					end)
				end,
			}),
		})
	end

	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Main = e("Frame", {
			Size = UDim2.new(1, -360, 1, -40),
			Position = UDim2.fromOffset(40, 20),
			BackgroundTransparency = 1,
		}, {
			Header = e(C.Panel, {
				Size = UDim2.new(1, 0, 0, 150),
				Padding = 18,
				StrokeColor = if premium then GOLD else Theme.Accent,
			}, {
				Title = e(C.Label, {
					Text = `SEASON {season.Id}  ·  {string.upper(season.Name)}`,
					Size = UDim2.new(0.6, 0, 0, 34),
					Heavy = true,
					TextSize = 30,
					Color = Theme.Accent,
				}),
				When = e(C.Label, {
					Text = status,
					Size = UDim2.new(0.6, 0, 0, 18),
					Position = UDim2.fromOffset(0, 38),
					Bold = true,
					TextSize = 14,
					Color = Theme.Dim,
				}),
				Tier = e(C.Label, {
					Text = `TIER {tier} OF {Seasons.TIERS}`,
					Size = UDim2.new(0.6, 0, 0, 22),
					Position = UDim2.fromOffset(0, 66),
					Heavy = true,
					TextSize = 18,
				}),
				Bar = e(C.Bar, {
					Value = if need > 0 then into / need else 1,
					Size = UDim2.new(0.4, 0, 0, 14),
					Position = UDim2.new(0, 0, 1, -16),
					Color = Theme.Accent,
				}),
				XP = e(C.Label, {
					Text = if need > 0 then `{C.number(into)} / {C.number(need)} XP to tier {tier + 1}` else "TOP TIER",
					Size = UDim2.new(0.15, 0, 0, 18),
					Position = UDim2.new(0.4, 10, 1, -18),
					Bold = true,
					TextSize = 13,
				}),
				Earn = e(C.Label, {
					Text = "Every bit of XP you earn counts: matches, challenges, bridge runs.",
					Size = UDim2.new(0.45, -20, 0, 32),
					Position = UDim2.new(0.55, 20, 1, -32),
					TextSize = 12,
					Wrap = true,
					Color = Theme.Dim,
				}),
				Buy = if buy
					then e("Frame", {
						Size = UDim2.fromOffset(380, 44),
						Position = UDim2.fromScale(1, 0),
						AnchorPoint = Vector2.new(1, 0),
						BackgroundTransparency = 1,
					}, { Inner = buy })
					else nil,
				-- Only there when something waits (a greyed-out button was noise)
				Claim = if claimable > 0 or pending
					then e(C.Button, {
						Text = `CLAIM {claimable} REWARD{if claimable == 1 then "" else "S"}`,
						Style = "Primary",
						Color = Theme.Good,
						Size = UDim2.fromOffset(220, 40),
						Position = UDim2.new(1, 0, 0, 54),
						AnchorPoint = Vector2.new(1, 0),
						TextSize = 15,
						Pending = pending,
						Disabled = claimable == 0,
						OnClick = function()
							act(props.OnClaimSeason)
						end,
					})
					else nil,
				Message = if message
					then e(C.Label, {
						Text = message,
						Size = UDim2.fromOffset(380, 16),
						Position = UDim2.new(1, 0, 0, 98),
						AnchorPoint = Vector2.new(1, 0),
						Align = "Right",
						TextSize = 12,
						Color = Theme.Warn,
					})
					else nil,
			}),
			Legend = e(C.Label, {
				Text = `FREE  ·  everyone        <font color="#{GOLD:ToHex()}">PREMIUM  ·  with the pass</font>`,
				Rich = true,
				Size = UDim2.new(1, 0, 0, 20),
				Position = UDim2.fromOffset(0, 162),
				Bold = true,
				TextSize = 13,
				Color = Theme.Dim,
			}),
			Track = e("ScrollingFrame", {
				Size = UDim2.new(1, 0, 0, 22 + 8 + CARD_H * 2 + 8 + 18),
				Position = UDim2.fromOffset(0, 190),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 6,
				ScrollingDirection = Enum.ScrollingDirection.X,
				CanvasSize = UDim2.fromOffset(Seasons.TIERS * (COLUMN_W + 10), 0),
				ref = track,
			}, columns),
		}),
		Challenges = e(ChallengesPanel, { Data = data, OnReroll = props.OnReroll }),
	})
end

return SeasonScreen
