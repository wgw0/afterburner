--!strict
-- Owning, buying and equipping cosmetics (SHP-07; the catalogue is Config/Cosmetics). Saved as
-- data.Cosmetics = { Owned = { [id] = true }, Equipped = { [kind] = id or "" } }. Pure.

local Catalogue = require(script.Parent.Config.Cosmetics)
local Perks = require(script.Parent.Perks)

local Cosmetics = {}

local function state(data: { [string]: any }): { Owned: { [string]: boolean }, Equipped: { [string]: string } }
	data.Cosmetics = data.Cosmetics or {}
	data.Cosmetics.Owned = data.Cosmetics.Owned or {}
	data.Cosmetics.Equipped = data.Cosmetics.Equipped or {}
	return data.Cosmetics
end

-- Wing art is only for sale once its decals are uploaded, and a camo once its paint and preview are.
function Cosmetics.ready(id: string): boolean
	local item = Catalogue.get(id)
	if not item then
		return false
	end
	if item.Kind == "Camo" then
		return item.Images ~= nil and item.Images[1] ~= ""
	end
	return item.Kind ~= "WingArt" or (item.Images ~= nil and item.Images[1] ~= "" and item.Images[2] ~= "")
end

function Cosmetics.owns(data: { [string]: any }, id: string): boolean
	local item = Catalogue.get(id)
	if not item then
		return false
	end
	if data.Flags and data.Flags.AllUnlocked == true then
		return true
	end
	if item.Pass then
		return Perks.owns(data, item.Pass)
	end
	local saved = data.Cosmetics and data.Cosmetics.Owned
	return saved ~= nil and saved[id] == true
end

function Cosmetics.canBuy(data: { [string]: any }, id: string): (boolean, string?)
	local item = Catalogue.get(id)
	if not item then
		return false, "Unknown item"
	elseif item.Wings == nil then
		return false, if item.Pass then "Comes with a game pass" else "Not for sale"
	elseif not Cosmetics.ready(id) then
		return false, "Coming soon"
	elseif Cosmetics.owns(data, id) then
		return false, "You already own that"
	elseif (data.Wings or 0) < item.Wings then
		return false, "Not enough Wings"
	end
	return true, nil
end

-- Buys and equips it.
function Cosmetics.buy(data: { [string]: any }, id: string): (boolean, string?)
	local ok, err = Cosmetics.canBuy(data, id)
	if not ok then
		return false, err
	end
	local item = Catalogue.get(id) :: Catalogue.Cosmetic
	data.Wings -= item.Wings :: number
	local s = state(data)
	s.Owned[id] = true
	s.Equipped[item.Kind] = id
	return true, nil
end

-- Equips an owned item in its kind's slot, or clears the slot (id "").
function Cosmetics.equip(data: { [string]: any }, kind: string, id: string): (boolean, string?)
	if not table.find(Catalogue.KINDS, kind :: any) then
		return false, "Unknown kind"
	end
	if id ~= "" then
		local item = Catalogue.get(id)
		if not item or item.Kind ~= kind then
			return false, "Unknown item"
		elseif not Cosmetics.owns(data, id) then
			return false, "You don't own that"
		end
	end
	state(data).Equipped[kind] = id
	return true, nil
end

-- What's equipped in a slot and still owned (a pass item stops when the pass does), or nil.
function Cosmetics.equipped(data: { [string]: any }, kind: string): string?
	local id = data.Cosmetics and data.Cosmetics.Equipped and data.Cosmetics.Equipped[kind]
	if type(id) ~= "string" or id == "" or not Cosmetics.owns(data, id) or not Cosmetics.ready(id) then
		return nil
	end
	return id
end

return Cosmetics
