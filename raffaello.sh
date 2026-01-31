#!/usr/bin/env bash
# Raffaello - Main Execution Loop
# Orchestrates parallel execution of multiple user stories

set -euo pipefail

# Ensure we always capture a primary run log even if the terminal closes.
LOG_DIR_DEFAULT="$(pwd)/.raffaello-logs"
LOG_DIR="${LOG_DIR:-$LOG_DIR_DEFAULT}"
mkdir -p "$LOG_DIR"
MAIN_LOG_FILE_DEFAULT="$LOG_DIR/raffaello-main.log"
MAIN_LOG_FILE="${MAIN_LOG_FILE:-$MAIN_LOG_FILE_DEFAULT}"

# Best-effort: mirror stdout/stderr to a file without relying on a pipeline in the caller.
# NOTE: If we hard-redirect stdout/stderr here, interactive prompts may appear to "hang".
# Keep terminal output by default; allow opt-in to full redirection.
if [[ -z "${RAFFAELLO_MAIN_LOG_STARTED:-}" ]]; then
  export RAFFAELLO_MAIN_LOG_STARTED=1
  if [[ "${RAFFAELLO_REDIRECT_STDOUT:-false}" == "true" ]]; then
    exec >>"$MAIN_LOG_FILE" 2>&1
  else
    # Avoid process substitution here: it creates extra bash processes and can
    # interfere with lock fds, leading to confusing errors like "flock: 200: Bad file descriptor".
    # Users can tee externally if needed:
    #   ../raffaello/raffaello.sh 2>&1 | tee -a .raffaello-logs/raffaello-main.log
    :
  fi
fi

_raffaello_last_command=""
trap '_raffaello_last_command="$BASH_COMMAND"' DEBUG

_raffaello_on_exit() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    printf '[FATAL] raffaello.sh exiting rc=%s last_cmd=%q\n' "$exit_code" "${_raffaello_last_command:-}" >&2
  else
    printf '[INFO] raffaello.sh exiting rc=0\n' >&2
  fi
}
# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

# Source libraries
source "$SCRIPT_DIR/lib/detect-cli.sh"
source "$SCRIPT_DIR/lib/agent-api.sh"
source "$SCRIPT_DIR/lib/prd-validator.sh"

# Source unified logging
export LOG_PREFIX="INFO"
source "$SCRIPT_DIR/lib/logging.sh"

# Configuration defaults (can be overridden by CLI args or env vars)
MAX_PARALLEL_STORIES=${MAX_PARALLEL_STORIES:-3}
LOG_DIR="$LOG_DIR"

# Global rerun budget across all stories in a single raffaello.sh run.
# If any story fails, raffaello will try again in another iteration until budget is exhausted.
GLOBAL_MAX_ITERATIONS=${GLOBAL_MAX_ITERATIONS:-20}

# Optional watchdog to kill stalled agents and unblock orchestration.
# Off by default for safety; enable to automatically enforce stall handling.
AUTO_MONITOR_KILL=${AUTO_MONITOR_KILL:-false}
MONITOR_INTERVAL_SECS=${MONITOR_INTERVAL_SECS:-10}
MONITOR_STALL_SECS=${MONITOR_STALL_SECS:-300}

# Avoid hangs when stdin is non-interactive (e.g. running under nohup or when stdout is redirected
# to MAIN_LOG_FILE). Set to true to auto-confirm safe prompts.
RAFFAELLO_ASSUME_YES=${RAFFAELLO_ASSUME_YES:-false}

# Parse command line arguments
show_help() {
  cat <<EOF
Usage: raffaello.sh [OPTIONS]

Options:
  --max-iterations N    Maximum iterations to retry failed stories (default: 20)
  --max-parallel N      Maximum parallel stories per batch (default: 3)
  --auto-kill           Enable auto-kill for stalled agents
  --stall-secs N        Seconds before agent is considered stalled (default: 300)
  --yes, -y             Auto-confirm prompts (non-interactive mode)
  --help, -h            Show this help message

Environment variables:
  GLOBAL_MAX_ITERATIONS   Same as --max-iterations
  MAX_PARALLEL_STORIES    Same as --max-parallel
  AUTO_MONITOR_KILL       Same as --auto-kill (set to "true")
  MONITOR_STALL_SECS      Same as --stall-secs
  RAFFAELLO_ASSUME_YES        Same as --yes (set to "true")

Examples:
  raffaello.sh --max-iterations 10 --max-parallel 5
  raffaello.sh --auto-kill --stall-secs 180
  raffaello.sh -y
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-iterations)
      GLOBAL_MAX_ITERATIONS="$2"
      shift 2
      ;;
    --max-parallel)
      MAX_PARALLEL_STORIES="$2"
      shift 2
      ;;
    --auto-kill)
      AUTO_MONITOR_KILL=true
      shift
      ;;
    --stall-secs)
      MONITOR_STALL_SECS="$2"
      shift 2
      ;;
    --yes|-y)
      RAFFAELLO_ASSUME_YES=true
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      show_help
      exit 1
      ;;
  esac
done

# Guard against accidental multi-start in the same project directory.
# Use a PID file lock (not flock) to avoid fd portability issues.
LOCK_FILE="${RAFFAELLO_LOCK_FILE:-$LOG_DIR/raffaello.pid}"

acquire_pid_lock() {
  mkdir -p "$LOG_DIR" 2>/dev/null || true

  if [[ -f "$LOCK_FILE" ]]; then
    local existing_pid
    existing_pid=$(tr -d ' \n\r\t' <"$LOCK_FILE" 2>/dev/null || true)
    if [[ "$existing_pid" =~ ^[0-9]+$ ]] && kill -0 "$existing_pid" 2>/dev/null; then
      log_error "Another raffaello.sh is already running for this project (pid=$existing_pid)."
      log_error "If you're sure it's stale, run: bash $SCRIPT_DIR/raffaello/kill-all.sh --project-dir $(pwd)"
      exit 1
    fi
  fi

  echo "$$" >"$LOCK_FILE" 2>/dev/null || true
}

release_pid_lock() {
  # Only remove the lock if we still own it.
  if [[ -f "$LOCK_FILE" ]]; then
    local current
    current=$(tr -d ' \n\r\t' <"$LOCK_FILE" 2>/dev/null || true)
    if [[ "$current" == "$$" ]]; then
      rm -f "$LOCK_FILE" 2>/dev/null || true
    fi
  fi
}

# Try current directory first, then script directory
if [[ -f "prd.json" ]]; then
  PRD_FILE="${PRD_FILE:-$(pwd)/prd.json}"
else
  PRD_FILE="${PRD_FILE:-$SCRIPT_DIR/prd.json}"
fi

if [[ -f "progress.txt" ]]; then
  PROGRESS_FILE="${PROGRESS_FILE:-$(pwd)/progress.txt}"
else
  PROGRESS_FILE="${PROGRESS_FILE:-$SCRIPT_DIR/progress.txt}"
fi

# Temporary directory for PID tracking (Bash 3.2 compatible)
PID_TRACKING_DIR=$(mktemp -d)

# Keep a single EXIT trap handler so multiple sections don't overwrite each other.
_raffaello_cleanup() {
  # Remove temp pid tracker
  rm -rf "$PID_TRACKING_DIR" 2>/dev/null || true

  # Best-effort: stop monitor-kill if we started one
  if [[ -n "${LOG_DIR:-}" && -f "${LOG_DIR:-}/monitor-kill.pid" ]]; then
    local mpid
    mpid=$(cat "${LOG_DIR:-}/monitor-kill.pid" 2>/dev/null || true)
    if [[ -n "$mpid" ]] && kill -0 "$mpid" 2>/dev/null; then
      kill -TERM "$mpid" 2>/dev/null || true
    fi
  fi

  release_pid_lock
  _raffaello_on_exit
}

trap _raffaello_cleanup EXIT

# Cleanup worktrees on interrupt
cleanup_worktrees() {
  # Kill all tracked background processes first
  if [[ -d "$PID_TRACKING_DIR" ]]; then
    for pid_file in "$PID_TRACKING_DIR"/*; do
      if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(basename "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
          log_info "Killing background process $pid"
          kill -TERM "$pid" 2>/dev/null || true
        fi
      fi
    done
    # Wait for graceful shutdown
    sleep 1
    # Force kill any remaining
    for pid_file in "$PID_TRACKING_DIR"/*; do
      if [[ -f "$pid_file" ]]; then
        local pid
        pid=$(basename "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
          kill -KILL "$pid" 2>/dev/null || true
        fi
      fi
    done
  fi

  # Then clean up worktrees
  if [[ -d "$PWD/.raffaello-worktrees" ]]; then
    log_info "Cleaning up worktrees due to interrupt..."
    for worktree_path in "$PWD/.raffaello-worktrees"/*; do
      if [[ -d "$worktree_path" ]]; then
        git worktree remove "$worktree_path" 2>/dev/null || true
      fi
    done
    rmdir "$PWD/.raffaello-worktrees" 2>/dev/null || true
    git worktree prune 2>/dev/null || true
  fi

  # Exit with error code 130 (standard for SIGINT)
  exit 130
}
# Only SIGINT (Ctrl-C) should trigger aggressive cleanup. Treat TERM/HUP as a
# request to stop without tearing down worktrees mid-flight; the monitor-kill
# process may send TERM to stale processes.
trap cleanup_worktrees INT

# Check prerequisites
check_prerequisites() {
  log_info "Checking prerequisites..."

  # Check jq is installed
  if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed"
    echo "Install: brew install jq"
    exit 1
  fi

  # Check yq is installed
  if ! command -v yq &> /dev/null; then
    log_error "yq is required but not installed"
    echo "Install: brew install yq"
    exit 1
  fi

  # Check PRD file exists
  if [[ ! -f "$PRD_FILE" ]]; then
    log_error "PRD file not found: $PRD_FILE"
    exit 1
  fi

  # Validate PRD structure and content
  log_info "Validating PRD file..."
  if ! validate_prd "$PRD_FILE" 2>&1 | while IFS= read -r line; do
    if [[ "$line" =~ ^ERROR: ]]; then
      log_error "${line#ERROR: }"
    elif [[ "$line" =~ ^✓ ]]; then
      log_success "${line#✓ }"
    else
      echo "$line"
    fi
  done; then
    log_error "PRD validation failed"
    exit 1
  fi

  # Check if current directory is a git repository
  if ! git rev-parse --git-dir &>/dev/null; then
    log_warn "Current directory is not a git repository"
    echo ""
    echo "Raffaello uses git branches to isolate work for each user story."
    echo "This allows parallel execution and easy rollback if needed."
    echo ""

    # Safety checks before initializing git
    local current_dir
    current_dir="$(pwd)"

    # CRITICAL: Prevent git init in dangerous locations
    # Block home directory (any user)
    if [[ "$current_dir" == "$HOME" ]]; then
      log_error "UNSAFE LOCATION: Cannot initialize git in home directory!"
      log_error "Current directory: $current_dir"
      echo ""
      echo "Initializing git in your home directory would track ALL personal files."
      echo ""
      echo "Please:"
      echo "  1. Create a dedicated project directory"
      echo "  2. cd into that directory"
      echo "  3. Run raffaello.sh again"
      echo ""
      echo "Example:"
      echo "  mkdir -p ~/projects/my-project"
      echo "  cd ~/projects/my-project"
      echo "  cp /path/to/prd.json ."
      echo "  /path/to/raffaello.sh"
      exit 1
    fi

    # Block system critical directories (macOS and Linux)
    local dangerous_dirs=(
      "/"                    # Root
      "/bin"                 # System binaries
      "/boot"                # Boot files (Linux)
      "/dev"                 # Device files
      "/etc"                 # System configuration
      "/lib"                 # System libraries
      "/lib64"               # 64-bit libraries (Linux)
      "/opt"                 # Optional packages
      "/proc"                # Process info (Linux)
      "/root"                # Root user home (Linux)
      "/sbin"                # System binaries
      "/sys"                 # System info (Linux)
      "/tmp"                 # Temporary files
      "/usr"                 # User programs
      "/var"                 # Variable data
      "/System"              # macOS system
      "/Library"             # macOS system library
      "/Applications"        # macOS applications
      "/Users"               # macOS users directory
      "/home"                # Linux users directory
      "/mnt"                 # Mount points (Linux)
      "/media"               # Removable media (Linux)
      "/srv"                 # Service data (Linux)
    )

    for dangerous_dir in "${dangerous_dirs[@]}"; do
      if [[ "$current_dir" == "$dangerous_dir" ]]; then
        log_error "UNSAFE LOCATION: Cannot initialize git in system directory!"
        log_error "Current directory: $current_dir"
        echo ""
        echo "This is a critical system directory."
        echo "Initializing git here could damage your system."
        echo ""
        echo "Please create a project directory in a safe location:"
        echo "  mkdir -p ~/projects/my-project"
        echo "  cd ~/projects/my-project"
        exit 1
      fi
    done

    # Block top-level user directories (e.g., /Users/username, /home/username)
    if [[ "$current_dir" =~ ^/Users/[^/]+$ ]] || \
       [[ "$current_dir" =~ ^/home/[^/]+$ ]]; then
      log_error "UNSAFE LOCATION: Cannot initialize git in user home directory!"
      log_error "Current directory: $current_dir"
      echo ""
      echo "This is a user home directory."
      echo "Please create a subdirectory for your project:"
      echo "  mkdir -p $current_dir/projects/my-project"
      echo "  cd $current_dir/projects/my-project"
      exit 1
    fi

    # Show current directory prominently
    echo "════════════════════════════════════════"
    echo "⚠️  GIT INITIALIZATION WARNING"
    echo "════════════════════════════════════════"
    echo ""
    echo "Current directory:"
    echo "  $current_dir"
    echo ""
    echo "This will:"
    echo "  1. Run: git init"
    echo "  2. Run: git add -A (stage ALL files in this directory)"
    echo "  3. Run: git commit -m 'Initial commit'"
    echo ""
    echo "Files in current directory:"
    ls -la | head -10
    echo ""
    echo "════════════════════════════════════════"
    echo ""
    echo "Is this the CORRECT project directory? (yes/no)"
    echo "Type 'yes' to proceed, anything else to abort:"

    local answer
    if [[ "$RAFFAELLO_ASSUME_YES" == "true" ]]; then
      answer="yes"
      echo "[INFO] RAFFAELLO_ASSUME_YES=true: auto-confirmed" >&2
    else
      if [[ ! -t 0 ]]; then
        log_error "stdin is not interactive; refusing to wait for confirmation"
        log_error "Re-run with RAFFAELLO_ASSUME_YES=true or start raffaello.sh in an interactive terminal"
        exit 1
      fi
      read -r answer
    fi

    if [[ "$answer" == "yes" ]]; then
      log_info "Initializing git repository in: $current_dir"

      # Initialize git
      if ! git init; then
        log_error "git init failed"
        exit 1
      fi

      # Show what will be added
      echo ""
      log_info "Files to be added to git:"
      git status --short | head -20
      local file_count
      file_count=$(git status --short | wc -l | tr -d ' ')
      if [[ $file_count -gt 20 ]]; then
        echo "... and $((file_count - 20)) more files"
      fi
      echo ""

      # Final confirmation before git add
      echo "About to stage $file_count files. Continue? (yes/no)"

      local confirm
      if [[ "$RAFFAELLO_ASSUME_YES" == "true" ]]; then
        confirm="yes"
        echo "[INFO] RAFFAELLO_ASSUME_YES=true: auto-confirmed" >&2
      else
        if [[ ! -t 0 ]]; then
          log_error "stdin is not interactive; refusing to wait for confirmation"
          log_error "Re-run with RAFFAELLO_ASSUME_YES=true or start raffaello.sh in an interactive terminal"
          rm -rf .git
          exit 1
        fi
        read -r confirm
      fi
      if [[ "$confirm" != "yes" ]]; then
        log_warn "Aborting. Cleaning up git repository..."
        rm -rf .git
        exit 1
      fi

      # Add and commit
      git add -A
      if git commit -m "Initial commit"; then
        log_success "Git repository initialized successfully"
      else
        log_error "git commit failed (this is okay if there are no files)"
      fi
    else
      log_error "Git repository required to use Raffaello"
      echo ""
      echo "To initialize manually in the correct directory:"
      echo "  cd /path/to/your/project"
      echo "  git init"
      echo "  git add -A"
      echo "  git commit -m 'Initial commit'"
      exit 1
    fi
  fi

  # Check if on main/master branch
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ -n "$current_branch" && "$current_branch" != "main" && "$current_branch" != "master" ]]; then
    log_warn "Not on main/master branch (currently on: $current_branch)"
    echo ""
    echo "Raffaello works best when starting from main/master branch."
    echo "Would you like to checkout main? (y/n)"
    read -r answer
    if [[ "$answer" =~ ^[Yy] ]]; then
      # Try main first, then master
      if git rev-parse --verify main &>/dev/null; then
        git checkout main
        log_success "Checked out main branch"
      elif git rev-parse --verify master &>/dev/null; then
        git checkout master
        log_success "Checked out master branch"
      else
        log_warn "Neither main nor master branch exists, staying on $current_branch"
      fi
    else
      log_warn "Continuing on branch: $current_branch"
    fi
  fi

  # Detect and validate CLI
  CLI=$(detect_cli)
  log_success "Detected CLI: $CLI"

  if ! check_multiagents_support "$CLI"; then
    exit 1
  fi

  log_success "Prerequisites check passed"
}

# Get incomplete stories from PRD
get_incomplete_stories() {
  jq -r '.userStories[] | select(.passes == false) | .id' "$PRD_FILE"
}

# Get story details
get_story() {
  local story_id=$1
  jq ".userStories[] | select(.id == \"$story_id\")" "$PRD_FILE"
}

# Get story title
get_story_title() {
  local story_id=$1
  local title
  title=$(get_story "$story_id" | jq -r '.title')
  if [[ -z "$title" || "$title" == "null" ]]; then
    log_error "Story not found in PRD: $story_id"
    return 1
  fi
  echo "$title"
}

# Get story workflow (default to 'standard')
get_story_workflow() {
  local story_id=$1
  get_story "$story_id" | jq -r '.workflow // "standard"'
}

# Validate story exists in PRD
validate_story_exists() {
  local story_id=$1
  local story
  story=$(get_story "$story_id")
  if [[ -z "$story" || "$story" == "null" ]]; then
    log_error "Story not found in PRD: $story_id"
    log_error "Available stories: $(jq -r '.userStories[].id' "$PRD_FILE" | tr '\n' ' ')"
    return 1
  fi
  return 0
}

# Analyze dependencies and return parallelizable stories
# For Phase 2, we use simple implementation from dependency-analyzer.sh
analyze_dependencies() {
  "$SCRIPT_DIR/lib/dependency-analyzer.sh" "$PRD_FILE"
}

# Execute a single story in background
execute_story() {
  local story_id=$1
  local story_title=$2

  log_info "Starting story: $story_id - $story_title"

  # Validate story exists
  if ! validate_story_exists "$story_id"; then
    return 1
  fi

  local branch_name="story-$story_id"
  local worktree_dir="$PWD/.raffaello-worktrees/$story_id"

  # IMPORTANT: avoid stale phase markers across runs.
  # /tmp/raffaello is shared; old .<phase>-success files can cause false PASS.
  local agent_comm_dir="${AGENT_COMM_DIR:-/tmp/raffaello}"
  rm -rf "$agent_comm_dir/$story_id" 2>/dev/null || true
  mkdir -p "$agent_comm_dir/$story_id" 2>/dev/null || true

  # Create worktree for this story (isolated working directory)
  if git rev-parse --verify "$branch_name" &>/dev/null; then
    # Branch exists, create worktree from it
    if [[ -d "$worktree_dir" ]]; then
      # If the directory already exists but is not a valid worktree, recreate it.
      if git worktree list --porcelain 2>/dev/null | grep -Fq "worktree $worktree_dir"; then
        log_warn "Worktree already exists for $story_id, reusing"
      else
        log_warn "Stale worktree directory for $story_id detected, recreating"
        rm -rf "$worktree_dir" 2>/dev/null || true
        git worktree add "$worktree_dir" "$branch_name" 2>/dev/null || {
          log_error "Failed to recreate worktree for branch: $branch_name"
          return 1
        }
      fi
    else
      git worktree add "$worktree_dir" "$branch_name" 2>/dev/null || {
        log_error "Failed to create worktree for existing branch: $branch_name"
        return 1
      }
    fi
  else
    # Create new branch and worktree
    # If branch already exists (race or leftover), fall back to creating from the existing branch.
    if git rev-parse --verify "$branch_name" &>/dev/null; then
      rm -rf "$worktree_dir" 2>/dev/null || true
      git worktree add "$worktree_dir" "$branch_name" 2>/dev/null || {
        log_error "Failed to create worktree for existing branch: $branch_name"
        return 1
      }
    else
      rm -rf "$worktree_dir" 2>/dev/null || true
      git worktree add -b "$branch_name" "$worktree_dir" 2>/dev/null || {
        log_error "Failed to create worktree with branch: $branch_name"
        return 1
      }
    fi
  fi

  # Execute orchestrator in the worktree directory
  # Copy PRD file to worktree if needed
  if [[ -f "$PRD_FILE" ]]; then
    cp "$PRD_FILE" "$worktree_dir/prd.json"
  fi

  # Change to worktree directory and run orchestrator.
  # IMPORTANT: avoid `| tee` pipelines here.
  # If the parent stdout closes (common in some terminals/CI), `tee` can receive SIGPIPE,
  # which can tear down the pipeline and make the story look like it "failed" mid-run.
  # Instead, write logs directly to file; users can `tail -f` the per-story log.
  local log_file="$LOG_DIR/${story_id}.log"
  (
    cd "$worktree_dir" || exit 1

    # Run orchestrator under a clean bash to reduce environment-related parsing issues.
    # (e.g., user shell configs via BASH_ENV or unexpected aliases/functions)
    PRD_FILE="$worktree_dir/prd.json" \
      bash --noprofile --norc "$SCRIPT_DIR/orchestrator.sh" "$story_id" >>"$log_file" 2>&1
  )

  local exit_code=$?

  # Keep PRD authoritative in the main worktree to avoid last-writer-wins races.
  # Orchestrator updates the PRD inside its worktree; here we only patch the single story's
  # 'passes' flag back into main, guarded by flock.
  if [[ -f "$worktree_dir/prd.json" ]]; then
    local story_passes
    story_passes=$(jq -r ".userStories[] | select(.id == \"$story_id\") | .passes" "$worktree_dir/prd.json" 2>/dev/null || echo "")

    if [[ "$story_passes" == "true" || "$story_passes" == "false" ]]; then
      local lock_file="$PRD_FILE.lock"
      if (
        flock -w 30 9 || exit 1
        tmp_file=$(mktemp)
        jq "(.userStories[] | select(.id == \"$story_id\") | .passes) = $story_passes" "$PRD_FILE" >"$tmp_file" && mv "$tmp_file" "$PRD_FILE"
      ) 9>"$lock_file"; then
        :
      else
        log_warn "Failed to acquire lock for PRD update, story may not be marked as complete"
      fi
    else
      log_warn "Could not read passes status for $story_id from worktree PRD"
    fi
  fi

  return $exit_code
}

# Main execution loop
main() {
  log_info "=== Raffaello - Starting Execution ==="
  echo ""

  acquire_pid_lock

  # Check prerequisites
  check_prerequisites
  echo ""

  local iteration=1
  while [[ $iteration -le $GLOBAL_MAX_ITERATIONS ]]; do
    # Get incomplete stories
    local incomplete_stories
    incomplete_stories=$(get_incomplete_stories)

    if [[ -z "$incomplete_stories" ]]; then
      log_success "All stories are complete!"
      echo ""
      echo "<promise>COMPLETE</promise>"
      exit 0
    fi

    # Count incomplete stories
    local story_count
    story_count=$(echo "$incomplete_stories" | wc -l | tr -d ' ')
    log_info "Iteration $iteration/$GLOBAL_MAX_ITERATIONS: $story_count incomplete stories"
    echo ""

    # Analyze dependencies and get execution batches
    log_info "Analyzing dependencies..."
    local execution_plan
    execution_plan=$("$SCRIPT_DIR/lib/dependency-analyzer.sh" "$PRD_FILE")

    # Parse execution plan (JSON format)
    local batches
    batches=$(echo "$execution_plan" | jq -r '.batches | length')

    log_info "Execution plan: $batches batches"
    echo ""

  # Show log directory location
  echo "════════════════════════════════════════"
  echo "📁 Story logs will be saved to:"
  echo "   $LOG_DIR/"
  echo ""
  echo "Monitor individual stories:"
  echo "   tail -f $LOG_DIR/<STORY_ID>.log"
  echo ""
  echo "Common debugging commands:"
  echo "   ls -la ${AGENT_COMM_DIR:-/tmp/raffaello}/<STORY_ID>/"
  echo "   tail -f ${AGENT_COMM_DIR:-/tmp/raffaello}/<STORY_ID>/<PHASE>-output.txt"
  echo "   cat ${AGENT_COMM_DIR:-/tmp/raffaello}/<STORY_ID>/<PHASE>.pid"
  echo "   pid=\$(cat ${AGENT_COMM_DIR:-/tmp/raffaello}/<STORY_ID>/<PHASE>.pid 2>/dev/null || true); [[ -n \"\$pid\" ]] && ps -p \"\$pid\" -o pid,ppid,cmd || echo \"no pid\""
  echo "Monitor (optional):"
  echo "   nohup $SCRIPT_DIR/raffaello/monitor.sh \"$(pwd)\" > $LOG_DIR/monitor.nohup.log 2>&1 &"
  echo "   tail -f $LOG_DIR/monitor.nohup.log"
  echo "Auto kill-stalled (optional):"
  echo "   AUTO_MONITOR_KILL=true MONITOR_STALL_SECS=300 MONITOR_INTERVAL_SECS=10 $0"
  echo "════════════════════════════════════════"
  echo ""

  # Start kill-stalled monitor in background if enabled.
  # Write directly to monitor-kill.log (and optionally mirror to stdout via --stdout).
  if [[ "$AUTO_MONITOR_KILL" == "true" ]]; then
    log_warn "AUTO_MONITOR_KILL=true: will kill stalled agents (stall=${MONITOR_STALL_SECS}s interval=${MONITOR_INTERVAL_SECS}s)"
    echo "[INFO] Monitor-kill log: $LOG_DIR/monitor-kill.log"
    # If a previous run left a monitor-kill process behind, stop it first.
    if [[ -f "$LOG_DIR/monitor-kill.pid" ]]; then
      old_pid=$(cat "$LOG_DIR/monitor-kill.pid" 2>/dev/null || true)
      if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
        kill -TERM "$old_pid" 2>/dev/null || true
      fi
      rm -f "$LOG_DIR/monitor-kill.pid" 2>/dev/null || true
    fi
    (
      STALL_SECS="$MONITOR_STALL_SECS" INTERVAL_SECS="$MONITOR_INTERVAL_SECS" KILL_STALLED=true OUT_LOG="$LOG_DIR/monitor-kill.log" \
        bash "$SCRIPT_DIR/raffaello/monitor.sh" "$(pwd)" >/dev/null 2>&1
    ) &
    echo $! >"$LOG_DIR/monitor-kill.pid" 2>/dev/null || true
    disown $! 2>/dev/null || true
    log_info "Monitor-kill started (pid=$(cat "$LOG_DIR/monitor-kill.pid" 2>/dev/null || echo "?"))."
  fi

    local any_failed=0

    # Execute each batch
    local batch_idx=0
    while [[ $batch_idx -lt $batches ]]; do
    local batch_stories
    batch_stories=$(echo "$execution_plan" | jq -r ".batches[$batch_idx][]")

    log_info "=== Batch $((batch_idx + 1)) / $batches ==="

    # Track background processes
    local pids=()

    # Execute stories in this batch (parallel, up to MAX_PARALLEL_STORIES at a time)
    local concurrent=0
    for story_id in $batch_stories; do
      local story_title
      story_title=$(get_story_title "$story_id") || continue

      # Start story execution in background
      log_info "Starting story: $story_id - $story_title"
      echo "  → Log file: $LOG_DIR/${story_id}.log"
      echo "  → Monitor: tail -f $LOG_DIR/${story_id}.log"
      echo ""

      execute_story "$story_id" "$story_title" &
      local pid=$!
      pids+=("$pid")

      # Store PID to story_id mapping in file (Bash 3.2 compatible)
      echo "$story_id" > "$PID_TRACKING_DIR/$pid"

      ((concurrent++)) || true

      # If we've reached max parallel, wait for one to finish
      if [[ $concurrent -ge $MAX_PARALLEL_STORIES ]]; then
        # Throttle: wait for the oldest PID we still track.
        # This is portable (no `wait -n`) and avoids `set -e` traps on bash 3.2.
        wait "${pids[0]}" || true
        pids=("${pids[@]:1}")
        ((concurrent--)) || true
      fi
    done

    # Ensure we wait for any remaining PIDs started in this batch.
    # (Some may have already been reaped by the throttle wait above.)
    if [[ ${#pids[@]} -eq 0 ]]; then
      log_info "No remaining processes to wait for in this batch"
    fi

    # Wait for all stories in this batch to complete
    log_info "Waiting for batch $((batch_idx + 1)) to complete..."
      for pid in "${pids[@]}"; do
      local story_id
      if [[ -f "$PID_TRACKING_DIR/$pid" ]]; then
        story_id=$(<"$PID_TRACKING_DIR/$pid")
      else
        story_id="unknown"
      fi

        if wait "$pid"; then
        log_success "Story $story_id finished successfully"
        echo "  → Full log: $LOG_DIR/${story_id}.log"
      else
        log_error "Story $story_id failed"
        echo "  → Check log: $LOG_DIR/${story_id}.log"
        any_failed=1
        # Continue with other stories even if one fails
      fi
    done

    echo ""
      ((batch_idx++)) || true
    done

    # Check if all stories are now complete
    local remaining_incomplete
    remaining_incomplete=$(get_incomplete_stories)
    if [[ -z "$remaining_incomplete" ]]; then
      log_success "All stories completed in this iteration!"
      break
    fi

    if [[ $any_failed -eq 0 ]]; then
      # No failures but still incomplete stories - continue to next iteration
      log_info "Batch completed successfully, continuing with remaining stories..."
    else
      if [[ $iteration -lt $GLOBAL_MAX_ITERATIONS ]]; then
        log_warn "Some stories failed; rerunning incomplete stories (next iteration)"
        echo ""
      fi
    fi

    ((iteration++))
  done

  # Clean up worktrees
  log_info "Cleaning up worktrees..."
  if [[ -d "$PWD/.raffaello-worktrees" ]]; then
    for worktree_path in "$PWD/.raffaello-worktrees"/*; do
      if [[ -d "$worktree_path" ]]; then
        git worktree remove "$worktree_path" 2>/dev/null || {
          log_warn "Failed to remove worktree: $worktree_path, forcing cleanup"
          rm -rf "$worktree_path" 2>/dev/null || true
        }
      fi
    done
    rmdir "$PWD/.raffaello-worktrees" 2>/dev/null || true
  fi
  git worktree prune 2>/dev/null || true
  log_success "Worktrees cleaned up"
  echo ""

  # Clean up agent communication dirs for this project run.
  # /tmp/raffaello is shared across runs; leaving old STORY-* dirs around confuses monitoring
  # and can contribute to stale state issues.
  log_info "Cleaning up agent communication directories..."
  local agent_comm_dir="${AGENT_COMM_DIR:-/tmp/raffaello}"
  rm -rf "$agent_comm_dir"/STORY-[0-9]* 2>/dev/null || true
  log_success "Agent communication directories cleaned"
  echo ""

  # Merge all story branches
  log_info "=== Merging Story Branches ==="
  if "$SCRIPT_DIR/merge-stories.sh"; then
    log_success "All stories merged successfully"
  else
    log_warn "Some merge conflicts require manual resolution"
  fi

  echo ""
  log_success "=== Raffaello - Execution Complete ==="

  release_pid_lock
}

# Run main
main "$@"
