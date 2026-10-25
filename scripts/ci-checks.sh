#!/usr/bin/env bash
# Repository integrity checks that run in CI (and locally: `bash scripts/ci-checks.sh`).
# Catches corrupted place files, missing strict mode, merge leftovers, broken Rojo paths
# and remote names that aren't declared in Net/Definitions.
set -uo pipefail

fail=0
error() { echo "::error::$*"; fail=1; }

# Find a working Python (Windows has a python3 stub that only opens the Store).
PY=""
for candidate in python3 python py; do
	if "$candidate" -c "import json" >/dev/null 2>&1; then PY="$candidate"; break; fi
done
[ -n "$PY" ] || error "no working Python found (needed for JSON checks)"

# 1. Place file is a real binary Roblox place (not truncated, not an LFS pointer, not text).
for place in *.rbxl; do
	[ -e "$place" ] || continue
	header=$(head -c 8 "$place")
	size=$(wc -c < "$place")
	if [ "$header" != "<roblox!" ]; then error "$place is not a binary Roblox place (bad header)"; fi
	if [ "$size" -lt 4096 ]; then error "$place is suspiciously small ($size bytes)"; fi
done

# 2. Every Luau file declares a type-checking mode on its first line.
while IFS= read -r file; do
	first=$(head -n 1 "$file")
	case "$first" in
		"--!strict"|"--!nonstrict"*) ;;
		*) error "$file must start with --!strict (or --!nonstrict with a reason)";;
	esac
done < <(find src tests tools -name '*.luau' -type f)

# 3. No merge-conflict markers in tracked text files.
if git grep -nIE '^(<<<<<<<|>>>>>>>)( |$)' -- . ':!scripts/ci-checks.sh' >/dev/null; then
	git grep -nIE '^(<<<<<<<|>>>>>>>)( |$)' -- . ':!scripts/ci-checks.sh'
	error "merge-conflict markers found"
fi

# 4. Rojo project is valid JSON and every $path exists.
if [ -z "$PY" ]; then
	:
elif ! "$PY" -c 'import json,sys; json.load(open("default.project.json"))' 2>/dev/null; then
	error "default.project.json is not valid JSON"
else
	while IFS= read -r path; do
		path=${path%$'\r'}
		[ -e "$path" ] || error "default.project.json points at missing path: $path"
	done < <("$PY" -c '
import json
def walk(node):
    if isinstance(node, dict):
        if "$path" in node: print(node["$path"])
        for v in node.values(): walk(v)
walk(json.load(open("default.project.json")))')
fi

# 5. Every remote used in code is declared in Net/Definitions.
defs="src/shared/Net/Definitions.luau"
declared=$(grep -oE $'^\t[A-Za-z0-9_]+ = \\{' "$defs" | awk '{print $1}' | sort -u)
used=$(grep -rhoE 'Net\.(Server|Client)\.(on|handle|fire|fireAll|fireList|invoke)\("[A-Za-z0-9_]+"' src \
	| grep -oE '"[A-Za-z0-9_]+"' | tr -d '"' | sort -u)
for name in $used; do
	if ! grep -qx "$name" <<< "$declared"; then error "remote \"$name\" is used but not declared in $defs"; fi
done

if [ "$fail" -ne 0 ]; then
	echo "Integrity checks FAILED"
	exit 1
fi
echo "Integrity checks passed ($(wc -l <<< "$declared") remotes declared, $(wc -w <<< "$used") used)"
