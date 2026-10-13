#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/test-feature-config.py"
exec python3 "$SCRIPT_DIR/test-recovery-state.py"
