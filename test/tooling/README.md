# Mutant sharding contract tests

The normal CI GUT command discovers `test_mutant_shards.gd` recursively. It
runs the real aggregate checker against catalog-derived JSON fixtures and
checks that malformed runner options fail before any mutation starts:

```sh
python3 test/tooling/test_mutant_shards.py -v
python3 test/tooling/test_mutant_runner.py RunnerOptionsTests -v
```

The separate runner protocol suite invokes the unchanged real runner and
catalog in an isolated temporary Git tree. Only the Godot child-process
boundary is a protocol fixture. These tests verify runner selection,
manifest persistence and failure handling; they do not measure gameplay
mutation coverage. Because the real runner applies temporary mutants, run
this suite under the shared mutation lock and heavy-work wrapper, after the
lane SHA/time/load checks, with all scratch and caches under `LANE_TMP`:

```sh
bash "$LANE_TEMP_HEAVY" -- bash -c \
  'ulimit -c 0; exec flock /coord/engine-mutation.lock /config/.local/bin/heavy-run "$@"' \
  bash python3 test/tooling/test_mutant_runner.py RunnerProtocolTests -v
```

Use `MUTANT_TEST_ROOT=/path/to/source` to run the same Python tests against
another unmodified source revision. Missing tooling must fail; the tests
never skip it. Expected names, indices and catalog digest are read from the
actual literal catalog rather than maintained as another name list.

The GUT wrapper lives outside `test/unit`, so the planted runner's unit
baseline does not recursively execute its own protocol suite.
