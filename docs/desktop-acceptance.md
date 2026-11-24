# Native desktop and controller input evidence

Issue #17 covers synthetic input and menu behavior on the real Level 1 scene.
Run the external driver against a freshly exported Linux release:

```bash
heavy-run bash tools/desktop-acceptance.sh
# Or pass an explicit exported binary with its adjacent .pck:
heavy-run bash tools/desktop-acceptance.sh /path/to/lowtide-vigil.x86_64
```

On the shared Engine desktop, use the pinned absolute heavy-run path and
desktop temp-heavy wrapper required by the lane rules. Imports, exports,
GUT and mutation validation remain separate gates; this command adds no CI
workflow changes. Set `TMPDIR` to the lane's private scratch directory.

The wrapper copies the binary and pack into a unique
`$TMPDIR/lowtide-desktop.*` directory. It checks ordinary boot, then adds an
external autoload to that copy using `override.cfg`. The shipped project and
original export stay untouched; `tools/*` remains excluded from the pack.
Each invocation retains `startup.log`, `acceptance.log`, `provenance.log`,
the isolated XDG directories and the copied export. Provenance includes UTC,
the checkout commit and SHA-256 of the original binary, pack and driver.
Keep those files together when recording a result. The checkout commit
identifies the driver source; the pack hash identifies the tested artifact
and does not by itself prove that an older export matches that commit.

Both child processes have 60-second deadlines. The traversal also has a
2,400-frame budget and the engine exits after at most 3,000 frames. Nonzero
exits, timeouts, engine/script errors, missing final success and missing
individual path markers all fail the wrapper. Logs remain on failure.

The driver injects press/release events through Godot's input pipeline:

- Keyboard Down/Enter and controller D-pad/A navigate title → controls →
  back → begin. Every panel must own the expected visible, enabled button
  focus. Closed overlays must release focus.
- Esc and controller Start each pause and resume. Both device paths select
  Restart, verify a fresh run, and return from pause to a clean shore.
- Left-stick motion moves the keeper; right-stick motion fires real friendly
  bolts. Both axes must return to zero when released.
- Each device navigates both ending panels back to shore. The driver calls
  the real `_lose_run` / `_win_run` handlers solely to stage those panels.
  These are explicit menu fixtures, not evidence of a combat loss or win.
  The separate [winning playthrough](winning-playthrough.md) exercises a
  complete win through ordinary gameplay input.
- F11 is pushed through the real viewport twice. Each press must be handled;
  echo and release must be ignored. With a window-capable display server,
  the driver also requires fullscreen/windowed transitions and restoration.
  With the headless display server it prints
  `DESKTOP ACCEPTANCE: headless window-mode transitions unverified` because
  that backend cannot establish actual display changes.

`DESKTOP ACCEPTANCE: passed` means those automatable checks completed. It
does not establish physical controller ergonomics, visible focus contrast,
sound, rendered output or actual fullscreen transitions on a headless backend.

Independent test-author coverage lives in
`test/unit/test_vigil_controls_contract.gd` (exact native bindings and deadzones),
`test/unit/test_native_controller_input.gd` (real scene/controller/menu paths)
and `test/unit/test_desktop_acceptance_wrapper.gd` (wrapper boundary failures,
artifact preservation and retained evidence). Protocol executables in the
wrapper tests provide no gameplay or display evidence. Existing assertions
and the separate F11 screen coverage remain unchanged.

No runtime result is recorded for this implementation yet. The first import
attempt on 2026-11-13 was refused by the desktop temp-heavy lock with exit 75;
the exported driver, GUT, mutation baseline/survivors and export smoke still
require validation before acceptance.
