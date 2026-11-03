#!/usr/bin/env python3
"""Export wrapper protocol boundary only; this fixture never proves game acceptance."""

import json
import os
import sys
import time
from pathlib import Path

root = Path(__file__).resolve().parents[2]
settings = json.loads((root / "build/linux/lowtide-vigil.pck").read_text())
menus = "--smoke" in sys.argv
phase = "menus" if menus else "boot"
expected = ["--headless", "--fixed-fps", "60", "--quit-after"]
expected += ["600", "--", "--smoke"] if menus else ["60"]
assert sys.argv[1:] == expected, sys.argv
for name in ("XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME"):
    assert Path(os.environ[name]).parent.parent == root / "runs"
with (root / "calls").open("a") as calls:
    calls.write(phase + "\n")
print("PROTOCOL FIXTURE: " + phase, flush=True)
print(
    settings.get(phase + "_output", "EXPORT SMOKE: passed" if menus else ""), flush=True
)
if settings.get(phase + "_hang", False):
    time.sleep(10)
sys.exit(settings.get(phase + "_status", 0))
