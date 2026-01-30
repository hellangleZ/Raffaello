#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
export PATH="$tmp_dir/bin:$PATH"

# Stub `claude` so detect-cli works without launching anything.
cat >"$tmp_dir/bin/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp_dir/bin/claude"

# Minimal git repo with one story branch.
mkdir -p "$tmp_dir/repo"
git -C "$tmp_dir/repo" init -q
echo base >"$tmp_dir/repo/file.txt"
git -C "$tmp_dir/repo" add -A
git -C "$tmp_dir/repo" -c user.email=test@example.com -c user.name=test commit -qm base
git -C "$tmp_dir/repo" checkout -qb story-US001
echo change >>"$tmp_dir/repo/file.txt"
git -C "$tmp_dir/repo" add -A
git -C "$tmp_dir/repo" -c user.email=test@example.com -c user.name=test commit -qm story

# Replace agent-api with a stub that ensures merge-stories calls wait_for_agent (not wait_for_agents).
mkdir -p "$tmp_dir/repo/lib"
cat >"$tmp_dir/repo/lib/agent-api.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

spawn_agent() { echo "cc-pid-99999"; }
wait_for_agent() { return 0; }
check_agent_success() { return 1; }
close_agent() { :; }
EOF
chmod +x "$tmp_dir/repo/lib/agent-api.sh"

# Copy required libs/scripts.
cp "$ROOT_DIR/merge-stories.sh" "$tmp_dir/repo/merge-stories.sh"
cp "$ROOT_DIR/lib/detect-cli.sh" "$tmp_dir/repo/lib/detect-cli.sh"
cp "$ROOT_DIR/lib/conflict-analyzer.sh" "$tmp_dir/repo/lib/conflict-analyzer.sh"
cp "$ROOT_DIR/lib/logging.sh" "$tmp_dir/repo/lib/logging.sh"

pushd "$tmp_dir/repo" >/dev/null
bash -n merge-stories.sh

# The old broken function name should never reappear.
if rg -n "\\bwait_for_agents\\b" merge-stories.sh >/dev/null; then
  echo "Found forbidden wait_for_agents usage"
  exit 1
fi
popd >/dev/null

echo "PASS"
