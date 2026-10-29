#!/usr/bin/env bash
# Tags a release (DEVELOPMENT.md §35, REL-03; the full checklist is docs/RELEASE.md).
#   bash scripts/release.sh            dates the changelog section, commits, and tags v<version>
#   bash scripts/release.sh --dry-run  only runs the checks
# The version comes from src/shared/Version.luau. Run on an up-to-date, clean master after the release
# build has been playtested. Nothing is pushed: the script prints the push command at the end.
set -euo pipefail

dry=0
[ "${1:-}" = "--dry-run" ] && dry=1

fail() { echo "release: $*" >&2; exit 1; }

version=$(grep -oE 'Version\.NUMBER = "[^"]*"' src/shared/Version.luau | grep -oE '"[^"]*"' | tr -d '"')
tag="v$version"
[ -n "$version" ] || fail "couldn't read Version.NUMBER from src/shared/Version.luau"

branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = "master" ] || fail "on branch $branch; releases are tagged on master"
[ -z "$(git status --porcelain)" ] || fail "the working tree has uncommitted changes"
git fetch -q origin master
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] || fail "master isn't the same as origin/master; pull or push first"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then fail "tag $tag already exists"; fi
grep -qF "## [$version]" CHANGELOG.md || fail "CHANGELOG.md has no \"## [$version]\" section"
bash scripts/ci-checks.sh >/dev/null || fail "scripts/ci-checks.sh failed; run it to see why"

# The changelog section for this version, without its heading (the tag's message)
notes=$(awk -v head="## [$version]" '
	index($0, head) == 1 { on = 1; next }
	on && /^## / { exit }
	on { print }
' CHANGELOG.md | sed -e '/./,$!d')

if [ "$dry" -eq 1 ]; then
	echo "release: checks passed; would tag $tag with these notes:"
	echo "$notes"
	exit 0
fi

today=$(date -u +%Y-%m-%d)
if grep -qF "## [$version] - Unreleased" CHANGELOG.md; then
	sed -i "s/^## \[$version\] - Unreleased\$/## [$version] - $today/" CHANGELOG.md
	git add CHANGELOG.md
	git commit -q -m "Release $tag"
fi
git tag -a --cleanup=verbatim "$tag" -m "Afterburner $tag ($today)" -m "$notes"
echo "release: tagged $tag at $(git rev-parse --short HEAD). Push it with:"
echo "  git push origin master $tag"
