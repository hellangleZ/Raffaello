#!/usr/bin/env bash
# Raffaello monitor - periodically reports progress and detects stalled agents.

set -euo pipefail

TARGET_DIR=${1:-"$(pwd)"}
STDOUT=${STDOUT:-false}

for arg in "${@:2}"; do
  case "$arg" in
    --stdout)
      STDOUT=true
      ;;
  esac
done

INTERVAL_SECS=${INTERVAL_SECS:-10}
STALL_SECS=${STALL_SECS:-300}
INACTIVE_SECS=${INACTIVE_SECS:-600}
SHOW_INACTIVE=${SHOW_INACTIVE:-true}

# Safety: default is observe-only. Set KILL_STALLED=true to enable killing.
KILL_STALLED=${KILL_STALLED:-false}

LOG_DIR="$TARGET_DIR/.raffaello-logs"
mkdir -p "$LOG_DIR"
OUT_LOG="${OUT_LOG:-$LOG_DIR/monitor.log}"

COMM_DIR="${AGENT_COMM_DIR:-/tmp/raffaello}"

now() { date -Is; }

log() {
  if [[ "$STDOUT" == "true" ]]; then
    echo "[$(now)] $*" | tee -a "$OUT_LOG"
  else
    echo "[$(now)] $*" | tee -a "$OUT_LOG" >/dev/null
  fi
}

is_alive() {
  local pid=$1
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

read_pid() {
  local pid_file=$1
  if [[ -f "$pid_file" ]]; then
    tr -d ' \n\r\t' <"$pid_file" 2>/dev/null || true
  else
    echo ""
  fi
}

primary_log() {
  ls -t "$LOG_DIR"/*.log 2>/dev/null | head -n 1 || true
}

list_stories() {
  if [[ -d "$COMM_DIR" ]]; then
    find "$COMM_DIR" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort | grep -E '^STORY-[0-9]+'
  fi
}

story_dir_mtime() {
  local story_id=$1
  local story_dir="$COMM_DIR/$story_id"
  stat -c %Y "$story_dir" 2>/dev/null || echo ""
}

state_story_mtime() {
  local story_id=$1
  cat "$COMM_DIR/.monitor-state/${story_id}.__dir_mtime" 2>/dev/null || echo ""
}

latest_story_activity_epoch() {
  local story_id=$1
  local story_dir="$COMM_DIR/$story_id"

  # If this story is being used by a running orchestrator, refreshes will update files.
  # Use newest mtime among known files as a cheap activity signal.
  local latest=0
  local f
  for f in "$story_dir"/*.pid "$story_dir"/*-output.txt "$story_dir"/.planner-success "$story_dir"/.coder-success "$story_dir"/.reviewer-success "$story_dir"/.tester-success; do
    [[ -e "$f" ]] || continue
    local mt
    mt=$(stat -c %Y "$f" 2>/dev/null || echo "0")
    if [[ "$mt" =~ ^[0-9]+$ ]] && (( mt > latest )); then
      latest=$mt
    fi
  done
  echo "$latest"
}

is_active_story() {
  local story_id=$1
  # Consider "active" if any phase pid is alive.
  if ! no_phase_pid_alive "$story_id"; then
    return 0
  fi

  # Or if there was recent file activity.
  local activity
  activity=$(latest_story_activity_epoch "$story_id")
  if [[ "$activity" =~ ^[0-9]+$ ]] && (( activity > 0 )); then
    local age=$(( $(date +%s) - activity ))
    # 120s grace by default to avoid flagging just-started stories as inactive.
    local grace=${ACTIVE_GRACE_SECS:-120}
    if (( age <= grace )); then
      return 0
    fi
  fi

  return 1
}

all_phases_done() {
  local story_id=$1
  local phase
  for phase in planner coder reviewer tester; do
    if [[ ! -f "$COMM_DIR/$story_id/.${phase}-success" ]]; then
      return 1
    fi
  done
  return 0
}

no_phase_pid_alive() {
  local story_id=$1
  local phase
  for phase in planner coder reviewer tester; do
    local pid_file="$COMM_DIR/$story_id/${phase}.pid"
    local pid
    pid=$(read_pid "$pid_file")
    if [[ -n "$pid" ]] && is_alive "$pid"; then
      return 1
    fi
  done
  return 0
}

ensure_state_dir() {
  mkdir -p "$COMM_DIR/.monitor-state" 2>/dev/null || true
}

reset_story_state_if_needed() {
  local story_id=$1
  local story_dir="$COMM_DIR/$story_id"

  # If the story directory was recreated (e.g. new run), clear any old per-phase state.
  # We key off the directory mtime as a simple run boundary.
  local marker="$COMM_DIR/.monitor-state/${story_id}.__dir_mtime"
  local current
  current=$(stat -c %Y "$story_dir" 2>/dev/null || echo "")
  local previous
  previous=$(cat "$marker" 2>/dev/null || echo "")
  if [[ -n "$current" && "$current" != "$previous" ]]; then
    rm -f "$COMM_DIR/.monitor-state/${story_id}."*.lastsize 2>/dev/null || true
    rm -f "$COMM_DIR/.monitor-state/${story_id}."*.lastchange 2>/dev/null || true
    echo "$current" >"$marker" 2>/dev/null || true
  fi
}

state_file_for() {
  local story_id=$1
  local phase=$2
  echo "$COMM_DIR/.monitor-state/${story_id}.${phase}.lastsize"
}

tick_story_phase() {
  local story_id=$1
  local phase=$2
  local phase_pid_file="$COMM_DIR/$story_id/${phase}.pid"
  local phase_success_file="$COMM_DIR/$story_id/.${phase}-success"
  local phase_abort_file="$COMM_DIR/$story_id/.${phase}-abort"
  local phase_output_file="$COMM_DIR/$story_id/${phase}-output.txt"

  local pid
  pid=$(read_pid "$phase_pid_file")

  local alive="no"
  if [[ -n "$pid" ]] && is_alive "$pid"; then
    alive="yes"
  fi

  local success="no"
  [[ -f "$phase_success_file" ]] && success="yes"

  local size=0
  if [[ -f "$phase_output_file" ]]; then
    size=$(wc -c <"$phase_output_file" | tr -d ' ')
  fi

  # Treat a phase as having produced activity if either:
  # - the phase output grows, OR
  # - the orchestrator has already marked it successful.
  # This avoids "bytes=0" looking like a hang when a phase intentionally prints
  # very little but finishes successfully.
  local activity_key="$size"
  if [[ -f "$phase_success_file" ]]; then
    activity_key="success"
  fi

  local st_file
  st_file=$(state_file_for "$story_id" "$phase")
  local prev=""
  prev=$(cat "$st_file" 2>/dev/null || true)

  local last_ts_file="$COMM_DIR/.monitor-state/${story_id}.${phase}.lastchange"
  local last_change_epoch
  last_change_epoch=$(cat "$last_ts_file" 2>/dev/null || echo "")
  if [[ -z "$last_change_epoch" ]]; then
    last_change_epoch=$(date +%s)
    echo "$last_change_epoch" >"$last_ts_file" 2>/dev/null || true
  fi

  if [[ "$prev" != "$activity_key" ]]; then
    echo "$activity_key" >"$st_file" 2>/dev/null || true
    echo "$(date +%s)" >"$last_ts_file" 2>/dev/null || true
    last_change_epoch=$(cat "$last_ts_file" 2>/dev/null || echo "$last_change_epoch")
  fi

  local stalled="no"
  local stalled_for=0
  stalled_for=$(( $(date +%s) - last_change_epoch ))
  if [[ "$success" == "no" && "$alive" == "yes" && $stalled_for -ge $STALL_SECS ]]; then
    stalled="yes"
  fi

  local inactive="no"
  if [[ "$alive" == "no" && "$success" == "no" && $stalled_for -ge $INACTIVE_SECS ]]; then
    inactive="yes"
  fi

  if [[ "$inactive" == "yes" ]]; then
    if [[ "$SHOW_INACTIVE" == "true" ]]; then
      log "story=$story_id phase=$phase pid=${pid:-none} alive=$alive success=$success bytes=$size stalled=$stalled inactive=yes inactive_for=${stalled_for}s"
    fi
  else
    log "story=$story_id phase=$phase pid=${pid:-none} alive=$alive success=$success bytes=$size stalled=$stalled stalled_for=${stalled_for}s"
  fi

  if [[ "$KILL_STALLED" == "true" && "$stalled" == "yes" && -n "$pid" ]]; then
    # Signal orchestrator to stop waiting asap.
    echo "aborted $(now)" >"$phase_abort_file" 2>/dev/null || true
    log "ACTION kill_stalled story=$story_id phase=$phase pid=$pid"
    kill -TERM "$pid" 2>/dev/null || true
    sleep 1
    kill -KILL "$pid" 2>/dev/null || true
  fi
}

main_loop() {
  ensure_state_dir
  log "monitor start target=$TARGET_DIR interval=${INTERVAL_SECS}s stall=${STALL_SECS}s kill=${KILL_STALLED} comm_dir=$COMM_DIR out=$OUT_LOG"

  while true; do
    local p
    p=$(primary_log)
    if [[ -n "$p" ]]; then
      log "latest_log=$p"
      tail -n 3 "$p" 2>/dev/null | sed 's/^/  /' | tee -a "$OUT_LOG" >/dev/null || true
    fi

    local story
    while IFS= read -r story; do
      [[ -z "$story" ]] && continue

      reset_story_state_if_needed "$story"

      # If a story is clearly stale (leftover from a previous run), hide it by default.
      # This avoids confusing "inactive_for=1400s" lines right after starting a new run.
      if ! is_active_story "$story" && [[ "${SHOW_STALE_STORIES:-false}" != "true" ]]; then
        continue
      fi

      # Reduce noise: once a story is fully done and no PIDs are alive, stop printing it.
      # (Directories may remain; this keeps the terminal/log readable.)
      if all_phases_done "$story" && no_phase_pid_alive "$story"; then
        continue
      fi

      for phase in planner coder reviewer tester; do
        if [[ -d "$COMM_DIR/$story" ]]; then
          tick_story_phase "$story" "$phase"
        fi
      done

      # If the story looks inactive (no PIDs alive and no phase progress) for long enough,
      # print a single reminder line (once per minute) suggesting a rerun/cleanup.
      if no_phase_pid_alive "$story" && ! all_phases_done "$story"; then
        local hint_file="$COMM_DIR/.monitor-state/${story}.inactive.hint"
        local last_hint
        last_hint=$(cat "$hint_file" 2>/dev/null || echo "")
        local now_epoch
        now_epoch=$(date +%s)
        if [[ -z "$last_hint" || $(( now_epoch - last_hint )) -ge 60 ]]; then
          echo "$now_epoch" >"$hint_file" 2>/dev/null || true
          log "INACTIVE story=$story hint=No alive pids detected; check story log or rerun. (set SHOW_INACTIVE=false to hide phase lines)"
        fi
      fi
    done < <(list_stories)

    sleep "$INTERVAL_SECS"
  done
}

main_loop
