#!/usr/bin/env bash
# Check the packaged game, preserving all logs for inspection.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
binary="$PWD/build/linux/lowtide-vigil.x86_64"
test -x "$binary"
test -s build/linux/lowtide-vigil.pck
scratch_root="${M2_SCRATCH:-${TMPDIR:-/tmp}}"
mkdir -p "$scratch_root"
smoke_dir=$(mktemp -d "$scratch_root/export-smoke.XXXXXXXX")
export XDG_CACHE_HOME="$smoke_dir/cache"
export XDG_DATA_HOME="$smoke_dir/data"
export XDG_CONFIG_HOME="$smoke_dir/config"
export GODOT_SILENCE_ROOT_WARNING=1
printf 'Export smoke logs: %s\n' "$smoke_dir"

run_smoke() {
  local name="$1"
  shift
  local log="$smoke_dir/$name.log"
  if timeout --signal=TERM --kill-after=5s 60s "$binary" --headless --fixed-fps 60 "$@" >"$log" 2>&1; then
    cat "$log"
  else
    local status=$?
    cat "$log"
    printf 'Export smoke %s exited %s\n' "$name" "$status" >&2
    return "$status"
  fi
  if grep -Eq '(^|[[:space:]])(SCRIPT )?ERROR:' "$log"; then
    printf 'Export smoke %s contains Godot errors\n' "$name" >&2
    return 1
  fi
}

run_smoke boot --quit-after 60
run_smoke menus --quit-after 600 -- --smoke
grep -Fxq 'EXPORT SMOKE: passed' "$smoke_dir/menus.log"
printf 'Linux export smoke: passed\n'
