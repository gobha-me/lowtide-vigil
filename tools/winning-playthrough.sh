#!/usr/bin/env bash
# Exercise a copied Linux export; keep the original binary and pack untouched.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if (($# > 1)); then
	echo "usage: bash tools/winning-playthrough.sh [exported-binary]" >&2
	exit 2
fi
binary=$(realpath -- "${1:-$root/build/linux/lowtide-vigil.x86_64}")
pack="${binary%.x86_64}.pck"
driver="$root/tools/winning-playthrough.gd"
if [[ ! -x "$binary" || ! -s "$pack" || ! -f "$driver" ]]; then
	echo "winning-playthrough: executable, adjacent pack and driver are required" >&2
	exit 1
fi

scratch=$(mktemp -d "${TMPDIR:-/tmp}/lowtide-playthrough.XXXXXX")
echo "winning-playthrough: evidence $scratch"
cp -- "$binary" "$scratch/lowtide-vigil.x86_64"
cp -- "$pack" "$scratch/lowtide-vigil.pck"
mkdir "$scratch/cache" "$scratch/data" "$scratch/config"
export XDG_CACHE_HOME="$scratch/cache"
export XDG_DATA_HOME="$scratch/data"
export XDG_CONFIG_HOME="$scratch/config"
export GODOT_SILENCE_ROOT_WARNING=1
cd "$scratch"

run_export() {
	local log="$1"
	shift
	local result=0
	timeout --signal=TERM --kill-after=5s 60s ./lowtide-vigil.x86_64 \
		--headless --fixed-fps 60 "$@" >"$log" 2>&1 || result=$?
	cat "$log"
	if ((result != 0)); then
		echo "winning-playthrough: exported process failed ($result); see $log" >&2
		return 1
	fi
	if grep -Eq '(^|[[:space:]])(SCRIPT )?ERROR:' "$log"; then
		echo "winning-playthrough: engine errors; see $log" >&2
		return 1
	fi
}

# Verify ordinary boot before adding the test-only autoload to this private copy.
run_export startup.log --quit-after 120
python3 - "$driver" <<'PY'
import json
import sys
from pathlib import Path

Path("override.cfg").write_text(
    "[autoload]\nWinningPlaythrough=" + json.dumps("*" + sys.argv[1]) + "\n"
)
PY
run_export playthrough.log --quit-after 18000
if ! grep -Fxq 'WINNING PLAYTHROUGH: passed' playthrough.log; then
	echo "winning-playthrough: missing victory marker; see $scratch/playthrough.log" >&2
	exit 1
fi
echo "winning-playthrough: passed"
