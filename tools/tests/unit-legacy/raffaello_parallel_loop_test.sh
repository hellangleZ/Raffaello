#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$tmp_dir/binstub"
export PATH="$tmp_dir/binstub:$PATH"

# Stub required CLIs
cat >"$tmp_dir/binstub/jq" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/jq "$@"
EOF
chmod +x "$tmp_dir/binstub/jq"

cat >"$tmp_dir/binstub/yq" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp_dir/binstub/yq"

cat >"$tmp_dir/binstub/claude-code" <<'EOF'
#!/usr/bin/env bash
# Minimal stub just to satisfy detect_cli + multi-agent check
echo "claude-code stub" >/dev/null
exit 0
EOF
chmod +x "$tmp_dir/binstub/claude-code"

cat >"$tmp_dir/binstub/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

comm_dir="${COMMUNICATION_DIRECTORY:-}"
if [[ -n "$comm_dir" ]]; then
  mkdir -p "$comm_dir"
  # Best-effort: infer agent name from prompt filename written by agent-api.
  agent_name="agent"
  if [[ -f /dev/fd/0 ]]; then
    :
  fi
  # Read stdin but ignore contents.
  cat >/dev/null
  # Touch a generic marker so wait loops can terminate if used.
  touch "$comm_dir/.planner-success" 2>/dev/null || true
fi

exit 0
EOF
chmod +x "$tmp_dir/binstub/claude"

# Minimal git repo with PRD
mkdir -p "$tmp_dir/proj"
cp "$ROOT_DIR/prd.json" "$tmp_dir/proj/prd.json"
cp -R "$ROOT_DIR/workflows" "$tmp_dir/proj/workflows"

cat >"$tmp_dir/proj/prd.json" <<'EOF'
{
  "projectName": "Test Project",
  "branchName": "main",
  "userStories": [
    {"id": "US-001", "title": "Story 1", "description": "d", "passes": false, "dependencies": []},
    {"id": "US-002", "title": "Story 2", "description": "d", "passes": false, "dependencies": []},
    {"id": "US-003", "title": "Story 3", "description": "d", "passes": false, "dependencies": []},
    {"id": "US-004", "title": "Story 4", "description": "d", "passes": false, "dependencies": []}
  ]
}
EOF

cat >"$tmp_dir/proj/.gitignore" <<'EOF'
.raffaello-logs/
.raffaello-worktrees/
EOF

git -C "$tmp_dir/proj" init -q
git -C "$tmp_dir/proj" add -A
git -C "$tmp_dir/proj" -c user.email=test@example.com -c user.name=test commit -qm "init"

# Stub orchestrator: quick + deterministic, and creates success markers.
cat >"$tmp_dir/orchestrator.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
story_id="$1"
echo "[ORCHESTRATOR] story=$story_id"
COMMUNICATION_DIRECTORY="${COMMUNICATION_DIRECTORY:-/tmp/raffaello/$story_id}"
mkdir -p "$COMMUNICATION_DIRECTORY"
touch "$COMMUNICATION_DIRECTORY/.planner-success"
sleep 0.1
exit 0
EOF
chmod +x "$tmp_dir/orchestrator.sh"

# Copy minimal raffaello tree so library sourcing works
cp -R "$ROOT_DIR/lib" "$tmp_dir/lib"
cp "$ROOT_DIR/raffaello.sh" "$tmp_dir/raffaello.sh"

export MAX_PARALLEL_STORIES=2
export LOG_DIR="$tmp_dir/proj/.raffaello-logs"
export AGENT_COMM_DIR="$tmp_dir/comm"
mkdir -p "$AGENT_COMM_DIR"

pushd "$tmp_dir/proj" >/dev/null
set +e
stdbuf -oL -eL bash "$tmp_dir/raffaello.sh" >"$tmp_dir/out.log" 2>&1
raffaello_exit=$?
set -e
popd >/dev/null

# Expect more than one story to start, otherwise loop likely exited early.
started_count=$(rg -c "Starting story: US-" "$tmp_dir/out.log" || true)
if [[ "$started_count" -lt 2 ]]; then
  echo "Expected >= 2 stories to start, got $started_count"
  echo "--- output ---"
  cat "$tmp_dir/out.log"
  exit 1
fi

echo "--- agent comm dir ---"
find "$AGENT_COMM_DIR" -maxdepth 4 -type f | sed -n '1,200p'


# PID persistence is best-effort (depends on agent actually spawning). This test
# only asserts that the main loop starts multiple stories.

echo "PASS"
exit 0
