--!strict
-- Social bonuses on match rewards (DEVELOPMENT.md §25.8; rules in Shared/Social). Two of them, each its own
-- line on the results screen:
--   Group: in the Afterburner Roblox group (Player:IsInGroupAsync on the server). Rewarding a group join is allowed;
--     rewarding likes or favourites is not, so there is no bonus for those (docs/COMPLIANCE.md §8).
--   Friends: a Roblox friend or a party member flew in the same match.
-- Credits and XP only (RP is the jet's research, left alone), and never power.

local Social = {}

-- The Roblox group (community) id. nil until Will makes the group: no group bonus, no chip, no hint.
Social.GROUP_ID = nil :: number?

Social.GROUP = table.freeze({ XP = 1.1, Credits = 1.1 }) -- +10% *(tune in playtests)*
Social.FRIENDS = table.freeze({ XP = 1.1, Credits = 1.1 }) -- +10% *(tune in playtests)*

return Social
