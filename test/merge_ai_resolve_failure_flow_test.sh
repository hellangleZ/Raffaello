#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
export PATH="$tmp/bin:$PATH"

# Stub `claude` so detect-cli works.
cat >"$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp/bin/claude"

# Create repo with a deterministic conflict.
mkdir -p "$tmp/repo"
git -C "$tmp/repo" init -q

{
  echo "line1"
  echo "BASE"
  for i in $(seq 3 80); do
    echo "line$i"
  done
} >"$tmp/repo/conflict.txt"

git -C "$tmp/repo" add -A
git -C "$tmp/repo" -c user.email=test@example.com -c user.name=test commit -qm base

git -C "$tmp/repo" checkout -qb story-US001
sed -i 's/BASE/STORY/' "$tmp/repo/conflict.txt"
git -C "$tmp/repo" add -A
git -C "$tmp/repo" -c user.email=test@example.com -c user.name=test commit -qm story

git -C "$tmp/repo" checkout -q master 2>/dev/null || git -C "$tmp/repo" checkout -q main
sed -i 's/BASE/MAIN/' "$tmp/repo/conflict.txt"
git -C "$tmp/repo" add -A
git -C "$tmp/repo" -c user.email=test@example.com -c user.name=test commit -qm main

main_branch=$(git -C "$tmp/repo" rev-parse --abbrev-ref HEAD)

# Copy merge tooling.
mkdir -p "$tmp/repo/lib"
cp "$ROOT_DIR/merge-stories.sh" "$tmp/repo/merge-stories.sh"
cp "$ROOT_DIR/lib/detect-cli.sh" "$tmp/repo/lib/detect-cli.sh"
cp "$ROOT_DIR/lib/conflict-analyzer.sh" "$tmp/repo/lib/conflict-analyzer.sh"
cp "$ROOT_DIR/lib/logging.sh" "$tmp/repo/lib/logging.sh"

# Agent stub simulates failure: returns no success marker.
cat >"$tmp/repo/lib/agent-api.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

AGENT_COMM_DIR="${AGENT_COMM_DIR:-/tmp/ralph-parallel}"

spawn_agent() {
  local agent_name=$1
  local story_id=${3:-default}
  mkdir -p "$AGENT_COMM_DIR/$story_id"
  echo "cc-pid-99999"
}

wait_for_agent() { return 1; }
check_agent_success() { return 1; }
close_agent() { :; }
EOF
chmod +x "$tmp/repo/lib/agent-api.sh"

pushd "$tmp/repo" >/dev/null

set +e
CONFLICT_RATIO_MEDIUM_THRESHOLD=0 MULTIPLE_CONFLICTS_THRESHOLD=0 MAIN_BRANCH="$main_branch" bash ./merge-stories.sh >"$tmp/merge.log" 2>&1
merge_exit=$?
set -e

if [[ $merge_exit -eq 0 ]]; then
  echo "Expected merge-stories.sh to fail"
  cat "$tmp/merge.log"
  exit 1
fi

# Merge should be aborted cleanly.
if [[ -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]]; then
  echo "Expected merge to be aborted (MERGE_HEAD still present)"
  git status
  exit 1
fi

# Story branch should still exist.
if ! git branch | rg -q "\bstory-US001\b"; then
  echo "Expected story branch to remain"
  git branch
  exit 1
fi

# Escalation report should be mentioned somewhere in output.
if ! rg -q "conflict-escalation\.md" "$tmp/merge.log"; then
  echo "Expected escalation report path to be printed"
  cat "$tmp/merge.log"
  exit 1
fi

# Escalation report should include conflicted files.
report_path="${AGENT_COMM_DIR:-/tmp/ralph-parallel}/merge/conflict-escalation.md"
if [[ ! -f "$report_path" ]]; then
  echo "Expected escalation report to exist"
  exit 1
fi
if ! rg -q "Conflicted Files" "$report_path"; then
  echo "Expected conflicted files section in escalation report"
  cat "$report_path"
  exit 1
fi

popd >/dev/null
echo "PASS"
