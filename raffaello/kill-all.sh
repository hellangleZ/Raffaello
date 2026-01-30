#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

AGENT_COMM_DIR_DEFAULT="/tmp/ralph-parallel"

usage() {
  cat <<'EOF'
kill-all.sh - stop Ralph + agents and optionally clean temp dirs

Usage:
  kill-all.sh [--project-dir DIR] [--clean-comm] [--clean-worktrees] [--clean-logs] [--clean-all] [--dry-run]

Options:
  --project-dir DIR     Project directory that contains .ralph-logs/.ralph-worktrees (default: cwd)
  --clean-comm          Remove $AGENT_COMM_DIR/STORY-* and monitor state (default: off)
  --clean-worktrees      Remove project .ralph-worktrees (default: off)
  --clean-logs           Remove project .ralph-logs (default: off)
  --clean-all            Equivalent to: --clean-comm --clean-worktrees --clean-logs
  --dry-run              Print what would be killed/removed

Environment:
  AGENT_COMM_DIR         Defaults to /tmp/ralph-parallel

Examples:
  /aml/raffaello/raffaello/kill-all.sh
  /aml/raffaello/raffaello/kill-all.sh --project-dir /aml/test --clean-comm
  /aml/raffaello/raffaello/kill-all.sh --project-dir /aml/test --clean-all
EOF
}

PROJECT_DIR="$(pwd)"
CLEAN_COMM=0
CLEAN_WORKTREES=0
CLEAN_LOGS=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      PROJECT_DIR="$2"; shift 2 ;;
    --clean-comm)
      CLEAN_COMM=1; shift ;;
    --clean-worktrees)
      CLEAN_WORKTREES=1; shift ;;
    --clean-logs)
      CLEAN_LOGS=1; shift ;;
    --clean-all)
      CLEAN_COMM=1; CLEAN_WORKTREES=1; CLEAN_LOGS=1; shift ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

AGENT_COMM_DIR="${AGENT_COMM_DIR:-$AGENT_COMM_DIR_DEFAULT}"

say() { printf '%s\n' "$*"; }
run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    say "[dry-run] $*"
    return 0
  fi
  eval "$@"
}

say "[kill-all] repo=$REPO_DIR"
say "[kill-all] project=$PROJECT_DIR"
say "[kill-all] agent_comm_dir=$AGENT_COMM_DIR"
say "[kill-all] clean_comm=$CLEAN_COMM clean_worktrees=$CLEAN_WORKTREES clean_logs=$CLEAN_LOGS dry_run=$DRY_RUN"

process_pattern='(\./raffaello/ralph\.sh|\.\./raffaello/ralph\.sh|/aml/raffaello/ralph\.sh|raffaello/ralph\.sh|/aml/raffaello/orchestrator\.sh|raffaello/orchestrator\.sh|/aml/raffaello/raffaello/monitor\.sh|raffaello/raffaello/monitor\.sh|/aml/raffaello/raffaello/monitor-kill\.sh|raffaello/raffaello/monitor-kill\.sh|(^|/)(claude|claude-code)( |$)|cc-pid-|cc-sync)'

say "[kill-all] matching processes:"
pgrep -af "$process_pattern" || true

say "[kill-all] sending TERM..."
run "pkill -TERM -f '$process_pattern' || true"

if [[ $DRY_RUN -eq 0 ]]; then
  for _ in {1..20}; do
    if ! pgrep -af "$process_pattern" >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
  done
fi

say "[kill-all] sending KILL to leftovers..."
run "pkill -KILL -f '$process_pattern' || true"

if [[ $CLEAN_COMM -eq 1 ]]; then
  say "[kill-all] cleaning agent comm state..."
  run "rm -rf '$AGENT_COMM_DIR'/STORY-* 2>/dev/null || true"
  run "rm -rf '$AGENT_COMM_DIR'/.monitor-state 2>/dev/null || true"
  say "[kill-all] done cleaning comm"
fi

if [[ $CLEAN_WORKTREES -eq 1 ]]; then
  say "[kill-all] cleaning project worktrees..."
  # IMPORTANT: removing the directory is not enough. Git keeps bookkeeping for worktrees
  # (e.g. .git/worktrees/*). If those become stale, future `git worktree add` will fail with
  # "<branch> is already used by worktree" even if the directory is gone.
  if [[ -d "$PROJECT_DIR/.git" ]]; then
    run "git -C '$PROJECT_DIR' worktree prune >/dev/null 2>&1 || true"

    # Force-remove any tracked worktrees under the ralph worktrees directory.
    # Use --force to handle cases like: "prunable gitdir file points to non-existent location".
    if [[ -d "$PROJECT_DIR/.ralph-worktrees" ]]; then
      while IFS= read -r wt; do
        [[ -z "$wt" ]] && continue
        run "git -C '$PROJECT_DIR' worktree remove --force '$wt' >/dev/null 2>&1 || true"
      done < <(git -C "$PROJECT_DIR" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}' | grep -F "$PROJECT_DIR/.ralph-worktrees/" || true)
    fi

    run "git -C '$PROJECT_DIR' worktree prune >/dev/null 2>&1 || true"
  fi

  run "rm -rf '$PROJECT_DIR/.ralph-worktrees' 2>/dev/null || true"
  say "[kill-all] done cleaning worktrees"
fi

if [[ $CLEAN_LOGS -eq 1 ]]; then
  say "[kill-all] cleaning project logs..."
  run "rm -rf '$PROJECT_DIR/.ralph-logs' 2>/dev/null || true"
  say "[kill-all] done cleaning logs"
fi

say "[kill-all] done"
