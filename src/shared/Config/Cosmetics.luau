--!strict
-- Cosmetics bought with Wings (DESIGN §8.2, SHP-07): never power, and never random. One of each kind can be
-- equipped at a time, across every jet; nothing equipped means the plain look (white contrails, stencilled
-- stars, the HUD colour from Settings, no wing art). Prices follow DESIGN §8.2's Robux guide at about one
-- Wing per Robux. Shared/Cosmetics has the rules; the server applies them to spawned jets, so everyone sees
-- contrails, kill markers and wing art (HUD themes are only for you).
--   Trail: colours your contrails, and lets coloured display smoke stream from the wingtips while the
--     afterburner's lit (Colours: one colour, or several along the trail).
--   Marker: how your kill markers are painted (Glyph, repeated once per mastery star, and Colour).
--   HUD: your HUD's colour (over the HUDColour setting while equipped).
--   WingArt: a decal on top of each wing, mid-span (Images: the right and left wing, mirrored so both point
--     outboard).
--   Camo: paints every jet you fly in it, over each jet's own skin (Skin: the skin folder in
--     Assets.Skins.<Jet>, painted for every jet by tools/blender/livery_paint.py; Images: the shop preview).
-- Pass: free with that game pass, and can't be bought (VIP Gold).

export type Kind = "Trail" | "Marker" | "HUD" | "WingArt" | "Camo"

export type Cosmetic = {
	Kind: Kind,
	DisplayName: string,
	Wings: number?, -- price; nil = not for sale (a pass item)
	Pass: string?, -- free with this pass (Config/Passes)
	Colours: { Color3 }?, -- Trail (along the trail), HUD (the first)
	Glyph: string?, -- Marker
	Colour: Color3?, -- Marker
	Images: { string }?, -- WingArt: { right wing, left wing } asset ids ("" until uploaded); Camo: { preview }
	Skin: string?, -- Camo: the skin it paints
	Order: number, -- in the shop
}

local Cosmetics = {}

Cosmetics.KINDS = table.freeze({ "Camo", "Trail", "Marker", "HUD", "WingArt" }) :: { Kind }
Cosmetics.KIND_NAMES = table.freeze({
	Camo = "Camos",
	Trail = "Contrails",
	Marker = "Kill markers",
	HUD = "HUD themes",
	WingArt = "Wing art",
})

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local GOLD = rgb(255, 201, 60) -- the VIP tag's gold

Cosmetics.LIST = table.freeze({
	-- Contrails and display smoke (DESIGN: contrail colours 200 R$; Tricolour 300)
	TrailRed = { Kind = "Trail", DisplayName = "Red", Wings = 200, Colours = { rgb(235, 60, 50) }, Order = 1 },
	TrailBlue = { Kind = "Trail", DisplayName = "Blue", Wings = 200, Colours = { rgb(60, 120, 240) }, Order = 2 },
	TrailGreen = { Kind = "Trail", DisplayName = "Green", Wings = 200, Colours = { rgb(70, 200, 90) }, Order = 3 },
	TrailOrange = {
		Kind = "Trail",
		DisplayName = "Afterburner Orange",
		Wings = 200,
		Colours = { rgb(255, 138, 61) },
		Order = 4,
	},
	TrailTricolour = {
		Kind = "Trail",
		DisplayName = "Tricolour",
		Wings = 300,
		Colours = { rgb(235, 60, 50), rgb(245, 245, 245), rgb(60, 120, 240) },
		Order = 5,
	},
	TrailVIP = { Kind = "Trail", DisplayName = "VIP Gold", Pass = "VIP", Colours = { GOLD }, Order = 6 },

	-- Kill-marker styles (DESIGN: 100 R$)
	MarkerBars = {
		Kind = "Marker",
		DisplayName = "Kill Bars",
		Wings = 100,
		Glyph = "▮",
		Colour = rgb(235, 235, 225),
		Order = 1,
	},
	MarkerRoundels = {
		Kind = "Marker",
		DisplayName = "Roundels",
		Wings = 100,
		Glyph = "◉",
		Colour = rgb(235, 80, 70),
		Order = 2,
	},
	MarkerJets = {
		Kind = "Marker",
		DisplayName = "Jet Silhouettes",
		Wings = 100,
		Glyph = "✈",
		Colour = rgb(235, 235, 225),
		Order = 3,
	},
	MarkerGold = { Kind = "Marker", DisplayName = "Gold Stars", Wings = 150, Glyph = "★", Colour = GOLD, Order = 4 },

	-- HUD themes (DESIGN: 150 R$). Colours the free HUDColour presets don't have.
	HUDAmber = { Kind = "HUD", DisplayName = "Amber", Wings = 150, Colours = { rgb(255, 176, 60) }, Order = 1 },
	HUDGold = { Kind = "HUD", DisplayName = "Gold", Wings = 150, Colours = { GOLD }, Order = 2 },
	HUDIce = { Kind = "HUD", DisplayName = "Ice", Wings = 150, Colours = { rgb(190, 235, 255) }, Order = 3 },
	HUDMint = { Kind = "HUD", DisplayName = "Mint", Wings = 150, Colours = { rgb(150, 255, 210) }, Order = 4 },

	-- Camos (DESIGN: 150-600 R$): bought once, on every jet (Will). VIP Gold comes with the VIP Pilot pass.
	CamoVIP = {
		Kind = "Camo",
		DisplayName = "VIP Gold",
		Pass = "VIP",
		Skin = "VIPGold",
		Colours = { GOLD },
		Images = { "rbxassetid://125674333100654" },
		Order = 1,
	},
	CamoArctic = {
		Kind = "Camo",
		DisplayName = "Arctic Splinter",
		Wings = 400,
		Skin = "ArcticSplinter",
		Colours = { rgb(146, 174, 200) },
		Images = { "rbxassetid://95443903567285" },
		Order = 2,
	},
	CamoTiger = {
		Kind = "Camo",
		DisplayName = "Tiger Stripe",
		Wings = 400,
		Skin = "TigerStripe",
		Colours = { rgb(232, 142, 40) },
		Images = { "rbxassetid://130275013707024" },
		Order = 3,
	},

	-- Wing art (DESIGN: 250 R$). Made by tools/cosmetics/wing_art.py; Images = { right wing, left wing }.
	WingShark = {
		Kind = "WingArt",
		DisplayName = "Shark Mouth",
		Wings = 250,
		Images = { "rbxassetid://125379322282998", "rbxassetid://109471115413464" },
		Order = 1,
	},
	WingAce = {
		Kind = "WingArt",
		DisplayName = "Ace of Spades",
		Wings = 250,
		Images = { "rbxassetid://75298212215679", "rbxassetid://113012543482538" },
		Order = 2,
	},
	WingBolt = {
		Kind = "WingArt",
		DisplayName = "Lightning Bolt",
		Wings = 250,
		Images = { "rbxassetid://104985414551295", "rbxassetid://72548941369160" },
		Order = 3,
	},
	WingEight = {
		Kind = "WingArt",
		DisplayName = "Lucky Eight",
		Wings = 250,
		Images = { "rbxassetid://72432997988103", "rbxassetid://140078804130604" },
		Order = 4,
	},
}) :: { [string]: Cosmetic }

function Cosmetics.get(id: string): Cosmetic?
	return Cosmetics.LIST[id]
end

-- Ids of one kind, in shop order.
function Cosmetics.ofKind(kind: Kind): { string }
	local ids = {}
	for id, item in Cosmetics.LIST do
		if item.Kind == kind then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a, b)
		return Cosmetics.LIST[a].Order < Cosmetics.LIST[b].Order
	end)
	return ids
end

return Cosmetics
