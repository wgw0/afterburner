--!strict
-- The friends bonus on match rewards (DEVELOPMENT.md §25.8; rules in Shared/Social): a Roblox friend or a party
-- member flew in the same match. Its own line on the results screen. Credits and XP only (RP is the jet's
-- research, left alone), and never power. Nothing rewards likes or favourites (docs/COMPLIANCE.md §8).

local Social = {}

Social.FRIENDS = table.freeze({ XP = 1.1, Credits = 1.1 }) -- +10% *(tune in playtests)*

return Social
