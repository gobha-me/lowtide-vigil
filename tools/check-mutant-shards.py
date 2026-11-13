#!/usr/bin/env python3
"""Require complete, passing evidence for every shard of the planted catalog.

Usage: python3 tools/check-mutant-shards.py --shards 4 manifests/
The runner writes schema-version-1 JSON manifests. Shards and catalog indices
are zero based; a catalog entry belongs to ``index % shards``. Read the catalog
as data, never by sourcing or executing the mutation runner.
"""

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import shlex
import sys


def read_catalog(path):
    """Return ordered names and a digest of the complete literal catalog."""
    source = path.read_text(encoding="utf-8")
    blocks = re.findall(r"^mutants=\(\s*\n(.*?)^\)\s*$", source, re.M | re.S)
    if len(blocks) != 1:
        raise ValueError("catalog must contain exactly one literal mutants array")
    entries = shlex.split(blocks[0], comments=True, posix=True)
    if not entries:
        raise ValueError("catalog is empty")
    names = []
    for entry in entries:
        fields = entry.split("|", 3)
        if len(fields) != 4 or not fields[1] or not fields[2]:
            raise ValueError("catalog entry must have name, file, anchor, replacement")
        name = fields[0]
        if not re.fullmatch(r"[a-z][a-z0-9-]*", name):
            raise ValueError(f"invalid catalog name: {name!r}")
        names.append(name)
    duplicates = sorted(name for name, count in Counter(names).items() if count > 1)
    if duplicates:
        raise ValueError(f"duplicate catalog names: {', '.join(duplicates)}")
    digest = hashlib.sha256(("\n".join(entries) + "\n").encode("utf-8")).hexdigest()
    return names, digest


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key!r}")
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError(f"non-finite JSON number: {value}")


def is_duration(value):
    if type(value) is int:
        return value >= 0
    return type(value) is float and math.isfinite(value) and value >= 0


def manifest_paths(arguments):
    paths = []
    for argument in arguments:
        path = Path(argument)
        if path.is_dir():
            paths.extend(sorted(path.rglob("*.json")))
        else:
            paths.append(path)
    return paths


def check_manifests(paths, shards, names, digest):
    errors = []
    seen_shards = Counter()
    seen_names = Counter()
    expected_indices = {name: index for index, name in enumerate(names)}
    for path in paths:
        label = str(path)
        try:
            with path.open(encoding="utf-8") as handle:
                manifest = json.load(
                    handle, object_pairs_hook=unique_object, parse_constant=reject_constant
                )
        except (OSError, UnicodeError, ValueError) as error:
            errors.append(f"{label}: cannot read manifest: {error}")
            continue
        if not isinstance(manifest, dict):
            errors.append(f"{label}: manifest must be a JSON object")
            continue
        if type(manifest.get("schema_version")) is not int or manifest["schema_version"] != 1:
            errors.append(f"{label}: unsupported or missing schema_version (expected 1)")
        if type(manifest.get("shards")) is not int or manifest["shards"] != shards:
            errors.append(f"{label}: shards must equal requested count {shards}")
        shard = manifest.get("shard")
        if type(shard) is not int or not 0 <= shard < shards:
            errors.append(f"{label}: invalid shard {shard!r}; expected 0..{shards - 1}")
            shard = None
        else:
            seen_shards[shard] += 1
        if manifest.get("catalog_sha256") != digest:
            errors.append(f"{label}: catalog_sha256 does not match the current catalog")
        if manifest.get("complete") is not True:
            errors.append(f"{label}: shard is incomplete, cancelled, or missing complete=true")
        if not is_duration(manifest.get("duration_seconds")):
            errors.append(f"{label}: missing or invalid shard duration_seconds")
        baseline = manifest.get("baseline")
        if not isinstance(baseline, dict):
            errors.append(f"{label}: missing baseline result")
        else:
            if baseline.get("outcome") != "passed":
                errors.append(f"{label}: baseline did not pass ({baseline.get('outcome')!r})")
            if not is_duration(baseline.get("duration_seconds")):
                errors.append(f"{label}: missing or invalid baseline duration_seconds")
        mutants = manifest.get("mutants")
        if not isinstance(mutants, list):
            errors.append(f"{label}: mutants must be a list")
            continue
        for position, mutant in enumerate(mutants):
            location = f"{label}: mutants[{position}]"
            if not isinstance(mutant, dict):
                errors.append(f"{location}: mutant must be an object")
                continue
            name = mutant.get("name")
            if not isinstance(name, str) or name not in expected_indices:
                errors.append(f"{location}: extra or unknown mutant name {name!r}")
                continue
            seen_names[name] += 1
            index = expected_indices[name]
            if type(mutant.get("index")) is not int or mutant["index"] != index:
                errors.append(f"{location}: {name} must have original index {index}")
            if (
                type(mutant.get("shard")) is not int
                or mutant["shard"] != shard
                or shard != index % shards
            ):
                errors.append(f"{location}: {name} must run in shard {index % shards}")
            if mutant.get("outcome") != "killed":
                errors.append(f"{location}: {name} was not killed ({mutant.get('outcome')!r})")
            if not is_duration(mutant.get("duration_seconds")):
                errors.append(f"{location}: {name} has missing or invalid duration_seconds")
    for shard in range(shards):
        count = seen_shards[shard]
        if count == 0:
            errors.append(f"missing shard {shard} of {shards}")
        elif count != 1:
            errors.append(f"duplicate shard {shard}: {count} manifests")
    for name in names:
        count = seen_names[name]
        if count == 0:
            errors.append(f"missing mutant {name}")
        elif count != 1:
            errors.append(f"duplicate mutant {name}: ran {count} times")
    if len(paths) != shards:
        errors.append(f"expected exactly {shards} manifests, found {len(paths)}")
    return errors


def positive_int(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be a positive integer")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--shards", type=positive_int, required=True)
    parser.add_argument(
        "--catalog", type=Path, default=Path(__file__).with_name("planted-mutants.sh")
    )
    parser.add_argument("manifests", nargs="+", help="JSON files or directories searched recursively")
    arguments = parser.parse_args()
    try:
        names, digest = read_catalog(arguments.catalog)
        paths = manifest_paths(arguments.manifests)
        errors = check_manifests(paths, arguments.shards, names, digest)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"mutant-shards: ERROR: {error}", file=sys.stderr)
        return 1
    if errors:
        for error in errors:
            print(f"mutant-shards: ERROR: {error}", file=sys.stderr)
        return 1
    print(
        f"mutant-shards: PASS: {len(names)} catalog mutants killed exactly once "
        f"across {arguments.shards} complete shards; every baseline passed"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
