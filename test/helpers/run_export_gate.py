"""Run the unmodified export wrapper with a bounded process group and isolated cwd."""

import os
from pathlib import Path
import signal
import subprocess
import sys


def main():
    sandbox = Path(sys.argv[1])
    command = ["bash", str(sandbox / "source/tools/check-export.sh"), *sys.argv[2:]]
    env = dict(os.environ, TMPDIR=str(sandbox / "wrapper temp"))
    with subprocess.Popen(
        command,
        cwd=sandbox / "caller",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    ) as process:
        try:
            output, _ = process.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
            sys.stdout.buffer.write(output)
            print("export gate test: subprocess exceeded 15 seconds", flush=True)
            return 124
    sys.stdout.buffer.write(output)
    return process.returncode


if __name__ == "__main__":
    sys.exit(main())
