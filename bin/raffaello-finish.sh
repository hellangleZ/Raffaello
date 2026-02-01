#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_DIR="$(pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./raffaello-finish.sh [--merge-pass] [--clean] [--dry-run]

What it does (in order):
  1) Stops raffaello/agents/monitors for this project (kill-all)
  2) Cleans comm/worktrees (optional)
  3) Ensures working tree is clean
  4) Merges passes=true story branches into the current branch (optional)

Options:
  --project-dir DIR  Target project directory (default: cwd)
  --merge-pass   Merge all passes=true stories into current branch
  --clean        Also clean comm dir + git worktrees
  --dry-run      Print actions, do not execute destructive steps

Examples:
  ./raffaello-finish.sh --project-dir /path/to/project --merge-pass
  ./raffaello-finish.sh --project-dir /path/to/project --clean --merge-pass
EOF
}

MERGE_PASS=false
CLEAN=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift ;;
    --merge-pass) MERGE_PASS=true ;;
    --clean) CLEAN=true ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

cd "$PROJECT_DIR"

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "+ $*"
  else
    eval "$@"
  fi
}

kill_orphan_claude() {
  # Only kill `claude` processes that are clearly orphaned from Raffaello:
  # - command is exactly "claude"
  # - PPID == 1
  # - PID is not referenced by any /tmp/raffaello-parallel/STORY-*/<phase>.pid file
  local comm_dir="${AGENT_COMM_DIR:-/tmp/raffaello-parallel}"

  if [[ ! -d "$comm_dir" ]]; then
    return 0
  fi

  # Build a set of PIDs that Raffaello still considers relevant.
  # Those MUST NOT be killed.
  local referenced_pids
  referenced_pids=$(ls "$comm_dir"/STORY-*/{planner,coder,reviewer,tester}.pid 2>/dev/null \
    | xargs -r -n1 sh -c 'tr -d "\\r\\n\\t " < "$1"' sh \
    | rg -n '^[0-9]+$' -o || true)

  local killed=0
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue

    # PPID guard
    local ppid
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' \t\r\n' || true)
    [[ "$ppid" == "1" ]] || continue

    # Not referenced by any pid file
    if [[ -n "$referenced_pids" ]] && echo "$referenced_pids" | rg -q "^$pid$"; then
      continue
    fi

    echo "[raffaello-finish] killing orphan claude pid=$pid"
    if [[ "$DRY_RUN" == "true" ]]; then
      continue
    fi

    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    kill -KILL "$pid" 2>/dev/null || true
    sleep 0.2
    if kill -0 "$pid" 2>/dev/null; then
      echo "[raffaello-finish] WARN: orphan claude still alive pid=$pid" >&2
    fi
    killed=$((killed+1))
  done < <(pgrep -x claude 2>/dev/null || true)

  if [[ $killed -gt 0 ]]; then
    echo "[raffaello-finish] orphan claude killed=$killed"
  fi
}


echo "[raffaello-finish] project=$PROJECT_DIR"

KILL_ALL="$SCRIPT_DIR/../raffaello/kill-all.sh"
if [[ ! -x "$KILL_ALL" ]]; then
  echo "ERROR: missing $KILL_ALL" >&2
  exit 2
fi

kill_args=("--project-dir" "$PROJECT_DIR")
if [[ "$CLEAN" == "true" ]]; then
  kill_args+=("--clean-comm" "--clean-worktrees")
fi

echo "[raffaello-finish] stopping agents/monitors..."
run "bash '$KILL_ALL' ${kill_args[*]}"

# Optional: clean up orphaned Claude processes left behind after success
# (helps avoid stale/resource-leak issues on restarts)
if [[ "$CLEAN" == "true" ]]; then
  kill_orphan_claude
fi



echo "[raffaello-finish] ensuring repo hygiene..."
run "rm -f '$PROJECT_DIR/prd.json.lock' 2>/dev/null || true"
run "git checkout -q master || true"
run "git worktree prune || true"

# Keep logs/worktrees out of git, but don't delete user files.
if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: working tree is not clean. Resolve before finishing." >&2
  git status --porcelain >&2
  exit 3
fi

if [[ "$MERGE_PASS" == "true" ]]; then
  if [[ ! -x "$SCRIPT_DIR/raffaello-merge.sh" ]]; then
    echo "ERROR: missing $SCRIPT_DIR/raffaello-merge.sh" >&2
    exit 4
  fi
  echo "[raffaello-finish] merging passes=true stories..."
  run "'$SCRIPT_DIR/raffaello-merge.sh' --project-dir '$PROJECT_DIR' merge-pass"
fi

echo "[raffaello-finish] done"

