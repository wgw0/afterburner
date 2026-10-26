--!strict
-- Aircraft detail (UI-04): performance bars (stock vs with your modules), the upgrade modules with
-- their costs and Fit buttons, the loadout, camo, and adding the jet to your lineup.
-- props: Data, AirframeId, OnBack(), OnBuyModule(id, moduleId) -> (ok, err),
--   OnSetModuleFitted(id, moduleId, fitted) -> (ok, err), OnLineup(ids) -> (ok, err)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AircraftData = require(Shared.AircraftData)
local Economy = require(Shared.Config.Economy)
local Progression = require(Shared.Progression)
local WeaponData = require(Shared.WeaponData)

local UI = script.Parent.Parent
local C = require(UI.Components)
local JetPreview = require(UI.JetPreview)
local Theme = require(UI.Theme)

local e = React.createElement
local G = 9.81

-- Rough, comparable performance numbers for the bars.
local function stats(a: any): { { string } | any }
	return {
		{ "Top speed", a.MaxMach, 2.5, string.format("Mach %.2f", a.MaxMach) },
		{ "Max G", a.MaxG, 10, string.format("%.1f G", a.MaxG) },
		{ "Thrust / weight", a.MaxThrust * a.AfterburnerMult / ((a.Mass + a.Fuel) * G), 1.4, nil },
		{ "Roll rate", a.MaxRollRate, 120, nil },
		{ "Radar range", a.Radar and a.Radar.Range or 0, 50000, nil },
	}
end

local function effectText(def: Economy.ModuleDef): string
	local parts = {}
	for effect, value in def.Effects do
		local plus = string.match(effect, "^(.+)Plus$")
		local field = plus or string.match(effect, "^(.+)X$") or effect
		local label = ({
			MaxThrust = "thrust",
			MaxG = "max G",
			MaxRollRate = "roll rate",
			RadarRange = "radar range",
			Flares = "flares",
			Chaff = "chaff",
		})[field] or field
		if plus then
			table.insert(parts, `+{value} {label}`)
		else
			table.insert(parts, `+{math.floor((value - 1) * 100 + 0.5)}% {label}`)
		end
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

local function ModuleRow(props: any)
	local def: Economy.ModuleDef = props.Def
	local data, airframeId = props.Data, props.AirframeId
	local pending, setPending = React.useState(false)
	local message, setMessage = React.useState(nil :: string?)
	local entry = data.Aircraft[airframeId]
	local state = entry and entry.Modules[def.Id] -- true fitted, false owned but off, nil not owned
	local fitted, owned = state == true, state ~= nil
	local rp, credits = Progression.moduleCost(airframeId, def)
	local ok, reason
	if owned then
		ok, reason = Progression.canSetModuleFitted(data, airframeId, def.Id, not fitted)
	else
		ok, reason = Progression.canBuyModule(data, airframeId, def.Id)
	end
	local function run(action: () -> (boolean, string?))
		setPending(true)
		setMessage(nil)
		task.spawn(function()
			local done, err = action()
			setPending(false)
			setMessage(if done then nil else err)
		end)
	end
	return e(C.Panel, {
		Size = UDim2.new(1, 0, 0, 64),
		LayoutOrder = props.Order,
		Color = if fitted then Theme.PanelLight else Theme.Panel,
		StrokeColor = if fitted then Theme.Good else Theme.Stroke,
	}, {
		Name = e(C.Label, {
			Text = def.DisplayName,
			Size = UDim2.new(1, -150, 0, 20),
			Position = UDim2.fromOffset(12, 8),
			Bold = true,
			TextSize = 15,
		}),
		Effect = e(C.Label, {
			Text = effectText(def),
			Size = UDim2.new(1, -150, 0, 16),
			Position = UDim2.fromOffset(12, 28),
			Color = Theme.Dim,
			TextSize = 12,
		}),
		Cost = e(C.Label, {
			Text = message or (if fitted
				then (if ok then "Fitted" else `Fitted · {reason}`)
				elseif owned then (if ok then "Owned · not fitted" else `Owned · {reason}`)
				elseif ok then `{rp} RP · {C.number(credits)} Cr`
				else reason),
			Size = UDim2.new(1, -150, 0, 16),
			Position = UDim2.fromOffset(12, 44),
			Color = if message
				then Theme.Warn
				elseif fitted then Theme.Good
				elseif not ok then Theme.Warn
				else Theme.Text,
			TextSize = 12,
		}),
		Action = e(C.Button, {
			Text = if fitted then "UNFIT" elseif owned then "FIT" else "BUY",
			Style = if fitted then "Ghost" else "Primary",
			Size = UDim2.fromOffset(120, 40),
			Position = UDim2.new(1, -132, 0.5, -20),
			TextSize = 14,
			Pending = pending,
			Disabled = not ok,
			OnClick = function()
				if owned then
					run(function()
						return props.OnSetModuleFitted(airframeId, def.Id, not fitted)
					end)
				else
					run(function()
						return props.OnBuyModule(airframeId, def.Id)
					end)
				end
			end,
		}),
	})
end

local function AircraftDetail(props: any)
	local data, id = props.Data, props.AirframeId
	local lineupPending, setLineupPending = React.useState(false)
	local lineupMessage, setLineupMessage = React.useState(nil :: string?)
	local airframe = AircraftData.get(id) :: any
	if not airframe then
		return nil
	end
	local entry = data.Aircraft[id]
	local upgraded = Progression.applyModules(airframe, entry and entry.Modules)
	local stock, mine = stats(airframe), stats(upgraded)

	local statChildren: { [string]: any } = { Layout = C.List({ Gap = 10 }) }
	statChildren.Title =
		e(C.Label, { Text = "PERFORMANCE", Bold = true, Color = Theme.Accent, TextSize = 14, LayoutOrder = 0 })
	for i, s in stock do
		local now = mine[i]
		statChildren[`S{i}`] = e(
			"Frame",
			{ Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = i },
			{
				Label = e(C.Label, {
					Text = `{s[1]}   {now[4] or ""}`,
					Size = UDim2.new(1, 0, 0, 16),
					TextSize = 13,
					Color = Theme.Dim,
				}),
				Upgraded = e(C.Bar, {
					Value = now[2] / s[3],
					Size = UDim2.new(1, 0, 0, 10),
					Position = UDim2.fromOffset(0, 20),
					Color = Theme.Good,
					ZIndex = 1,
				}),
				Stock = e(C.Bar, {
					Value = s[2] / s[3],
					Size = UDim2.new(1, 0, 0, 10),
					Position = UDim2.fromOffset(0, 20),
					Color = Theme.Accent,
					ZIndex = 2,
					Transparent = true,
				}),
			}
		)
	end
	statChildren.Key = e(C.Label, {
		Text = "Orange: stock  ·  Green: with your modules",
		TextSize = 12,
		Color = Theme.Dim,
		LayoutOrder = 99,
	})

	-- Loadout
	local loadout = {}
	for _, slot in airframe.Missiles or {} do
		local spec = WeaponData.getMissile(slot.Weapon)
		table.insert(loadout, `{slot.Count}× {spec and spec.DisplayName or slot.Weapon}`)
	end
	local gun = WeaponData.get(airframe.Gun)
	local cm = upgraded.Countermeasures or {}
	local loadoutText = table.concat(loadout, "\n")
		.. `\n{gun and gun.DisplayName or airframe.Gun}`
		.. `\n{cm.Flares or 0} flares, {cm.Chaff or 0} chaff`

	local moduleChildren: { [string]: any } = { Layout = C.List({ Gap = 8 }) }
	moduleChildren.Title =
		e(C.Label, { Text = "MODULES", Bold = true, Color = Theme.Accent, TextSize = 14, LayoutOrder = 0 })
	if entry and entry.Owned then
		moduleChildren.RP = e(C.Label, {
			Text = `{C.number(entry.RP)} RP in this jet  ·  {C.number(data.Credits)} Credits`,
			TextSize = 13,
			Color = Theme.Good,
			LayoutOrder = 1,
		})
		for i, def in Economy.MODULES do
			moduleChildren[def.Id] = e(ModuleRow, {
				Def = def,
				Data = data,
				AirframeId = id,
				Order = i + 1,
				OnBuyModule = props.OnBuyModule,
				OnSetModuleFitted = props.OnSetModuleFitted,
			})
		end
	else
		moduleChildren.Locked = e(C.Label, {
			Text = "Buy this jet to fit modules.",
			Color = Theme.Dim,
			TextSize = 14,
			LayoutOrder = 1,
		})
	end

	local inLineup = table.find(data.Lineup, id)
	local slots = Progression.lineupSlots(data.PilotLevel)

	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Back = e(C.Button, {
			Text = "‹ BACK",
			Style = "Ghost",
			Size = UDim2.fromOffset(110, 40),
			Position = UDim2.fromOffset(20, 20),
			TextSize = 14,
			OnClick = props.OnBack,
		}),
		Name = e(C.Label, {
			Text = airframe.DisplayName,
			Size = UDim2.fromOffset(600, 40),
			Position = UDim2.fromOffset(150, 20),
			Heavy = true,
			TextSize = 30,
		}),
		Info = e(C.Label, {
			Text = `Tier {airframe.Tier}  ·  BR {airframe.BattleRating}  ·  {airframe.Branch}`,
			Size = UDim2.fromOffset(600, 20),
			Position = UDim2.fromOffset(152, 58),
			Color = Theme.Dim,
			TextSize = 15,
		}),
		Preview = e(JetPreview, {
			AirframeId = id,
			Size = UDim2.fromScale(0.36, 0.5),
			Position = UDim2.fromOffset(20, 90),
		}),
		Stats = e(C.Panel, {
			Size = UDim2.new(0.36, 0, 0, 260),
			Position = UDim2.new(0, 20, 0.5, 100),
			Padding = 14,
		}, statChildren),
		Loadout = e(C.Panel, {
			Size = UDim2.new(0.24, 0, 0, 230),
			Position = UDim2.new(0.38, 20, 0, 90),
			Padding = 14,
		}, {
			Layout = C.List({ Gap = 8 }),
			Title = e(C.Label, { Text = "LOADOUT", Bold = true, Color = Theme.Accent, TextSize = 14, LayoutOrder = 0 }),
			Items = e(C.Label, { Text = loadoutText, TextSize = 14, Wrap = true, AutoHeight = true, LayoutOrder = 1 }),
			Camo = e(C.Label, {
				Text = `Camo: {entry and entry.Camo or "Default"}`,
				TextSize = 13,
				Color = Theme.Dim,
				LayoutOrder = 2,
			}),
		}),
		Lineup = if entry and entry.Owned
			then e(C.Panel, {
				Size = UDim2.new(0.24, 0, 0, 120),
				Position = UDim2.new(0.38, 20, 0, 336),
				Padding = 14,
			}, {
				Layout = C.List({ Gap = 8 }),
				Text = e(C.Label, {
					Text = lineupMessage or (if inLineup
						then `In your lineup (slot {inLineup})`
						elseif #data.Lineup >= slots then "Lineup full: remove a jet in the hangar first"
						else "Not in your lineup"),
					TextSize = 13,
					Color = if lineupMessage then Theme.Bad else Theme.Dim,
					Wrap = true,
					LayoutOrder = 0,
				}),
				Button = e(C.Button, {
					Text = if inLineup then "REMOVE FROM LINEUP" else "ADD TO LINEUP",
					TextSize = 13,
					LayoutOrder = 1,
					Pending = lineupPending,
					Disabled = (inLineup ~= nil and #data.Lineup <= 1) or (inLineup == nil and #data.Lineup >= slots),
					OnClick = function()
						local ids = table.clone(data.Lineup)
						if inLineup then
							table.remove(ids, inLineup)
						else
							table.insert(ids, id)
						end
						setLineupPending(true)
						task.spawn(function()
							local ok, err = props.OnLineup(ids)
							setLineupPending(false)
							setLineupMessage(if ok then nil else err)
						end)
					end,
				}),
			})
			else nil,
		Modules = e(C.Panel, {
			Size = UDim2.new(0.36, -40, 1, -110),
			Position = UDim2.new(1, -20, 0, 90),
			AnchorPoint = Vector2.new(1, 0),
			Padding = 14,
		}, {
			Scroll = e("ScrollingFrame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 4,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
			}, moduleChildren),
		}),
	})
end

return AircraftDetail
