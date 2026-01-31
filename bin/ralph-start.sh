#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"

PROJECT_DIR_ARG=""


usage() {
  cat <<'EOF'
Usage:
  ./ralph-start.sh [--project-dir DIR] [--profile fast|safe|very-safe] [--iters N] [--stall-secs S] [--interval-secs S]

Options:
  --project-dir DIR  Target project directory (default: cwd)

Defaults:
  --profile safe
  --iters 30
  --stall-secs (from profile)
  --interval-secs 10

Profiles:
  fast:      stall=300  (faster recovery, may kill long silent steps)
  safe:      stall=600  (recommended default)
  very-safe: stall=900  (least likely to kill, slower to recover from real hangs)

Behavior:
  - Starts monitor in the background (nohup) writing to .ralph-logs/monitor.nohup.log
  - Runs ralph.sh in the foreground
  - Prints tail commands for a second terminal
EOF
}

PROFILE=${RALPH_PROFILE:-safe}
ITERS=${GLOBAL_MAX_ITERATIONS:-30}
STALL_SECS=${MONITOR_STALL_SECS:-}
INTERVAL_SECS=${MONITOR_INTERVAL_SECS:-10}

profile_to_stall() {
  case "$1" in
    fast) echo 300 ;;
    safe) echo 600 ;;
    very-safe) echo 900 ;;
    *) echo "" ;;
  esac
}

if [[ -z "$STALL_SECS" ]]; then
  STALL_SECS=$(profile_to_stall "$PROFILE")
fi

if [[ -z "$STALL_SECS" ]]; then
  echo "[ralph-start] ERROR: unknown profile '$PROFILE'" >&2
  usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift ;;
    --profile) PROFILE="$2"; shift ;;
    --iters) ITERS="$2"; shift ;;
    --stall-secs) STALL_SECS="$2"; shift ;;
    --interval-secs) INTERVAL_SECS="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

# If profile is set explicitly, re-derive stall unless --stall-secs was also provided.
if [[ -n "${PROFILE:-}" ]]; then
  if [[ -z "${MONITOR_STALL_SECS:-}" ]]; then
    # If user passed --stall-secs, it already overwrote STALL_SECS.
    prof_stall=$(profile_to_stall "$PROFILE")
    if [[ -n "$prof_stall" ]]; then
      STALL_SECS="$prof_stall"
    fi
  fi
fi

echo "[ralph-start] project=$PROJECT_DIR"
echo "[ralph-start] project=$PROJECT_DIR profile=$PROFILE iters=$ITERS stall=$STALL_SECS interval=$INTERVAL_SECS"
cd "$PROJECT_DIR"

mkdir -p .ralph-logs

# Per-project comm dir to avoid cross-run monitor confusion
export AGENT_COMM_DIR="${AGENT_COMM_DIR:-/tmp/ralph-parallel-$(echo "$PROJECT_DIR" | sha256sum | awk '{print $1}' | cut -c1-10)}"

# Start monitor in background (observe-only); ralph.sh may start monitor-kill separately.
nohup env SHOW_STALE_STORIES=false SHOW_INACTIVE=false \
  INTERVAL_SECS="$INTERVAL_SECS" STALL_SECS="$STALL_SECS" \
  bash /aml/raffaello/raffaello/monitor.sh "$PROJECT_DIR" \
  > .ralph-logs/monitor.nohup.log 2>&1 &

echo "[ralph-start] monitor pid=$! (log: .ralph-logs/monitor.nohup.log)"

cat <<EOF

Second terminal (recommended):
  tail -f .ralph-logs/monitor.nohup.log
  tail -f .ralph-logs/STORY-XXX.log

EOF

exec env RALPH_ASSUME_YES=true \
  GLOBAL_MAX_ITERATIONS="$ITERS" \
  AUTO_MONITOR_KILL=true \
  MONITOR_STALL_SECS="$STALL_SECS" \
  MONITOR_INTERVAL_SECS="$INTERVAL_SECS" \
  "$SCRIPT_DIR/../ralph.sh"
