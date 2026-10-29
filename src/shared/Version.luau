--!strict
-- The game's version (DEVELOPMENT.md §35.2, REL-03). Semantic versions: 0.x until launch, then 1.0.0.
-- Bumped at release by hand together with CHANGELOG.md, then tagged with scripts/release.sh. CI checks
-- that the changelog has a section for this version.

local Version = {}

Version.NUMBER = "0.6.0"

-- "v0.6.0", plus the environment off production ("v0.6.0 · Test").
function Version.label(environment: string?): string
	if environment and environment ~= "Prod" then
		return `v{Version.NUMBER} · {environment}`
	end
	return `v{Version.NUMBER}`
end

-- Whether a string is a plain semantic version ("1.2.3").
function Version.valid(text: string): boolean
	return string.match(text, "^%d+%.%d+%.%d+$") ~= nil
end

return Version
