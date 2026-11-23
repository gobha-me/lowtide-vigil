# Issue #20 ORDEAL power regressions

These tests use the real packed Vigil scene and reward API already exercised by
`test/unit/test_vigil.gd`. No game script, Keeper, or reward function is replaced.
Expectations come from [issue #20](https://github.com/gobha-me/lowtide-vigil/issues/20):
ordinary repeated Twin Wick multiplies damage by 1.25, Spare Wick grants one
current and maximum flame, and Phoenix Ash heals three. ORDEAL power 1.5 must be
strictly stronger than ordinary power 1.0 for each effect. Integer rounding is
left to the implementation; the regressions do not require an arbitrary rule.

From the project root, prepare isolated temporary state (on the burn desktop,
use a directory beneath `$CODEX_BURN_WORK`):

```sh
mkdir -p .test-state/data .test-state/config .test-state/cache
export XDG_DATA_HOME="$PWD/.test-state/data"
export XDG_CONFIG_HOME="$PWD/.test-state/config"
export XDG_CACHE_HOME="$PWD/.test-state/cache"
heavy-run godot --headless --path . --import
```

The ordinary baseline tests run with the normal `test_` discovery prefix and
the unchanged strict post-run policy. Focused command:

```sh
heavy-run timeout 60s godot --headless --path . \
  --script addons/gut/gut_cmdln.gd -gconfig= \
  -gtest=res://test/unit/test_ordeal_power_baselines.gd \
  -gpost_run_script=res://tools/gut-ci-post-run.gd \
  -gexit -gignore_pause -gdisable_colors
```

On main `18801eb`, this passes three tests and six assertions. Existing
Wick/Bellows/Light Step tests are unchanged. Full normal discovery remains:

```sh
heavy-run timeout 120s godot --headless --path . \
  --script addons/gut/gut_cmdln.gd -gconfig= -gdir=res://test \
  -ginclude_subdirs -gprefix=test_ -gsuffix=.gd \
  -gpost_run_script=res://tools/gut-ci-post-run.gd \
  -gexit -gignore_pause -gdisable_colors
```

The three known regressions are **expected-fail on main, pending #30**. Their
explicit filename starts with `pending_`, outside automatic `test_` discovery,
because the existing CI hook rejects any pending test. No CI or discovery
configuration changes. To inspect their named pending status, run explicitly
without the strict zero-pending hook:

```sh
heavy-run timeout 60s godot --headless --path . \
  --script addons/gut/gut_cmdln.gd -gconfig= \
  -gtest=res://test/known_bugs/pending_20_ordeal_power.gd \
  -gexit -gignore_pause -gdisable_colors
```

This reports three inherited baseline passes and three named pending tests.
It is an inspection command, not a green CI claim. Execute the actual
regression assertions with the strict hook for the red control:

```sh
LOWTIDE_RUN_KNOWN_BUGS=1 heavy-run timeout 60s godot --headless --path . \
  --script addons/gut/gut_cmdln.gd -gconfig= \
  -gtest=res://test/known_bugs/pending_20_ordeal_power.gd \
  -gpost_run_script=res://tools/gut-ci-post-run.gd \
  -gexit -gignore_pause -gdisable_colors
```

On unchanged main this exits 1 with exactly three failing tests: repeated Twin
damage is 2.5 for both powers, Spare gives 2/6 current/maximum flames for both,
and Phoenix gives 4/12 for both. Baselines still pass, with zero engine/script
errors, orphans, or risky cases in this opt-in run. Phoenix starts sufficiently
below its maximum so clipping cannot conceal the missing power scaling.

The CODE author owns #30. This TESTS branch neither reads its non-test diff nor
fixes the defect. After that fix lands, run the opt-in command, then promote
these regressions into normal discovery and remove the pending guard in a
separate test change. The configured planted-mutants gate remains unchanged;
it cannot demonstrate stronger reward behavior while these known bugs exist.
