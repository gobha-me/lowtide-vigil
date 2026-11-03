# Exported Linux winning playthrough

Two runs of the baseline Linux release **passed**, both at controller frame
2,680 with **3/5 HP**, **11 kills**, **18 dashes**, and the visible victory
panel. The boss entered at **100/100 HP** on frame 1,066; its second phase was
observed at **49 HP** on frame 1,889 while the keeper had 4 HP.

Complete wrapper output is tracked in
[run 1](evidence/winning-playthrough-baseline-01.log) and
[run 2](evidence/winning-playthrough-baseline-02.log). Their completion times
were **2026-11-03 02:15:23 UTC** and **2026-11-03 02:16:41 UTC**. Both include
ordinary startup, every room transition, boss/phase observations, surviving HP,
the detailed `PLAYTHROUGH PASS`, and the exact `WINNING PLAYTHROUGH: passed`
marker. Both wrapper invocations exited zero without engine or script errors.

## Reproduce

After exporting the Linux build, run from the repository root:

```bash
mkdir -p .codex-run/tmp .codex-run/evidence
export TMPDIR="$PWD/.codex-run/tmp"
export MAKEFLAGS=-j2 CMAKE_BUILD_PARALLEL_LEVEL=2
heavy-run bash tools/winning-playthrough.sh \
  > .codex-run/evidence/winning-playthrough.log 2>&1
```

An optional first argument selects another exported `.x86_64` binary with its
adjacent `.pck`. On the shared host, start outside 23:55–03:00
America/New_York. These recorded runs first received exit 75 from `heavy-run`
for memory pressure, then used the owner-authorized fallback:

```bash
flock /config/engine/loops/heavy.lock bash tools/winning-playthrough.sh \
  >> .codex-run/evidence/winning-playthrough.log 2>&1
```

Fallback is permitted only after exit 75 and outside the quiet period. Other
refusals stop execution. No import or export was needed for these baseline runs.

The wrapper prints its retained evidence directory under `TMPDIR`. It copies
the executable and PCK byte for byte, runs an ordinary startup smoke, then
writes `override.cfg` in that private directory. The config autoloads the
external Node controller; the **original packed main scene boots normally**.
The controller observes `get_tree().current_scene` once available. There is no
second scene instance. Cache, data, config and both logs stay in the private
copy. The original export and project settings remain untouched; the existing
export exclusions keep `tools/` out of the shipped build.

Each child has a 60-second wall bound with a further five-second termination
bound. Startup uses `--quit-after 120`; gameplay uses `--quit-after 18000`.
Both use `--headless --fixed-fps 60`. The wrapper rejects nonzero child exits,
`ERROR:` or `SCRIPT ERROR:` output in either stage, and a missing or incomplete
victory marker. Logs remain available on failure too.

## What the controller proves

`tools/winning-playthrough.gd` seeds RNG with 3 in `_enter_tree`. It injects
real `InputEventKey` and `InputEventJoypadMotion` through
`Input.parse_input_event`. Enter releases and panel checks occur on separate
frames. It visits the title, opens Controls, returns through Back, then starts
a fresh ordinary run using Begin. Gameplay follows:

| Room | Chosen door | Observed foes | Entry frame | Entry HP |
| --- | --- | --- | --- | --- |
| 1 | EMBERS | 4 | 145 | 5 |
| 2 | FONT | 0 | 512 | 5 |
| 3 | EMBERS | 6 | 590 | 5 |
| 4 | FONT | 0 | 988 | 5 |
| 5 | THE DROWNED TOLLING | 1 | 1066 | 5 |

The bot aims at the nearest foe, circles a rectangle below the doors, and
dashes when nearby foes or projected hostile bolts threaten it. Once combat
clears, it walks to the selected door. Keeping the combat path below the doors
prevents accidentally entering a different reward as the last foe falls.

All game properties are observations. The driver never assigns gameplay HP,
positions, damage or invulnerability; calls private gameplay methods; emits
defeat signals; mocks gameplay; or steps game time. Ordinary engine processing,
bolts, collisions, damage, healing and room transitions determine the outcome.
It rejects death, unexpected panels/transitions, a missing door and exhaustion
of its 18,000-frame budget. Failure quits nonzero without a success marker.
Victory requires the observed title/menu sequence, all five sequential rooms,
the boss starting at 100 HP, second phase, a living keeper, exactly 11 kills,
empty foe and upgrade lists, state `won`, visible overlay, victory heading
`THE TOLLING FALLS SILENT` and replay button `CARRY ANOTHER LIGHT`.

This is headless input coverage, not human visual/controller QA. It does not
assess rendering quality, physical controller ergonomics, sound or other routes.

## Artifact provenance

The baseline export contains the production source at
`5107b6e361b9c9f0b2c182b00dbd6e1d714cc27a`, built with Godot
`4.7.2.stable.official.ed1daf0bf`. These runs exercised the wrapper from source
head `60f6506c3a9f8d2bec82898973b0e9cbe7d2360a` plus this test-author change to
the external controller. Production scripts/scenes/settings have not changed
since the baseline export. The parent still needs a fresh export and wrapper
run at the final combined head.

SHA-256 (the two successful copies and original artifacts match):

```text
d9f79ab89b5ae369aeed11c6052d402e8218cd503bf85b4a235f9c30c46a7c63  lowtide-vigil.x86_64
d0a200aabc293e232e8016b59cc7a64adff0c58e470990faf48ff0221681d719  lowtide-vigil.pck
2232e8b706ab9f85de57d3bce9be1a5774ec9b94b4f0ec67c30480fae77377be  tools/winning-playthrough.gd
```

## Wrapper contract tests

`test/unit/test_winning_wrapper.gd` invokes the real shell wrapper in disposable
sandboxes. Its child executables are protocol fixtures, **not gameplay win
evidence**. The tests cover success, retained isolated logs/config, unchanged
original binary/PCK, missing binary/PCK/driver, empty PCK, nonzero child exits
even with a marker, startup/gameplay engine and script errors even with a
marker, and absent/partial/surrounded markers. Every invocation has an outer
15-second timeout. Fixtures check the child's launch arguments, working
directory, autoload timing and isolated XDG paths. Sandbox cleanup removes only
its own created files after retention assertions.

Focused validation passed: **6 GUT methods, 101 assertions**, including all
parameterized cases, with `GUT CI: passed`. The complete unit scope also passed:
**33 methods, 188 assertions**, with no errors, pending cases or orphans.
Run focused tests with the same shared-host heavy work policy:

```bash
heavy-run timeout 60s godot --headless --path "$PWD" \
  --script addons/gut/gut_cmdln.gd -gconfig= -gdir=res://test/unit \
  -gselect=test_winning_wrapper.gd \
  -gpost_run_script=res://tools/gut-ci-post-run.gd \
  -gexit -gignore_pause -gdisable_colors
```

Eight new wrapper mutants were appended to `tools/planted-mutants.sh`; the
original 20 entries and runner semantics are preserved. The parent owns the
final serial mutation run and full-suite results. The test author did not run
the full mutation suite. Local raw diagnostics and GUT output remain under
`.codex-run/evidence`; no core dump was found.
