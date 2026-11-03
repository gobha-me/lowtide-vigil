#!/usr/bin/env bash
# Apply each planted mutant to a temp copy, run the unit tests, and fail if any survive.
# The real tree is never changed: everything happens under one mktemp directory.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

prefix="${TMPDIR:-/tmp}/lowtide-mutants."
dir=$(mktemp -d "${prefix}XXXXXX")
cleanup() {
	if [[ "$dir" == "$prefix"* && -d "$dir" ]]; then
		python3 -c 'import shutil,sys; shutil.rmtree(sys.argv[1])' "$dir"
	fi
}
trap cleanup EXIT

copy="$dir/repo"
mkdir "$copy"
# Tracked files plus the (possibly not yet committed) test files.
{
	git ls-files -z
	git ls-files -z --others --exclude-standard -- test
} | tar --null -T - -cf - | tar -xf - -C "$copy"

godot --headless --path "$copy" --import >"$dir/import.log" 2>&1 || {
	cat "$dir/import.log"
	echo "planted-mutants: import of the temp copy failed" >&2
	exit 1
}

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
	cat "$dir/baseline.log"
	echo "planted-mutants: baseline red: the unmutated copy does not pass" >&2
	exit 1
fi

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
	'browser-resume-start-gate|web/lowtide-vigil.html|resume();PAD.startPrev=st;|resume();if(G.state!=="play")PAD.startPrev=st;'
)

results=()
survivors=()
killed=0
for mutant in "${mutants[@]}"; do
	IFS='|' read -r name file anchor replacement <<<"$mutant"
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
	else
		results+=("KILLED $name")
		killed=$((killed + 1))
	fi
	cp "$dir/original" "$target"
done

printf '%s\n' "${results[@]}"
echo "survivors: ${survivors[*]:-}"
echo "totals: ${#mutants[@]} mutants, $killed killed, ${#survivors[@]} survived"
if ((${#survivors[@]} > 0)); then
	exit 1
fi
