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

# Create repo with a MEDIUM conflict. We'll lower the medium threshold for determinism.
mkdir -p "$tmp/repo"
git -C "$tmp/repo" init -q

{
  echo "line1"
  for i in $(seq 1 10); do
    echo "BASE-$i"
    echo "filler-$i"
  done
  for i in $(seq 21 160); do
    echo "line$i"
  done
} >"$tmp/repo/conflict.txt"

git -C "$tmp/repo" add -A
git -C "$tmp/repo" -c user.email=test@example.com -c user.name=test commit -qm base

git -C "$tmp/repo" checkout -qb story-US001
for i in $(seq 1 10); do
  sed -i "s/BASE-$i/STORY-$i/" "$tmp/repo/conflict.txt"
done
git -C "$tmp/repo" add -A
git -C "$tmp/repo" -c user.email=test@example.com -c user.name=test commit -qm story

git -C "$tmp/repo" checkout -q master 2>/dev/null || git -C "$tmp/repo" checkout -q main
for i in $(seq 1 10); do
  sed -i "s/BASE-$i/MAIN-$i/" "$tmp/repo/conflict.txt"
done
git -C "$tmp/repo" add -A
git -C "$tmp/repo" -c user.email=test@example.com -c user.name=test commit -qm main

main_branch=$(git -C "$tmp/repo" rev-parse --abbrev-ref HEAD)

# Copy merge tooling.
mkdir -p "$tmp/repo/lib"
cp "$ROOT_DIR/merge-stories.sh" "$tmp/repo/merge-stories.sh"
cp "$ROOT_DIR/lib/detect-cli.sh" "$tmp/repo/lib/detect-cli.sh"
cp "$ROOT_DIR/lib/conflict-analyzer.sh" "$tmp/repo/lib/conflict-analyzer.sh"
cp "$ROOT_DIR/lib/logging.sh" "$tmp/repo/lib/logging.sh"

# Agent stub resolves conflict by picking main version and marking success.
cat >"$tmp/repo/lib/agent-api.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

AGENT_COMM_DIR="${AGENT_COMM_DIR:-/tmp/ralph-parallel}"

spawn_agent() {
  local agent_name=$1
  local story_id=${3:-default}
  mkdir -p "$AGENT_COMM_DIR/$story_id"

  # Simulate agent doing work: resolve conflict and stage.
  if [[ -f conflict.txt ]]; then
    # Keep ours (main branch) for test determinism.
    git checkout --ours conflict.txt >/dev/null 2>&1 || true
    git add conflict.txt >/dev/null 2>&1 || true
  fi

  touch "$AGENT_COMM_DIR/$story_id/.${agent_name}-success"
  echo "cc-pid-99999"
}

wait_for_agent() { return 0; }
check_agent_success() {
  local story_id=$1
  local agent_name=$2
  [[ -f "$AGENT_COMM_DIR/$story_id/.${agent_name}-success" ]]
}
close_agent() { :; }
EOF
chmod +x "$tmp/repo/lib/agent-api.sh"

pushd "$tmp/repo" >/dev/null
set +e
CONFLICT_RATIO_MEDIUM_THRESHOLD=0 MULTIPLE_CONFLICTS_THRESHOLD=0 MAIN_BRANCH="$main_branch" bash ./merge-stories.sh >"$tmp/merge.log" 2>&1
merge_exit=$?
set -e

if [[ $merge_exit -ne 0 ]]; then
  echo "merge-stories.sh failed (exit=$merge_exit)"
  cat "$tmp/merge.log"
  exit 1
fi

# Ensure branch is deleted and merge commit exists.
if git branch | rg -q "\bstory-US001\b"; then
  echo "Expected story branch deleted"
  exit 1
fi

if ! git log --oneline -n 10 | rg -q "Merge story-US001"; then
  echo "Expected merge commit"
  git log --oneline -n 10
  exit 1
fi

popd >/dev/null
echo "PASS"
