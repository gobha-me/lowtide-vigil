#!/usr/bin/env bash
# Scan tracked player-facing content. Python is also used by the build tooling.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
exec python3 tools/term_gate.py
