#!/usr/bin/env python3
"""Validate the wrapper's actual bound, then accelerate only the fixture's clock."""

import os
import sys
from pathlib import Path

assert sys.argv[1:4] == ["--signal=TERM", "--kill-after=5s", "60s"], sys.argv
root = Path(__file__).resolve().parents[1]
with (root / "timeout-calls").open("a") as calls:
    calls.write(" ".join(sys.argv[1:4]) + "\n")
os.execv(
    "/usr/bin/timeout",
    ["timeout", "--signal=TERM", "--kill-after=0.1s", "0.5s", *sys.argv[4:]],
)
