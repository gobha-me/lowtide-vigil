#!/usr/bin/env python3
"""Real runner contracts, with Godot represented only at its process boundary.

RunnerOptionsTests rejects input before mutation and may run as an ordinary test.
RunnerProtocolTests applies the unchanged catalog to disposable source copies:
run ONLY under the shared mutation lock and heavy-run, e.g.:
flock /coord/engine-mutation.lock heavy-run python3 test/tooling/test_mutant_runner.py
The protocol fixture supplies engine exits, not gameplay mutation evidence.
"""

import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(os.environ.get("MUTANT_TEST_ROOT", Path(__file__).resolve().parents[2]))
ENGINE = r'''#!/usr/bin/env python3
import json, os, signal, sys, time
from pathlib import Path
state = Path(os.environ["PROTOCOL_STATE"])
calls = json.loads(state.read_text()) if state.exists() else []
calls.append(sys.argv[1:])
state.write_text(json.dumps(calls))
mode = os.environ.get("PROTOCOL_MODE", "killed")
if mode == "options":
    sys.exit(99)  # An old runner that ignores invalid flags must stop before mutation.
if "--import" in sys.argv:
    sys.exit(9 if mode == "import_error" else 0)
gut = sum("--script" in args for args in calls)
if gut == 1:
    print("GUT CI: passed")
    sys.exit(7 if mode == "red_baseline" else 0)
if mode == "interrupt_second" and gut == 3:
    ready = Path(os.environ["PROTOCOL_READY"])
    ready.write_text("ready")
    deadline = time.monotonic() + 10
    while not ready.with_suffix(".release").exists():
        if time.monotonic() >= deadline:
            sys.exit(88)
        time.sleep(.01)
    os.kill(os.getppid(), signal.SIGTERM)
    sys.exit(1)
if mode == "survive" and gut == 2:
    print("GUT CI: passed")
    sys.exit(0)
print("GUT CI: failed")
sys.exit(1)
'''


class RunnerFixture(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="runner-contract-", dir=os.environ["TMPDIR"])
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        source = (ROOT / "tools/planted-mutants.sh").read_text()
        block = re.findall(r"^mutants=\(\s*\n(.*?)^\)\s*$", source, re.M | re.S)
        self.assertEqual(len(block), 1)
        self.entries = shlex.split(block[0], comments=True)
        self.names = [entry.split("|", 1)[0] for entry in self.entries]
        self.assertEqual(len(self.names), 55)
        paths = {"tools/planted-mutants.sh"}
        paths.update(entry.split("|", 3)[1] for entry in self.entries)
        for relative in paths:
            target = self.repo / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        for args in (["init", "-q"], ["add", "."]):
            subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.bin / "godot").write_text(ENGINE)
        (self.bin / "godot").chmod(0o755)
        self.state = self.root / "calls.json"
        self.manifest = self.root / "manifest.json"
        self.ready = self.root / "ready"
        self.env = os.environ.copy()
        for key in ("MUTANT_SHARD", "MUTANT_SHARDS", "MUTANT_MANIFEST"):
            self.env.pop(key, None)
        self.env.update(PATH=str(self.bin) + os.pathsep + self.env["PATH"],
                        PROTOCOL_STATE=str(self.state), PROTOCOL_READY=str(self.ready),
                        MUTANT_MANIFEST=str(self.manifest))

    def run_runner(self, *args, mode="killed", env=None):
        environment = dict(self.env, PROTOCOL_MODE=mode)
        environment.update(env or {})
        return subprocess.run(["bash", "tools/planted-mutants.sh", *args], cwd=self.repo,
                              env=environment, text=True, capture_output=True, timeout=90)

    def calls(self):
        return json.loads(self.state.read_text()) if self.state.exists() else []


class RunnerOptionsTests(RunnerFixture):
    def run_runner(self, *args, mode="options", env=None):
        return super().run_runner(*args, mode=mode, env=env)

    def test_invalid_options_fail_before_engine_or_manifest(self):
        cases = [
            (["--shard"], "requires a value"), (["--shards"], "requires a value"),
            (["--manifest"], "requires a value"), (["--wat"], "unknown option"),
            (["--shard", "-1"], "nonnegative decimal"),
            (["--shard", "1+1"], "nonnegative decimal"),
            (["--shard", "1.0"], "nonnegative decimal"),
            (["--shards", ""], "nonnegative decimal"),
            (["--shards", "1000000000"], "nonnegative decimal"),
            (["--shards", "0"], "require 0 <= shard"),
            (["--shard", "4", "--shards", "4"], "require 0 <= shard"),
        ]
        for args, diagnostic in cases:
            with self.subTest(args=args):
                result = self.run_runner(*args)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn(diagnostic, result.stderr)
                self.assertEqual(self.calls(), [])
                self.assertFalse(self.manifest.exists())

    def test_invalid_environment_is_rejected_before_engine(self):
        for env in ({"MUTANT_SHARD": "-1"}, {"MUTANT_SHARDS": "0"},
                    {"MUTANT_SHARD": "4", "MUTANT_SHARDS": "4"}):
            with self.subTest(env=env):
                result = self.run_runner(env=env)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn("planted-mutants:", result.stderr)
                self.assertEqual(self.calls(), [])
                self.assertFalse(self.manifest.exists())

    def test_help_does_not_start_baseline_or_mutation(self):
        result = self.run_runner("--help")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("--shard K --shards N", result.stdout)
        self.assertEqual(self.calls(), [])
        self.assertFalse(self.manifest.exists())


class RunnerProtocolTests(RunnerFixture):
    def assert_manifest(self, shard, shards, output):
        manifest = json.loads(self.manifest.read_text())
        self.assertEqual(manifest["schema_version"], 1)
        self.assertIs(manifest["complete"], True)
        self.assertEqual((manifest["shard"], manifest["shards"]), (shard, shards))
        digest = hashlib.sha256(("\n".join(self.entries) + "\n").encode()).hexdigest()
        self.assertEqual(manifest["catalog_sha256"], digest)
        expected = [(index, name) for index, name in enumerate(self.names) if index % shards == shard]
        self.assertEqual([(record["index"], record["name"]) for record in manifest["mutants"]], expected)
        self.assertEqual(manifest["baseline"]["outcome"], "passed")
        for record in [manifest, manifest["baseline"], *manifest["mutants"]]:
            self.assertIsInstance(record["duration_seconds"], (int, float))
            self.assertTrue(math.isfinite(record["duration_seconds"]))
            self.assertGreaterEqual(record["duration_seconds"], 0)
            self.assertLessEqual(record["duration_seconds"], manifest["duration_seconds"])
        lines = [line for line in output.splitlines() if line.startswith("MUTANT ")]
        self.assertEqual(len(lines), len(expected))
        for line, record in zip(lines, manifest["mutants"]):
            self.assertRegex(line, rf"^MUTANT name={record['name']} index={record['index']} "
                             rf"shard={shard}/{shards} outcome={record['outcome']} duration_seconds=\d+\.\d+$")
            self.assertEqual(record["shard"], shard)
        gut_calls = [args for args in self.calls() if "--script" in args]
        self.assertEqual(len(gut_calls), 1 + len(expected))
        self.assertEqual(sum("--import" in args for args in self.calls()), 1)
        for args in gut_calls:
            self.assertIn("-gdir=res://test/unit", args)
            self.assertIn("-gpost_run_script=res://tools/gut-ci-post-run.gd", args)
        return manifest

    def test_default_runs_all_55_in_catalog_order(self):
        result = self.run_runner()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        data = self.assert_manifest(0, 1, result.stdout)
        self.assertTrue(all(record["outcome"] == "killed" for record in data["mutants"]))
        self.assertIn("55 mutants, 55 killed, 0 survived", result.stdout)

    def test_every_shard_has_full_baseline_and_cli_matches_environment(self):
        explicit = None
        for shard in range(4):
            with self.subTest(shard=shard):
                self.state.unlink(missing_ok=True)
                result = self.run_runner("--shard", str(shard), "--shards", "4")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                data = self.assert_manifest(shard, 4, result.stdout)
                self.assertEqual(len(data["mutants"]), [14, 14, 14, 13][shard])
                if shard == 1:
                    explicit = [(r["index"], r["name"], r["outcome"]) for r in data["mutants"]]
        self.state.unlink()
        result = self.run_runner(env={"MUTANT_SHARD": "1", "MUTANT_SHARDS": "4"})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        data = self.assert_manifest(1, 4, result.stdout)
        self.assertEqual([(r["index"], r["name"], r["outcome"]) for r in data["mutants"]], explicit)

    def test_red_baseline_or_import_error_replaces_stale_success(self):
        for mode, outcome in (("red_baseline", "failed"), ("import_error", "error")):
            with self.subTest(mode=mode):
                self.state.unlink(missing_ok=True)
                self.manifest.write_text('{"complete":true,"mutants":[{"name":"stale"}]}')
                result = self.run_runner("--shard", "1", "--shards", "4", mode=mode)
                self.assertNotEqual(result.returncode, 0)
                data = json.loads(self.manifest.read_text())
                self.assertIs(data["complete"], False)
                self.assertEqual(data["baseline"]["outcome"], outcome)
                self.assertEqual(data["mutants"], [])
                self.assertGreaterEqual(data["duration_seconds"], data["baseline"]["duration_seconds"])
                self.assertNotIn("MUTANT ", result.stdout)
                self.assertEqual(len(self.calls()), 2 if mode == "red_baseline" else 1)

    def test_surviving_case_fails_even_with_complete_manifest(self):
        result = self.run_runner("--shard", "0", "--shards", "55", mode="survive")
        self.assertNotEqual(result.returncode, 0)
        data = self.assert_manifest(0, 55, result.stdout)
        self.assertEqual(data["mutants"][0]["outcome"], "survived")
        self.assertIn("1 mutants, 0 killed, 1 survived", result.stdout)

    def test_immediate_result_is_persisted_when_next_case_is_interrupted(self):
        env = dict(self.env, PROTOCOL_MODE="interrupt_second")
        log = self.root / "runner.log"
        with log.open("w+") as stream:
            process = subprocess.Popen(["bash", "tools/planted-mutants.sh", "--shard", "0", "--shards", "4"],
                                       cwd=self.repo, env=env, stdout=stream, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 15
                while not self.ready.exists() and process.poll() is None and time.monotonic() < deadline:
                    time.sleep(.01)
                self.assertTrue(self.ready.exists(), log.read_text())
                current = json.loads(self.manifest.read_text())
                self.assertIs(current["complete"], False)
                self.assertEqual([(r["index"], r["outcome"]) for r in current["mutants"]], [(0, "killed")])
                self.assertIn(f"MUTANT name={self.names[0]} index=0 shard=0/4 outcome=killed", log.read_text())
                self.ready.with_suffix(".release").write_text("release")
                self.assertNotEqual(process.wait(timeout=15), 0)
            finally:
                self.ready.with_suffix(".release").write_text("release")
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=15)
        data = json.loads(self.manifest.read_text())
        self.assertIs(data["complete"], False)
        self.assertEqual([(r["index"], r["outcome"]) for r in data["mutants"]], [(0, "killed"), (4, "error")])
        self.assertNotIn("totals:", log.read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
