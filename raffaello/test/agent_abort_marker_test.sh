#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/lib/agent-api.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export AGENT_COMM_DIR="$tmp/comm"
mkdir -p "$AGENT_COMM_DIR/STORY-X"

# Fake a pid-based agent id; it doesn't need to exist because abort should short-circuit.
agent_id="cc-pid-999999"
touch "$AGENT_COMM_DIR/STORY-X/.tester-abort"

set +e
wait_for_agent "STORY-X" "tester" "$agent_id"
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  echo "Expected abort marker to fail wait_for_agent" >&2
  exit 1
fi

echo "PASS"
