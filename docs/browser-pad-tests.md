# Browser controller regression tests

The GUT test `test/unit/test_browser_pad.gd` runs the Node.js harness in
`test/helpers/browser_pad_harness.cjs`. It is discovered by the existing CI
command (`-gdir=res://test -ginclude_subdirs`) and by the planted mutant
runner's unit test command. No CI changes or npm packages are required.
**Node.js 18 or newer must be on PATH as `node`** (also available on the
Ubuntu Actions runner). Missing Node or a failed harness fails GUT.

For a quick check from the repository root:

```sh
node test/helpers/browser_pad_harness.cjs
godot --headless --path . --script addons/gut/gut_cmdln.gd \
  -gconfig= -gdir=res://test -ginclude_subdirs -gprefix=test_ -gsuffix=.gd \
  -gselect=test_browser_pad.gd \
  -gpost_run_script=res://tools/gut-ci-post-run.gd \
  -gexit -gignore_pause -gdisable_colors
```

The harness loads the actual inline JavaScript from `web/lowtide-vigil.html`
into a fresh VM per case. It replaces only the terminal `boot()` call with
an export of the existing closure variables and functions; it never replaces
`padMenus`, `pollPad`, `resume`, `showPause`, or their UI helpers. Fixtures
provide the DOM, canvas pixel buffer, focus timers, and Gamepad API. The real
Resume button listener runs in the A-button cases. Startup, rendering, audio
hardware, and the full gameplay loop are outside this focused check.

The cases call `padMenus()` then `pollPad()` in the order used by `frame()`
and `update()`, including repeated polls for catch-up updates. They cover
Start resume and continued holds, release and the next press pausing once,
another release/press resuming once, simultaneous A/Start, release during
A-button resume, other menus, missing/disconnected gamepads, and empty menu
focus. The planted mutant `browser-resume-start-gate` restores the original
state-dependent latch gate; these tests must reject it.

For red/green verification without touching the working browser file, the
harness also accepts a path to a temporary HTML copy as its first argument.
Restore the original bug in that copy by changing the unique anchor
`resume();PAD.startPrev=st;` to
`resume();if(G.state!=='play')PAD.startPrev=st;`. The harness must exit 1;
running against the unchanged working file must exit 0. The same mutation
can be checked through targeted GUT with a temporary working-file edit and
a `finally`/shell trap that restores its exact original bytes. Full import,
export, and mutation jobs should use the shared host's locks.

Verified with Node.js v22.23.4 and Godot 4.7.2/GUT 9.6.1: the targeted GUT
command above exited 1 with `GUT CI: failed` against the actual pre-fix HTML
from `7e0f1b5^` (six harness cases failed). After restoring the working HTML
byte-for-byte, it exited 0 with `GUT CI: passed`; all eight Node cases
passed. Applying the new mutant entry to a temporary HTML copy also made
the Node harness exit 1. No import, export, full suite, or full mutation job
was run for this focused verification.
