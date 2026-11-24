#!/usr/bin/env python3
"""Desktop wrapper boundary protocol only: never engine or gameplay evidence."""

import json
import os
from pathlib import Path
import signal
import sys


MARKERS = [
    "DESKTOP ACCEPTANCE: F11 press/echo/release 1",
    "DESKTOP ACCEPTANCE: F11 press/echo/release 2",
    "DESKTOP ACCEPTANCE: joypad sticks/release",
    "DESKTOP ACCEPTANCE: passed",
    "DESKTOP ACCEPTANCE: keyboard controls/back",
    "DESKTOP ACCEPTANCE: keyboard pause/resume",
    "DESKTOP ACCEPTANCE: keyboard restart",
    "DESKTOP ACCEPTANCE: keyboard lost fixture/shore",
    "DESKTOP ACCEPTANCE: keyboard won fixture/shore",
    "DESKTOP ACCEPTANCE: joypad controls/back",
    "DESKTOP ACCEPTANCE: joypad pause/resume",
    "DESKTOP ACCEPTANCE: joypad restart",
    "DESKTOP ACCEPTANCE: joypad lost fixture/shore",
    "DESKTOP ACCEPTANCE: joypad won fixture/shore",
]


def main():
    cwd = Path.cwd()
    settings = json.loads((cwd / "lowtide-vigil.pck").read_text())
    startup = sys.argv[1:] == [
        "--headless", "--fixed-fps", "60", "--quit-after", "120"
    ]
    if not startup:
        assert sys.argv[1:] == [
            "--headless", "--fixed-fps", "60", "--quit-after", "3000"
        ], sys.argv
    phase = "startup" if startup else "acceptance"
    assert cwd.parent == Path(settings["sandbox"]) / "runs"
    assert cwd != Path(settings["original"])
    assert Path(sys.argv[0]).resolve() == cwd / "lowtide-vigil.x86_64"
    for name, directory in (
        ("XDG_CACHE_HOME", "cache"),
        ("XDG_DATA_HOME", "data"),
        ("XDG_CONFIG_HOME", "config"),
    ):
        assert Path(os.environ[name]) == cwd / directory
        assert Path(os.environ[name]).is_dir()
        (Path(os.environ[name]) / (phase + ".sentinel")).write_text(phase)
    assert os.environ["GODOT_SILENCE_ROOT_WARNING"] == "1"
    override = cwd / "override.cfg"
    assert override.exists() != startup
    if not startup:
        assert override.read_text() == (
            "[autoload]\nDesktopAcceptance="
            + json.dumps("*" + settings["driver"])
            + "\n"
        )
    with (Path(settings["sandbox"]) / "calls").open("a") as calls:
        calls.write(phase + "\n")
    print("PROTOCOL FIXTURE: " + phase, flush=True)
    default = "" if startup else "\n".join(MARKERS)
    print(settings.get(phase + "_output", default), flush=True)
    if settings.get(phase + "_hang", False):
        # Block on a signal rather than sleeping or performing any game/engine work.
        while True:
            signal.pause()
    return settings.get(phase + "_status", 0)


if __name__ == "__main__":
    sys.exit(main())
