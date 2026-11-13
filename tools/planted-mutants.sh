#!/usr/bin/env bash
# Apply each planted mutant to a temp copy, run the unit tests, and fail if any survive.
# The real tree is never changed: everything happens under one mktemp directory.
# Shards are zero-based: original catalog index modulo --shards selects --shard.
# With no options, run the entire catalog as shard 0 of 1.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

shard="${MUTANT_SHARD:-0}"
shards="${MUTANT_SHARDS:-1}"
manifest="${MUTANT_MANIFEST:-}"
while (($#)); do
	case "$1" in
		--shard|--shards|--manifest)
			(($# >= 2)) || { echo "planted-mutants: $1 requires a value" >&2; exit 2; }
			case "$1" in
				--shard) shard="$2" ;;
				--shards) shards="$2" ;;
				--manifest) manifest="$2" ;;
			esac
			shift 2
			;;
		-h|--help)
			echo "usage: $0 [--shard K --shards N] [--manifest PATH]"
			echo "K is zero-based; defaults: MUTANT_SHARD=0 MUTANT_SHARDS=1."
			exit 0
			;;
		*) echo "planted-mutants: unknown option $1" >&2; exit 2 ;;
	esac
done
# Bound arithmetic and reject signs, expressions and shell octal interpretation.
for number in "$shard" "$shards"; do
	if [[ ! "$number" =~ ^[0-9]{1,9}$ ]]; then
		echo "planted-mutants: shard values must be nonnegative decimal integers (at most 9 digits)" >&2
		exit 2
	fi
done
shard=$((10#$shard))
shards=$((10#$shards))
if ((shards < 1 || shard >= shards)); then
	echo "planted-mutants: require 0 <= shard < shards and shards >= 1" >&2
	exit 2
fi
manifest="${manifest:-$PWD/mutant-manifest-$shard-of-$shards.json}"

clock_ns() { python3 -c 'import time; print(time.monotonic_ns())'; }
started=$(clock_ns)
active_name=""
active_index=""
active_started=""
manifest_ready=0

# Replace atomically after every event: cancellation can never leave a complete
# manifest from an earlier attempt, or truncate the last recorded result.
manifest_update() {
	python3 - "$manifest" "$started" "$shard" "$shards" "$@" <<'MANIFEST_PY'
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import time

path = Path(sys.argv[1])
started, shard, shards = map(int, sys.argv[2:5])
event, *args = sys.argv[5:]
now = time.monotonic_ns()
if event == "init":
    catalog = args
    data = {
        "schema_version": 1, "shard": shard, "shards": shards,
        "catalog_sha256": hashlib.sha256(("\n".join(catalog) + "\n").encode()).hexdigest(),
        "complete": False,
        "baseline": {"outcome": "pending", "duration_seconds": None},
        "mutants": [],
    }
else:
    data = json.loads(path.read_text())
    if event == "baseline":
        outcome, began = args
        data["baseline"] = {"outcome": outcome, "duration_seconds": (now - int(began)) / 1e9}
        print(f"BASELINE shard={shard}/{shards} outcome={outcome} "
              f"duration_seconds={data['baseline']['duration_seconds']:.6f}", flush=True)
    elif event == "mutant":
        name, index, outcome, began = args
        result = {"name": name, "index": int(index), "shard": shard,
                  "outcome": outcome, "duration_seconds": (now - int(began)) / 1e9}
        data["mutants"].append(result)
        print(f"MUTANT name={name} index={index} shard={shard}/{shards} "
              f"outcome={outcome} duration_seconds={result['duration_seconds']:.6f}", flush=True)
    elif event == "complete":
        data["complete"] = True
    elif event != "exit":
        raise ValueError(f"unknown manifest event: {event}")
data["duration_seconds"] = (now - started) / 1e9
path.parent.mkdir(parents=True, exist_ok=True)
fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
try:
    with os.fdopen(fd, "w") as stream:
        json.dump(data, stream, indent=2, allow_nan=False)
        stream.write("\n")
    os.replace(temporary, path)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
MANIFEST_PY
}

# name|file|anchor|replacement (each anchor must occur exactly once in its file)
# PCK virtual directories expose hidden entries regardless of include_hidden;
# export-skip-hidden must explicitly filter dot directories to change traversal.
mutants=(
	'keeper-light-scale|scripts/keeper.gd|0.5 + 0.5 * float(hp)|0.5 + 0.4 * float(hp)'
	'keeper-dash-iframes|scripts/keeper.gd|if dash_left > 0.0 or invulnerable > 0.0 or hp <= 0:|if invulnerable > 0.0 or hp <= 0:'
	'keeper-hurt-window|scripts/keeper.gd|invulnerable = 1.1|invulnerable = 0.0'
	'keeper-extinguish|scripts/keeper.gd|if hp == 0:|if hp < 0:'
	'foe-elite-hp|scripts/foe.gd|max_hp *= 1.8|max_hp *= 1.0'
	'foe-boss-phase|scripts/foe.gd|if hp < max_hp * 0.5 and not second_phase:|if hp < max_hp * 0.25 and not second_phase:'
	'foe-defeat-threshold|scripts/foe.gd|if hp <= 0.0:|if hp < 0.0:'
	'bolt-lifetime|scripts/bolt.gd|if lifetime <= 0.0 or|if lifetime < -1.0 or'
	'vigil-font-heal|scripts/vigil.gd|var restored := mini(2, keeper.max_hp - keeper.hp)|var restored := mini(3, keeper.max_hp - keeper.hp)'
	'vigil-font-embers|scripts/vigil.gd|embers += 12|embers += 0'
	'vigil-wick-power|scripts/vigil.gd|keeper.damage *= 1.0 + 0.35 * power|keeper.damage *= 1.0 + 0.35'
	'vigil-bellows-floor|scripts/vigil.gd|maxf(0.08,|maxf(0.0,'
	'vigil-heal-cap|scripts/vigil.gd|keeper.hp = mini(keeper.max_hp, keeper.hp + 3)|keeper.hp = keeper.hp + 3'
	'vigil-shop-price|scripts/vigil.gd|embers -= 18|embers -= 10'
	'vigil-shop-once|scripts/vigil.gd|if embers < 18 or shop_bought:|if embers < 18:'
	'vigil-mend-full|scripts/vigil.gd|if embers < 10 or keeper.hp >= keeper.max_hp:|if embers < 10:'
	'vigil-elite-embers|scripts/vigil.gd|embers += 5 if foe.elite else 3|embers += 3'
	'vigil-room-rewards|scripts/vigil.gd|ROOM_REWARDS[mini(room, ROOM_REWARDS.size() - 1)]|ROOM_REWARDS[mini(room, ROOM_REWARDS.size() - 2)]'
	'vigil-ordeal-count|scripts/vigil.gd|count += 1|count += 0'
	'interface-hud-flames|scripts/interface.gd|"* " if index < keeper.hp else ". "|"* " if index <= keeper.hp else ". "'
	'export-allow-tests|tools/check-export.gd|path.begins_with("res://test/")|false'
	'export-allow-gut|tools/check-export.gd|path.begins_with("res://addons/gut/")|false'
	'export-ignore-rejection|tools/check-export.gd|if _failed or _files == 0:|if _files == 0:'
	'export-skip-descendants|tools/check-export.gd|_list_pack(path.path_join(child) + "/")|pass'
	'export-skip-hidden|tools/check-export.gd|for child in directory.get_directories():|for child in Array(directory.get_directories()).filter(func(item): return not item.begins_with(".")):'
	'export-wrong-file-count|tools/check-export.gd|_files += 1|_files += 2'
	'export-ignore-engine-errors|tools/check-export.sh|then exit 1; fi|then :; fi'
	'export-relative-pack-path|tools/check-export.sh|pack=$(realpath "$pack")|pack="$pack"'
	'export-preset-include-tests|export_presets.cfg|,test/*|'
	'export-preset-include-gut|export_presets.cfg|addons/gut/*,|'
	'wrapper-child-status|tools/winning-playthrough.sh|if ((result != 0)); then|if ((result < 0)); then'
	'wrapper-engine-errors|tools/winning-playthrough.sh|if grep -Eq|if false && grep -Eq'
	'wrapper-victory-required|tools/winning-playthrough.sh|if ! grep -Fxq|if false && grep -Fxq'
	'wrapper-victory-whole-line|tools/winning-playthrough.sh|grep -Fxq|grep -Fq'
	'wrapper-empty-pack|tools/winning-playthrough.sh|-s "$pack"|-f "$pack"'
	'wrapper-driver-required|tools/winning-playthrough.sh|-f "$driver"|-n "$driver"'
	'wrapper-startup-required|tools/winning-playthrough.sh|run_export startup.log --quit-after 120|: startup smoke skipped'
	'wrapper-preserve-binary|tools/winning-playthrough.sh|cp -- "$binary"|mv -- "$binary"'
	'smoke-executable-required|tools/export-smoke.sh|test -x "$binary"|test -f "$binary"'
	'smoke-nonempty-pack|tools/export-smoke.sh|test -s build/linux/lowtide-vigil.pck|test -f build/linux/lowtide-vigil.pck'
	'smoke-child-status|tools/export-smoke.sh|return "$status"|return 0'
	'smoke-engine-errors|tools/export-smoke.sh|if grep -Eq|if false && grep -Eq'
	'smoke-marker-required|tools/export-smoke.sh|grep -Fxq|: grep -Fxq'
	'smoke-marker-whole-line|tools/export-smoke.sh|grep -Fxq|grep -Fq'
	'smoke-ordinary-boot|tools/export-smoke.sh|run_smoke boot --quit-after 60|: ordinary boot skipped'
	'smoke-timeout-bound|tools/export-smoke.sh|--kill-after=5s 60s|--kill-after=5s 600s'
	'lifecycle-restart-button|scripts/vigil.gd|ui.add_button("RESTART", _start_run)|ui.add_button("RESTART", _resume_run)'
	'lifecycle-reset-facing|scripts/vigil.gd|keeper.facing = Vector2.UP|keeper.facing = Vector2.RIGHT'
	'lifecycle-reset-walking|scripts/vigil.gd|keeper.walking_time = 0.0|keeper.walking_time = 1.0'
	'lifecycle-reset-offered|scripts/vigil.gd|offered.clear()|pass # stale offers retained'
	'lifecycle-clear-foes|scripts/vigil.gd|foe.queue_free()|pass # abandoned foe'
	'lifecycle-f11-binding|scripts/controls.gd|bind_keys("toggle_fullscreen", [KEY_F11])|bind_keys("toggle_fullscreen", [KEY_F10])'
	'lifecycle-f11-repeat|scripts/vigil.gd|event.is_action_pressed("toggle_fullscreen") and not event.is_echo()|event.is_action_pressed("toggle_fullscreen", true)'
	'lifecycle-hud-paused|scripts/vigil.gd|if state != "title":|if state == "play":'
	'browser-resume-start-gate|web/lowtide-vigil.html|resume();PAD.startPrev=st;|resume();if(G.state!=="play")PAD.startPrev=st;'
)

prefix="${TMPDIR:-/tmp}/lowtide-mutants."
dir=""
cleanup() {
	local status=$?
	trap - EXIT
	if ((manifest_ready)); then
		if [[ -n "$active_name" ]]; then
			manifest_update mutant "$active_name" "$active_index" error "$active_started" || status=1
		fi
		manifest_update exit || status=1
	fi
	if [[ "$dir" == "$prefix"* && -d "$dir" ]]; then
		python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$dir" || status=1
	fi
	exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
manifest_update init "${mutants[@]}"
manifest_ready=1
echo "planted-mutants: shard=$shard/$shards manifest=$manifest"
dir=$(mktemp -d "${prefix}XXXXXX")

copy="$dir/repo"
mkdir "$copy"
# Tracked files plus the (possibly not yet committed) test files.
{
	git ls-files -z
	git ls-files -z --others --exclude-standard -- test
} | tar --null -T - -cf - | tar -xf - -C "$copy"

# Every shard imports and runs its own entire unmutated unit baseline.
baseline_started=$(clock_ns)
if ! godot --headless --path "$copy" --import >"$dir/import.log" 2>&1; then
	manifest_update baseline error "$baseline_started"
	cat "$dir/import.log"
	echo "planted-mutants: import of the temp copy failed" >&2
	exit 1
fi

# Same flags and post-run hook as CI, over the unit tests only.
run_gut() {
	godot --headless --path "$copy" --script addons/gut/gut_cmdln.gd \
		-gconfig= -gdir=res://test/unit -ginclude_subdirs -gprefix=test_ -gsuffix=.gd \
		-gpost_run_script=res://tools/gut-ci-post-run.gd \
		-gexit -gignore_pause -gdisable_colors >"$1" 2>&1
}

gut_passed() {
	local log="$1"
	run_gut "$log" || return 1
	grep -Fxq 'GUT CI: passed' "$log"
}

if ! gut_passed "$dir/baseline.log"; then
	manifest_update baseline failed "$baseline_started"
	cat "$dir/baseline.log"
	echo "planted-mutants: baseline red: the unmutated copy does not pass" >&2
	exit 1
fi
manifest_update baseline passed "$baseline_started"

results=()
survivors=()
killed=0
selected=0
for index in "${!mutants[@]}"; do
	((index % shards == shard)) || continue
	mutant="${mutants[$index]}"
	IFS='|' read -r name file anchor replacement <<<"$mutant"
	active_name="$name"
	active_index="$index"
	active_started=$(clock_ns)
	selected=$((selected + 1))
	target="$copy/$file"
	# Read verbatim, keeping trailing newlines.
	content="$(
		cat "$target"
		printf x
	)"
	content="${content%x}"
	rest="${content#*"$anchor"}"
	if [[ "$rest" == "$content" || "$rest" == *"$anchor"* ]]; then
		echo "planted-mutants: anchor for $name not found exactly once in $file" >&2
		exit 1
	fi
	before="${content%%"$anchor"*}"
	cp "$target" "$dir/original"
	printf '%s' "$before$replacement$rest" >"$target"
	if gut_passed "$dir/$name.log"; then
		results+=("SURVIVED $name")
		survivors+=("$name")
		outcome=survived
	else
		results+=("KILLED $name")
		killed=$((killed + 1))
		outcome=killed
	fi
	cp "$dir/original" "$target"
	manifest_update mutant "$name" "$index" "$outcome" "$active_started"
	active_name=""
done

manifest_update complete
printf '%s\n' "${results[@]}"
echo "survivors: ${survivors[*]:-}"
echo "totals: $selected mutants, $killed killed, ${#survivors[@]} survived (shard $shard/$shards)"
if ((${#survivors[@]} > 0)); then
	exit 1
fi
