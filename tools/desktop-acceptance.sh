#!/usr/bin/env bash
# Exercise only a private copy of the Linux export, retaining all evidence.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if (($# > 1)); then
	echo "usage: bash tools/desktop-acceptance.sh [exported-binary]" >&2
	exit 2
fi
binary=$(realpath -- "${1:-$root/build/linux/lowtide-vigil.x86_64}")
pack="${binary%.x86_64}.pck"
driver="$root/tools/desktop-acceptance.gd"
if [[ ! -x "$binary" || ! -s "$pack" || ! -f "$driver" ]]; then
	echo "desktop-acceptance: executable, adjacent pack and driver are required" >&2
	exit 1
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/lowtide-desktop.XXXXXX")
echo "desktop-acceptance: evidence $scratch"
cp -- "$binary" "$scratch/lowtide-vigil.x86_64"
cp -- "$pack" "$scratch/lowtide-vigil.pck"
mkdir "$scratch/cache" "$scratch/data" "$scratch/config"
export XDG_CACHE_HOME="$scratch/cache"
export XDG_DATA_HOME="$scratch/data"
export XDG_CONFIG_HOME="$scratch/config"
export GODOT_SILENCE_ROOT_WARNING=1
{
	printf 'UTC: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	git -C "$root" rev-parse HEAD
	sha256sum -- "$binary" "$pack" "$driver"
} > "$scratch/provenance.log"
cd "$scratch"

run_export() {
	local log="$1"
	shift
	local result=0
	timeout --signal=TERM --kill-after=5s 60s ./lowtide-vigil.x86_64 \
		--headless --fixed-fps 60 "$@" >"$log" 2>&1 || result=$?
	cat "$log"
	if ((result != 0)); then
		echo "desktop-acceptance: exported process failed ($result); see $log" >&2
		return 1
	fi
	if grep -Eq '(^|[[:space:]])(SCRIPT )?ERROR:' "$log"; then
		echo "desktop-acceptance: engine errors; see $log" >&2
		return 1
	fi
}

# Check ordinary boot before installing the external evidence autoload in this copy.
run_export startup.log --quit-after 120
python3 - "$driver" <<'PY'
import json
import sys
from pathlib import Path

Path("override.cfg").write_text(
    "[autoload]\nDesktopAcceptance=" + json.dumps("*" + sys.argv[1]) + "\n"
)
PY
run_export acceptance.log --quit-after 3000
markers=(
	'DESKTOP ACCEPTANCE: F11 press/echo/release 1'
	'DESKTOP ACCEPTANCE: F11 press/echo/release 2'
	'DESKTOP ACCEPTANCE: joypad sticks/release'
	'DESKTOP ACCEPTANCE: passed'
)
for device in keyboard joypad; do
	for path in controls/back pause/resume restart 'lost fixture/shore' 'won fixture/shore'; do
		markers+=("DESKTOP ACCEPTANCE: $device $path")
	done
done
for marker in "${markers[@]}"; do
	if ! grep -Fxq -- "$marker" acceptance.log; then
		echo "desktop-acceptance: missing marker '$marker'; see $scratch/acceptance.log" >&2
		exit 1
	fi
done
echo "desktop-acceptance: passed"
