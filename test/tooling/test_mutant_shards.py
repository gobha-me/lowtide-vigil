#!/usr/bin/env python3
"""Adversarial JSON inputs for the real aggregate checker; no mutations run.

Run: python3 -m unittest discover -s test/tooling -p test_mutant_shards.py -v
MUTANT_TEST_ROOT selects an unmodified alternate source tree for red evidence.
All fixture names, indices and the manifest digest come from the real catalog.
"""

import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import unittest


SOURCE_ROOT = Path(os.environ.get("MUTANT_TEST_ROOT", Path(__file__).resolve().parents[2]))
CHECKER = SOURCE_ROOT / "tools/check-mutant-shards.py"
CATALOG = SOURCE_ROOT / "tools/planted-mutants.sh"


class MutantShardCheckerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Parse the source as data independently; never import the checker or runner.
        source = CATALOG.read_text(encoding="utf-8")
        match = re.search(r"^mutants=\(\s*\n(.*?)^\)\s*$", source, re.M | re.S)
        if match is None:
            raise AssertionError("the real planted-mutant catalog must be present")
        cls.entries = shlex.split(match.group(1), comments=True)
        cls.names = [entry.split("|", 1)[0] for entry in cls.entries]
        cls.digest = hashlib.sha256(("\n".join(cls.entries) + "\n").encode()).hexdigest()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(
            prefix="mutant-shard-checker-tests-", dir=os.environ.get("TMPDIR")
        )
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.case_number = 0

    def fixtures(self):
        return [
            {
                "schema_version": 1,
                "shard": shard,
                "shards": 4,
                "catalog_sha256": self.digest,
                "complete": True,
                "duration_seconds": 2.0,
                "baseline": {"outcome": "passed", "duration_seconds": 0.5},
                "mutants": [
                    {
                        "name": name,
                        "index": index,
                        "shard": shard,
                        "outcome": "killed",
                        "duration_seconds": 0.01,
                    }
                    for index, name in enumerate(self.names)
                    if index % 4 == shard
                ],
            }
            for shard in range(4)
        ]

    def write_manifests(self, manifests=None, nested=False):
        self.case_number += 1
        folder = self.root / str(self.case_number)
        folder.mkdir()
        for index, manifest in enumerate(self.fixtures() if manifests is None else manifests):
            target = folder / (f"artifact-{index}" if nested else "")
            target.mkdir(exist_ok=True)
            (target / f"shard-{index}.json").write_text(json.dumps(manifest), encoding="utf-8")
        return folder

    def run_checker(self, *arguments):
        return subprocess.run(
            [sys.executable, str(CHECKER), *map(str, arguments)],
            cwd=SOURCE_ROOT,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )

    def check_fixtures(self, manifests):
        return self.run_checker("--shards", "4", self.write_manifests(manifests))

    def assert_rejected(self, result, *diagnostics):
        output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0, output)
        for diagnostic in diagnostics:
            self.assertIn(diagnostic, output)
        self.assertNotIn("mutant-shards: PASS:", output)

    def test_full_real_catalog_killed_exactly_once(self):
        self.assertEqual(len(self.names), 55)
        self.assertEqual(len(set(self.names)), len(self.names))
        manifests = self.fixtures()
        self.assertEqual([len(m["mutants"]) for m in manifests], [14, 14, 14, 13])
        records = sorted(
            (record for manifest in manifests for record in manifest["mutants"]),
            key=lambda record: record["index"],
        )
        self.assertEqual([record["name"] for record in records], self.names)
        self.assertEqual([record["index"] for record in records], list(range(len(self.names))))
        self.assertTrue(all(record["shard"] == record["index"] % 4 for record in records))
        result = self.check_fixtures(manifests)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            result.stdout,
            f"mutant-shards: PASS: {len(self.names)} catalog mutants killed exactly once "
            "across 4 complete shards; every baseline passed\n",
        )
        self.assertEqual(result.stderr, "")

    def test_nested_artifact_directories_are_accepted(self):
        folder = self.write_manifests(nested=True)
        result = self.run_checker("--shards", "4", folder)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"PASS: {len(self.names)} catalog mutants", result.stdout)

    def test_omitting_each_shard_fails_with_missing_names(self):
        for shard in range(4):
            with self.subTest(shard=shard):
                manifests = self.fixtures()
                missing_name = manifests[shard]["mutants"][0]["name"]
                del manifests[shard]
                self.assert_rejected(
                    self.check_fixtures(manifests),
                    f"missing shard {shard} of 4",
                    f"missing mutant {missing_name}",
                    "expected exactly 4 manifests, found 3",
                )

    def test_absent_and_empty_artifact_directories_fail(self):
        empty = self.write_manifests([])
        for folder in (empty, self.root / "absent"):
            with self.subTest(folder=folder.name):
                self.assert_rejected(
                    self.run_checker("--shards", "4", folder),
                    "missing shard 0 of 4",
                    f"missing mutant {self.names[0]}",
                )

    def test_duplicate_name_with_55_records_within_and_across_shards_fails(self):
        for destination in (0, 1):
            with self.subTest(destination=destination):
                manifests = self.fixtures()
                duplicate = copy.deepcopy(manifests[0]["mutants"][0])
                replaced_name = manifests[destination]["mutants"][1]["name"]
                manifests[destination]["mutants"][1] = duplicate
                self.assertEqual(sum(len(m["mutants"]) for m in manifests), len(self.names))
                self.assert_rejected(
                    self.check_fixtures(manifests),
                    f"duplicate mutant {duplicate['name']}: ran 2 times",
                    f"missing mutant {replaced_name}",
                )

    def test_duplicate_shard_id_and_same_manifest_twice_fail(self):
        manifests = self.fixtures()
        manifests[1]["shard"] = 0
        self.assert_rejected(self.check_fixtures(manifests), "duplicate shard 0", "missing shard 1")
        folder = self.write_manifests()
        paths = [folder / f"shard-{i}.json" for i in range(4)]
        self.assert_rejected(
            self.run_checker("--shards", "4", *paths, paths[0]),
            "duplicate shard 0: 2 manifests",
            f"duplicate mutant {self.names[0]}",
            "expected exactly 4 manifests, found 5",
        )

    def test_surviving_error_pending_and_missing_outcome_fail(self):
        for outcome in ("survived", "error", "pending", None):
            with self.subTest(outcome=outcome):
                manifests = self.fixtures()
                record = manifests[0]["mutants"][0]
                if outcome is None:
                    del record["outcome"]
                else:
                    record["outcome"] = outcome
                self.assert_rejected(
                    self.check_fixtures(manifests), f"{record['name']} was not killed"
                )

    def test_cancelled_and_missing_completion_fail(self):
        for complete in (False, None, 1, "true"):
            with self.subTest(complete=complete):
                manifests = self.fixtures()
                if complete is None:
                    del manifests[0]["complete"]
                else:
                    manifests[0]["complete"] = complete
                self.assert_rejected(self.check_fixtures(manifests), "shard is incomplete")

    def test_complete_true_with_missing_last_record_fails(self):
        for shard in range(4):
            with self.subTest(shard=shard):
                manifests = self.fixtures()
                removed = manifests[shard]["mutants"].pop()
                self.assert_rejected(
                    self.check_fixtures(manifests), f"missing mutant {removed['name']}"
                )

    def test_failed_error_pending_and_missing_baseline_fail(self):
        for baseline in (
            {"outcome": "failed", "duration_seconds": 0},
            {"outcome": "error", "duration_seconds": 0},
            {"outcome": "pending", "duration_seconds": 0},
            {"duration_seconds": 0},
            None,
        ):
            with self.subTest(baseline=baseline):
                manifests = self.fixtures()
                if baseline is None:
                    del manifests[0]["baseline"]
                else:
                    manifests[0]["baseline"] = baseline
                self.assert_rejected(
                    self.check_fixtures(manifests),
                    "missing baseline result" if baseline is None else "baseline did not pass",
                )

    def test_extra_and_substituted_unknown_names_fail(self):
        for replace in (False, True):
            with self.subTest(replace=replace):
                manifests = self.fixtures()
                unknown = copy.deepcopy(manifests[0]["mutants"][0])
                original = unknown["name"]
                unknown["name"] = "unknown-fixture-mutant"
                if replace:
                    manifests[0]["mutants"][0] = unknown
                else:
                    manifests[0]["mutants"].append(unknown)
                result = self.check_fixtures(manifests)
                self.assert_rejected(result, "extra or unknown mutant name 'unknown-fixture-mutant'")
                if replace:
                    self.assertIn(f"missing mutant {original}", result.stderr)

    def test_fifth_out_of_range_shard_and_conflicting_counts_fail(self):
        manifests = self.fixtures()
        extra = copy.deepcopy(manifests[0])
        extra["shard"] = 4
        manifests.append(extra)
        self.assert_rejected(
            self.check_fixtures(manifests), "invalid shard 4", "expected exactly 4 manifests, found 5"
        )
        for value in (0, 3, 5, "4", True):
            with self.subTest(shards=value):
                manifests = self.fixtures()
                manifests[0]["shards"] = value
                self.assert_rejected(self.check_fixtures(manifests), "shards must equal requested count 4")

    def test_stale_missing_and_wrong_type_catalog_hash_fail(self):
        for digest in ("0" * 64, "", None, True):
            with self.subTest(digest=digest):
                manifests = self.fixtures()
                if digest is None:
                    del manifests[0]["catalog_sha256"]
                else:
                    manifests[0]["catalog_sha256"] = digest
                self.assert_rejected(self.check_fixtures(manifests), "catalog_sha256 does not match")

    def test_incorrect_missing_and_bool_original_indices_fail(self):
        for index in (1, -1, 0.0, "0", False, None):
            with self.subTest(index=index):
                manifests = self.fixtures()
                record = manifests[0]["mutants"][0]
                if index is None:
                    del record["index"]
                else:
                    record["index"] = index
                self.assert_rejected(self.check_fixtures(manifests), "must have original index 0")

    def test_wrong_modulo_or_record_shard_fails(self):
        manifests = self.fixtures()
        moved = manifests[0]["mutants"].pop(0)
        moved["shard"] = 1
        manifests[1]["mutants"].append(moved)
        self.assert_rejected(self.check_fixtures(manifests), f"{moved['name']} must run in shard 0")
        for shard in (1, False, "0", None):
            with self.subTest(shard=shard):
                manifests = self.fixtures()
                record = manifests[0]["mutants"][0]
                if shard is None:
                    del record["shard"]
                else:
                    record["shard"] = shard
                self.assert_rejected(self.check_fixtures(manifests), "must run in shard 0")

    def test_invalid_manifest_shard_types_and_ranges_fail(self):
        for shard in (-1, 4, False, "0", 0.0, None):
            with self.subTest(shard=shard):
                manifests = self.fixtures()
                if shard is None:
                    del manifests[0]["shard"]
                else:
                    manifests[0]["shard"] = shard
                self.assert_rejected(self.check_fixtures(manifests), "invalid shard", "missing shard 0")

    def test_invalid_missing_and_bool_schema_version_fail(self):
        for version in (0, 2, "1", True, 1.0, None):
            with self.subTest(version=version):
                manifests = self.fixtures()
                if version is None:
                    del manifests[0]["schema_version"]
                else:
                    manifests[0]["schema_version"] = version
                self.assert_rejected(self.check_fixtures(manifests), "unsupported or missing schema_version")

    def test_missing_negative_string_bool_and_nonfinite_durations_fail(self):
        invalid = (None, -1, -0.01, "0.01", True, float("nan"), float("inf"), -float("inf"))
        for location in ("shard", "baseline", "mutant"):
            for duration in invalid:
                with self.subTest(location=location, duration=duration):
                    manifests = self.fixtures()
                    container = manifests[0]
                    if location == "baseline":
                        container = container["baseline"]
                    elif location == "mutant":
                        container = container["mutants"][0]
                    if duration is None:
                        del container["duration_seconds"]
                    else:
                        container["duration_seconds"] = duration
                    diagnostic = (
                        "non-finite JSON number"
                        if isinstance(duration, float) and (duration != duration or abs(duration) == float("inf"))
                        else "duration_seconds"
                    )
                    self.assert_rejected(self.check_fixtures(manifests), diagnostic)

    def test_zero_integer_durations_are_valid(self):
        manifests = self.fixtures()
        for manifest in manifests:
            manifest["duration_seconds"] = 0
            manifest["baseline"]["duration_seconds"] = 0
            for record in manifest["mutants"]:
                record["duration_seconds"] = 0
        result = self.check_fixtures(manifests)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_duplicate_json_keys_in_manifest_and_nested_objects_fail(self):
        for needle, replacement in (
            ('"complete": true', '"complete": false, "complete": true'),
            ('"baseline": {', '"baseline": {"outcome": "passed", '),
            ('"mutants": [{', '"mutants": [{"index": 0, '),
        ):
            with self.subTest(needle=needle):
                folder = self.write_manifests()
                target = folder / "shard-0.json"
                text = target.read_text(encoding="utf-8")
                self.assertIn(needle, text)
                target.write_text(text.replace(needle, replacement, 1), encoding="utf-8")
                self.assert_rejected(self.run_checker("--shards", "4", folder), "duplicate JSON key")

    def test_truncated_malformed_and_non_object_manifests_fail(self):
        for raw, diagnostic in (
            ('{"shard": 0,', "cannot read manifest"),
            ("not-json", "cannot read manifest"),
            ("[]", "manifest must be a JSON object"),
            ("null", "manifest must be a JSON object"),
            ("true", "manifest must be a JSON object"),
        ):
            with self.subTest(raw=raw):
                folder = self.write_manifests()
                (folder / "shard-0.json").write_text(raw, encoding="utf-8")
                self.assert_rejected(self.run_checker("--shards", "4", folder), diagnostic)

    def test_non_object_records_non_list_mutants_and_non_object_baselines_fail(self):
        for value in (None, [], True, "killed", 0):
            with self.subTest(record=value):
                manifests = self.fixtures()
                manifests[0]["mutants"][0] = value
                self.assert_rejected(self.check_fixtures(manifests), "mutant must be an object")
            with self.subTest(baseline=value):
                manifests = self.fixtures()
                manifests[0]["baseline"] = value
                self.assert_rejected(self.check_fixtures(manifests), "missing baseline result")
        for value in (None, {}, True, "killed", 0):
            with self.subTest(mutants=value):
                manifests = self.fixtures()
                manifests[0]["mutants"] = value
                self.assert_rejected(self.check_fixtures(manifests), "mutants must be a list")

    def test_missing_mutants_list_fails(self):
        manifests = self.fixtures()
        del manifests[0]["mutants"]
        self.assert_rejected(self.check_fixtures(manifests), "mutants must be a list")

    def test_unknown_or_non_string_record_names_fail(self):
        for name in (None, 0, True, [], {}):
            with self.subTest(name=name):
                manifests = self.fixtures()
                record = manifests[0]["mutants"][0]
                if name is None:
                    del record["name"]
                else:
                    record["name"] = name
                self.assert_rejected(self.check_fixtures(manifests), "extra or unknown mutant name")

    def test_cli_requires_positive_shards_and_manifests(self):
        for arguments, diagnostic in (
            ([], "the following arguments are required"),
            (["--shards", "0", "."], "must be a positive integer"),
            (["--shards", "-1", "."], "must be a positive integer"),
            (["--shards", "four", "."], "invalid positive_int value"),
            (["--shards", "1.5", "."], "invalid positive_int value"),
            (["--shards"], "expected one argument"),
            (["--shards", "4"], "the following arguments are required: manifests"),
            (["--shards", "4", "--unknown", "."], "unrecognized arguments"),
        ):
            with self.subTest(arguments=arguments):
                self.assert_rejected(self.run_checker(*arguments), diagnostic)

    def test_explicit_real_catalog_and_missing_catalog(self):
        folder = self.write_manifests()
        result = self.run_checker("--shards", "4", "--catalog", CATALOG, folder)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_rejected(
            self.run_checker("--shards", "4", "--catalog", self.root / "absent-catalog", folder),
            "mutant-shards: ERROR:",
            "No such file or directory",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
