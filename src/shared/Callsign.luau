--!strict
-- Custom callsigns (DEVELOPMENT.md §32.2, CMP-01): the name other pilots see on your jet, the scoreboard and
-- the kill feed instead of your Roblox username. The server cleans the text here, runs it through Roblox's
-- text filter (TextFilterService) and only shows it if the filter left it untouched. The shown callsign is
-- the player's "Callsign" attribute; "" or missing means the username. Pure (nameOf only reads attributes).

local Callsign = {}

Callsign.MIN = 3
Callsign.MAX = 16

-- Tidies typed text into a callsign: trimmed, runs of spaces made single. Letters, digits, spaces, "-" and
-- "_" only, MIN–MAX characters, at least one letter. Returns the callsign, or nil and why not (HUD words).
function Callsign.clean(text: string): (string?, string?)
	local tidy = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
	tidy = string.gsub(tidy, "%s+", " ")
	if #tidy < Callsign.MIN then
		return nil, `At least {Callsign.MIN} characters`
	elseif #tidy > Callsign.MAX then
		return nil, `No more than {Callsign.MAX} characters`
	elseif string.find(tidy, "[^%w _%-]") then
		return nil, "Letters, numbers, spaces, - and _ only"
	elseif not string.find(tidy, "%a") then
		return nil, "Needs at least one letter"
	end
	return tidy, nil
end

-- Whether Roblox's filter passed the callsign: anything it changed (hashed out) means it isn't shown at all,
-- rather than showing a callsign full of #s.
function Callsign.accepted(callsign: string, filtered: string?): boolean
	return filtered ~= nil and filtered == callsign
end

-- The name to show for a pilot: a player's callsign if they have one, else their username; an AI pilot
-- record's Name.
function Callsign.nameOf(identity: any): string
	if typeof(identity) == "Instance" and identity:IsA("Player") then
		local callsign = identity:GetAttribute("Callsign")
		return if type(callsign) == "string" and callsign ~= "" then callsign else identity.Name
	end
	return if type(identity) == "table" and type(identity.Name) == "string" then identity.Name else "?"
end

return Callsign
