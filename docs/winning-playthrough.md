# Exported Linux playthrough evidence

Status: **blocked; no exported win has been demonstrated.** The external driver
passes Godot's parser and gdtoolkit checks, but the baseline Linux release
executable does not execute `--script`. Combat and menu automation in this driver
remain unvalidated. Do not count its presence, parser success, or a normal title
launch as a passing playthrough.

The inspected baseline is commit `5107b6e`, exported with Godot
`4.7.2.stable.official.ed1daf0bf`. No production code, export preset, workflow,
existing assertions, or existing mutants were changed for this investigation.

## Driver contract

`tools/winning-playthrough.gd` is an external `SceneTree` script, excluded from
export by the existing preset. It loads `res://scenes/vigil.tscn`; it does not
load production scripts from the checkout or depend on packed tests/addons.

The driver injects `InputEventKey` and `InputEventJoypadMotion` through
`Input.parse_input_event`. Keyboard input visits Controls, returns to the title,
and activates Begin. Analog stick input moves and aims at the nearest foe;
Space dashes when a projectile or foe threatens the keeper. A rectangular route
kites foes. Only cleared rooms permit steering into a chosen doorway.

All references to game properties are observations. The driver does not call
gameplay methods, step the game directly, mutate gameplay fields, replace any
implementation, or emit combat signals. A fixed RNG seed of 3 is the only
simulation setup. The intended route is:

1. EMBERS: four ordinary foes.
2. FONT: real healing and immediate room clear.
3. EMBERS: six ordinary foes.
4. FONT: real healing and immediate room clear.
5. THE DROWNED TOLLING: the ordinary 100 HP boss.

The driver fails on death, an unexpected panel/transition, a missing door, or
18,000 controller frames. Before its single `PLAYTHROUGH PASS` line it requires
all five transitions, an observed boss starting at 100/100 HP, observed second
phase, 11 actual kills, empty foe and upgrade lists, positive keeper HP, and the
visible victory panel and replay button. The final line reports frame, HP,
phase, kills, dashes, and route. These are intended assertions, **not observed
outcomes in this investigation**.

## Observed blocker

The release binary's own `--help` identifies a release export template and does
not list `--script`, `--main-loop`, or `--check-only`. The editor's help marks
these options as available only in editor builds and templates compiled with
`disable_path_overrides=false`. The baseline release ignores `--script` rather
than rejecting the option: even a minimal external print-and-quit script never
prints, and tracing shows the executable loading the normal packed main scene
and gameplay resources instead of opening the external script.

Thus the driver frame budget cannot run in this binary. A wall timeout is
essential, and a zero exit alone would not prove that the driver ran. The
initial long-running probes were headless title sessions without a controller,
not evidence that gameplay or the driver froze. No production gameplay defect
was established. The parent must decide on a supported external injection
method or export-template change before gameplay diagnostics resume. Replacing
the release executable with the editor would not satisfy this test's contract.

## Commands and retained evidence

All commands were run within this worktree with `MAKEFLAGS=-j2`,
`CMAKE_BUILD_PARALLEL_LEVEL=2`, `GODOT_SILENCE_ROOT_WARNING=1`, and
`TMPDIR="$PWD/.codex-run/tmp"`. Each heavy command was first attempted as
`heavy-run COMMAND`. All returned 75 for memory pressure; only then the same
command ran under `flock /config/engine/loops/heavy.lock`. Runs began around
21:06 America/New_York on 2026-11-02, outside the quiet period. No import,
export, or mutation suite was run by the test author.

The following are the exact fallback command bodies. Set `workspace` to this
worktree's absolute path and first change directory to
`"$workspace/.codex-run/tmp/playthrough-cwd"` (created empty, without a
`project.godot`). Godot internally changes to its executable directory to use
the adjacent PCK.

Normal launch, without any script option, passed with exit 0:

```bash
flock /config/engine/loops/heavy.lock timeout 20s \
  strace -f -e trace=file,connect \
  -o "$workspace/.codex-run/evidence/startup-smoke-strace.log" \
  "$workspace/build/linux/lowtide-vigil.x86_64" \
  --headless --fixed-fps 60 --quit-after 120 \
  > "$workspace/.codex-run/evidence/startup-smoke-fallback.log" 2>&1
```

The external driver attempt timed out with exit 124 and no driver markers:

```bash
flock /config/engine/loops/heavy.lock timeout 120s \
  "$workspace/build/linux/lowtide-vigil.x86_64" \
  --headless --fixed-fps 60 \
  --script "$workspace/tools/winning-playthrough.gd" \
  > "$workspace/.codex-run/evidence/playthrough-attempt-01-fallback.log" 2>&1
```

`playthrough-attempt-02-fallback.log` repeats the failure with a 60-second
timeout and `--accessibility disabled`; that flag did not resolve it.
`external-script-probe-fallback.log` and
`external-script-probe-02-fallback.log` retain the 15-second minimal-script
failures. The latter used `strace -f -e trace=file,connect`, retained in
`external-script-trace.log`. The probe in
`.codex-run/tmp/minimal-driver.gd` contains only:

```gdscript
extends SceneTree
func _initialize() -> void:
    print("EXTERNAL SCRIPT PROBE")
    quit(0)
```

The actual release help is retained in `exported-help-fallback.log`:

```bash
flock /config/engine/loops/heavy.lock timeout 10s \
  "$workspace/build/linux/lowtide-vigil.x86_64" --help \
  > "$workspace/.codex-run/evidence/exported-help-fallback.log" 2>&1
```

Main-thread backtraces and a short attached syscall trace from the first
attempt remain in `playthrough-attempt-01-*-backtrace.log`,
`playthrough-attempt-01-backtrace.log`, and
`playthrough-attempt-01-strace.log`. A second backtrace is in
`playthrough-attempt-02-backtrace.log`. No core dump was found in the worktree.

Editor **parse-only** validation passed after correcting an inferred vector
type; this did not execute the driver or count as exported gameplay evidence:

```bash
flock /config/engine/loops/heavy.lock timeout 20s godot \
  --headless --path "$workspace" \
  --script "$workspace/tools/winning-playthrough.gd" --check-only \
  > "$workspace/.codex-run/evidence/playthrough-parse-02-fallback.log" 2>&1
```

Style and terminology commands (run from the worktree root):

```bash
/config/engine/tools/venv/bin/gdlint \
  scripts tools/gut-ci-post-run.gd tools/winning-playthrough.gd
/config/engine/tools/venv/bin/gdformat --check \
  scripts tools/gut-ci-post-run.gd tools/winning-playthrough.gd
git add tools/winning-playthrough.gd docs/winning-playthrough.md
bash tools/term-gate.sh
```

Their final results are retained in `.codex-run/evidence/playthrough-checks.log`.
Binary, PCK, and driver hashes are in `playthrough-artifacts.sha256`.

## Acceptance after the launch blocker is resolved

Keep the normal startup smoke separate. Launch the actual exported executable
with the external driver from a scratch directory, `--fixed-fps 60`, an engine
frame bound (`--quit-after 18001`), and a wall timeout. Retain the complete log.
Require all of the following together: exit 0, exactly one complete
`PLAYTHROUGH PASS` line, the expected title/controls/begin/room/boss/phase
markers, positive surviving HP, and no `ERROR:`, `SCRIPT ERROR:`, or
`PLAYTHROUGH FAIL` diagnostics. Reject timeout, nonzero exit, and a missing
marker even if the executable itself exits successfully. Repeat once to check
reproducibility and record both frame/HP outcomes.

No executable shell gate or CI integration was added; this document retains
the manual command and validation contract. There are no new gate mutants to
run. The parent retains responsibility for the final existing mutation suite
and for completing exported gameplay validation after resolving the blocker.
