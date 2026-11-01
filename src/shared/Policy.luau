--!strict
-- What Roblox's policy rules allow for a player (CMP-02; DEVELOPMENT.md §32). PolicyChecksService asks
-- PolicyService:GetPolicyInfoForPlayerAsync on join and shows the answer as player attributes; anything
-- regulated asks here first. Until Roblox answers, or if it can't, everything regulated is off (STRICT).
-- Pure: the tests drive it with made-up answers.
--   PaidRandomItems: may this player buy a random item? (We sell none: DESIGN §8.1. If one is ever added, it
--     must check this and show its odds.)
--   Links: the external link references this player may be shown ("Discord", "Twitter", ...).
--   PaidTrading: may this player trade paid items?

local Policy = {}

export type Rules = {
	PaidRandomItems: boolean,
	Links: { string },
	PaidTrading: boolean,
}

Policy.STRICT = table.freeze({ PaidRandomItems = false, Links = table.freeze({}), PaidTrading = false }) :: Rules

Policy.ATTRIBUTES = table.freeze({
	PaidRandomItems = "PolicyPaidRandom",
	Links = "PolicyLinks", -- the references, comma-separated
	PaidTrading = "PolicyPaidTrading",
	Checked = "PolicyChecked", -- true once Roblox answered
})

-- The rules in Roblox's answer (a GetPolicyInfoForPlayerAsync table). Anything missing or odd counts as
-- not allowed.
function Policy.read(info: any): Rules
	if type(info) ~= "table" then
		return Policy.STRICT
	end
	local links = {}
	if type(info.AllowedExternalLinkReferences) == "table" then
		for _, ref in info.AllowedExternalLinkReferences do
			if type(ref) == "string" then
				table.insert(links, ref)
			end
		end
	end
	return {
		-- Roblox says whether they're *restricted*, so only an explicit false allows them
		PaidRandomItems = info.ArePaidRandomItemsRestricted == false,
		Links = links,
		PaidTrading = info.IsPaidItemTradingAllowed == true,
	}
end

-- The rules shown on a player (the attributes PolicyChecksService sets): strict until checked.
function Policy.of(player: Instance): Rules
	if player:GetAttribute(Policy.ATTRIBUTES.Checked) ~= true then
		return Policy.STRICT
	end
	local links = player:GetAttribute(Policy.ATTRIBUTES.Links)
	return {
		PaidRandomItems = player:GetAttribute(Policy.ATTRIBUTES.PaidRandomItems) == true,
		Links = if type(links) == "string" and links ~= "" then string.split(links, ",") else {},
		PaidTrading = player:GetAttribute(Policy.ATTRIBUTES.PaidTrading) == true,
	}
end

-- Writes the rules onto a player as attributes (the server does this; the client reads them with of).
function Policy.show(player: Instance, rules: Rules, checked: boolean)
	player:SetAttribute(Policy.ATTRIBUTES.PaidRandomItems, rules.PaidRandomItems)
	player:SetAttribute(Policy.ATTRIBUTES.Links, table.concat(rules.Links, ","))
	player:SetAttribute(Policy.ATTRIBUTES.PaidTrading, rules.PaidTrading)
	player:SetAttribute(Policy.ATTRIBUTES.Checked, checked)
end

-- Whether a link to this site (a reference such as "Discord") may be shown to the player.
function Policy.linkAllowed(rules: Rules, reference: string): boolean
	return table.find(rules.Links, reference) ~= nil
end

return Policy
