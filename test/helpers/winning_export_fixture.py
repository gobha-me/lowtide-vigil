#!/usr/bin/env python3
"""Disposable child-process protocol fixture, never gameplay evidence."""
import json
import os
from pathlib import Path
import sys

cwd = Path.cwd()
config = cwd / "override.cfg"
settings = json.loads((cwd / "lowtide-vigil.pck").read_text())
startup = sys.argv[-1] == "120"
phase = "startup" if startup else "playthrough"
assert sys.argv[1:4] == ["--headless", "--fixed-fps", "60"]
assert "--quit-after" in sys.argv
assert config.exists() != startup
assert cwd != Path(settings["original"])
for name in ("XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME"):
    assert Path(os.environ[name]).parent == cwd
if not startup:
    assert settings["driver"] in config.read_text()
print("PROTOCOL FIXTURE: " + phase, flush=True)
print(settings.get(phase + "_output", ""), flush=True)
if not startup and "playthrough_output" not in settings:
    print("WINNING PLAYTHROUGH: passed", flush=True)
sys.exit(settings.get(phase + "_status", 0))
