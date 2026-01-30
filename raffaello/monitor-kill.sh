#!/usr/bin/env bash
# Convenience wrapper: enable kill mode for monitor.sh

set -euo pipefail

TARGET_DIR=${1:-"$(pwd)"}

export KILL_STALLED=true
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/monitor.sh" "$TARGET_DIR" --stdout
