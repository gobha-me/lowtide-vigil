#!/usr/bin/env bash
# Mount only the exported pack, so source-tree resources cannot affect the check.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pack="${1:-$root/build/linux/lowtide-vigil.pck}"
test -s "$pack"
pack=$(realpath "$pack")
scratch=$(mktemp -d "${TMPDIR:-/tmp}/lowtide-pack-check.XXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
godot --headless --path "$scratch" --main-pack "$pack" \
	--script "$root/tools/check-export.gd" 2>&1 | tee "$scratch/check.log"
if grep -Eq '(^ERROR:|^SCRIPT ERROR:)' "$scratch/check.log"; then exit 1; fi
grep -Eq '^export-pack: passed \([1-9][0-9]* files\)$' "$scratch/check.log"
