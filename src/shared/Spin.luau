--!strict
-- The free spin (DEVELOPMENT.md §26.6, retention). One spin per INTERVAL seconds in the game, banked up to
-- BANK; a new account starts with one ready. The server rolls the prize (rarity first, with CS:GO-case odds,
-- then a concrete prize the player can use) and grants it in the same save update. Spins are never sold:
-- a paid random prize is gambling (DESIGN §8.1). Pure: SpinService runs it on the save, the tests directly.

local Economy = require(script.Parent.Config.Economy)
local Skins = require(script.Parent.Skins)

local Spin = {}

Spin.INTERVAL = 20 * 60 -- seconds in the game per spin
Spin.BANK = 3 -- spins that can be saved up

export type Tier = {
	Rarity: string, -- the achievements' rarities and colours (UI Theme.Rarity)
	Weight: number, -- percent
	Kind: "Credits" | "Module" | "Wings" | "Skin",
	Amount: number?,
}

-- Rarest last. The weights are CS:GO's case odds (Mil-Spec, Restricted, Classified, Covert, rare special).
Spin.TIERS = table.freeze({
	table.freeze({ Rarity = "Common", Weight = 79.92, Kind = "Credits", Amount = 250 }),
	table.freeze({ Rarity = "Uncommon", Weight = 15.98, Kind = "Module" }), -- a free upgrade for a jet you own
	table.freeze({ Rarity = "Rare", Weight = 3.20, Kind = "Credits", Amount = 2500 }),
	table.freeze({ Rarity = "Epic", Weight = 0.64, Kind = "Wings", Amount = Skins.WINGS_PRICE / 2 }), -- half a skin
	table.freeze({ Rarity = "Legendary", Weight = 0.26, Kind = "Skin" }), -- a base skin for a jet you own
}) :: { Tier }

-- No dead prizes: when there's no upgrade or skin left to give, something worth about the same instead.
Spin.FALLBACK = table.freeze({
	Module = table.freeze({ Kind = "Credits", Amount = 750 }),
	Skin = table.freeze({ Kind = "Wings", Amount = Skins.WINGS_PRICE }),
})

export type State = { Banked: number, Progress: number } -- in the save as data.Spin

export type Prize = {
	Rarity: string,
	Kind: string, -- "Credits" | "Module" | "Wings" | "Skin"
	Amount: number?,
	Airframe: string?, -- Module / Skin: which jet
	Item: string?, -- Module / Skin: which one
	Label: string, -- what to show: "2,500 Credits", "Engine II · F-16A"
}

function Spin.newState(): State
	return { Banked = 1, Progress = 0 }
end

-- Adds play time. Returns true if that earned a spin. Time doesn't build up while the bank is full.
function Spin.accrue(state: State, seconds: number): boolean
	if state.Banked >= Spin.BANK then
		state.Progress = 0
		return false
	end
	state.Progress += seconds
	if state.Progress < Spin.INTERVAL then
		return false
	end
	state.Banked = math.min(state.Banked + 1, Spin.BANK)
	state.Progress = if state.Banked >= Spin.BANK then 0 else state.Progress - Spin.INTERVAL
	return true
end

-- Seconds of play until the next spin is earned, or nil while the bank is full.
function Spin.secondsToNext(state: State): number?
	if state.Banked >= Spin.BANK then
		return nil
	end
	return math.max(Spin.INTERVAL - state.Progress, 0)
end

-- The tier for a roll in [0, 1).
function Spin.tierFor(roll: number): number
	local total = 0
	for _, tier in Spin.TIERS do
		total += tier.Weight
	end
	local at = roll * total
	for i, tier in Spin.TIERS do
		at -= tier.Weight
		if at < 0 then
			return i
		end
	end
	return 1
end

local function number(n: number): string
	local grouped = string.reverse((string.gsub(string.reverse(tostring(math.floor(n))), "(%d%d%d)", "%1,")))
	return (string.gsub(grouped, "^,", ""))
end

local function flat(rarity: string, kind: string, amount: number): Prize
	return { Rarity = rarity, Kind = kind, Amount = amount, Label = `{number(amount)} {kind}` }
end

-- Every (jet, module) the player could be given: a jet they own, a module they haven't got whose
-- prerequisite they have.
local function moduleChoices(data: { [string]: any }): { { string } }
	local choices = {}
	for airframeId, entry in data.Aircraft do
		if entry.Owned then
			local modules = entry.Modules or {}
			for _, def in Economy.MODULES do
				if modules[def.Id] == nil and (not def.Requires or modules[def.Requires] ~= nil) then
					table.insert(choices, { airframeId, def.Id })
				end
			end
		end
	end
	table.sort(choices, function(a, b)
		return a[1] .. a[2] < b[1] .. b[2]
	end)
	return choices
end

-- Every (jet, skin) the player could be given: a skin sold for Credits (not a default or level skin) for a
-- jet they own, that they don't have.
local function skinChoices(data: { [string]: any }): { { string } }
	local choices = {}
	for airframeId, entry in data.Aircraft do
		if entry.Owned then
			for _, skin in Skins.list(airframeId) do
				local owned = entry.Skins and entry.Skins[skin.Id]
				if skin.Credits and not skin.Default and not skin.Level and not owned then
					table.insert(choices, { airframeId, skin.Id })
				end
			end
		end
	end
	table.sort(choices, function(a, b)
		return a[1] .. a[2] < b[1] .. b[2]
	end)
	return choices
end

-- A concrete prize for a tier, for this player (pick: a number in [0, 1) choosing among upgrades / skins).
function Spin.resolve(data: { [string]: any }, tierIndex: number, pick: number): Prize
	local tier = Spin.TIERS[tierIndex]
	if tier.Kind == "Credits" or tier.Kind == "Wings" then
		return flat(tier.Rarity, tier.Kind, tier.Amount :: number)
	end
	local choices = if tier.Kind == "Module" then moduleChoices(data) else skinChoices(data)
	if #choices == 0 then
		local fallback = Spin.FALLBACK[tier.Kind]
		return flat(tier.Rarity, fallback.Kind, fallback.Amount)
	end
	local choice = choices[math.clamp(math.floor(pick * #choices) + 1, 1, #choices)]
	local airframeId, item = choice[1], choice[2]
	local name = item
	if tier.Kind == "Module" then
		for _, def in Economy.MODULES do
			if def.Id == item then
				name = def.DisplayName
			end
		end
	else
		local skin = Skins.get(airframeId, item)
		name = if skin then skin.DisplayName else item
	end
	return { Rarity = tier.Rarity, Kind = tier.Kind, Airframe = airframeId, Item = item, Label = name }
end

-- Puts a prize in the save.
function Spin.apply(data: { [string]: any }, prize: Prize)
	if prize.Kind == "Credits" then
		data.Credits += prize.Amount :: number
	elseif prize.Kind == "Wings" then
		data.Wings = (data.Wings or 0) + (prize.Amount :: number)
	elseif prize.Kind == "Module" then
		local entry = data.Aircraft[prize.Airframe :: string]
		entry.Modules = entry.Modules or {}
		entry.Modules[prize.Item :: string] = true -- fitted straight away
	elseif prize.Kind == "Skin" then
		local entry = data.Aircraft[prize.Airframe :: string]
		entry.Skins = entry.Skins or {}
		entry.Skins[prize.Item :: string] = true
	end
end

-- Uses a banked spin: rolls (two numbers in [0, 1): the tier, then the pick), applies the prize and returns
-- it; or nil and why not.
function Spin.take(data: { [string]: any }, roll: number, pick: number): (Prize?, string?)
	local state = data.Spin :: State
	if not state or state.Banked < 1 then
		return nil, "No spin ready yet"
	end
	local prize = Spin.resolve(data, Spin.tierFor(roll), pick)
	Spin.apply(data, prize)
	state.Banked -= 1
	if state.Banked == Spin.BANK - 1 then
		state.Progress = 0 -- the clock starts again from a full bank
	end
	return prize, nil
end

return Spin
