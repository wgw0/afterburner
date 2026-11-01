--!strict
-- Themed bundles for the weekly featured slot (DESIGN §8.4, SHP-05). One is featured each week, in this
-- order, changing on Monday at 00:00 UTC (the same for everyone: Shop.bundleFor). A bundle is bought with
-- Wings for DISCOUNT off the items you don't own yet, so owning some of it never means paying twice. The
-- items are Config/Cosmetics ids sold for Wings; nothing in a bundle is random.

export type Bundle = { Id: string, DisplayName: string, Items: { string } }

local Bundles = {}

Bundles.DISCOUNT = 0.25 -- off the items' own prices

Bundles.LIST = table.freeze({
	{ Id = "DisplayTeam", DisplayName = "Display Team", Items = { "TrailTricolour", "MarkerRoundels", "WingBolt" } },
	{ Id = "Arctic", DisplayName = "Arctic Patrol", Items = { "CamoArctic", "TrailBlue", "HUDIce" } },
	{ Id = "Tiger", DisplayName = "Tiger Meet", Items = { "CamoTiger", "TrailOrange", "WingShark" } },
	{ Id = "Night", DisplayName = "Night Raider", Items = { "CamoMidnight", "MarkerBars", "HUDMint" } },
	{ Id = "Spider", DisplayName = "Black Widow", Items = { "CamoArachnida", "TrailRed", "WingAce" } },
	{ Id = "Cosmic", DisplayName = "Deep Space", Items = { "CamoGalaxy", "MarkerGold", "WingEight" } },
}) :: { Bundle }

function Bundles.get(id: string): Bundle?
	for _, bundle in Bundles.LIST do
		if bundle.Id == id then
			return bundle
		end
	end
	return nil
end

return Bundles
