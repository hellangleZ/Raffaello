#!/usr/bin/env bash
# Agent API for Claude Code
# Provides interface for spawning and managing agents using Claude Code CLI

set -euo pipefail

# Source CLI detection
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/detect-cli.sh"

# Temporary directory for agent communication
AGENT_COMM_DIR="${AGENT_COMM_DIR:-/tmp/ralph-parallel}"
mkdir -p "$AGENT_COMM_DIR"

# Spawn an agent with a specific role
# Args: $1=agent_name, $2=task_message, $3=story_id (optional)
spawn_agent() {
  local agent_name=$1
  local task_message=$2
  local story_id=${3:-"default"}

  local agent_prompt_file="$LIB_DIR/../agents/${agent_name}.md"

  if [[ ! -f "$agent_prompt_file" ]]; then
    echo "ERROR: Agent prompt not found: $agent_prompt_file" >&2
    exit 1
  fi

  # Claude Code: Use Task tool (spawns managed background task)
  # NOTE: Claude Code manages agent lifecycle automatically via Task system
  mkdir -p "$AGENT_COMM_DIR/$story_id"
  local prompt_file="$AGENT_COMM_DIR/$story_id/${agent_name}-prompt.txt"
  local output_file="$AGENT_COMM_DIR/$story_id/${agent_name}-output.txt"

  # Clear old output file before spawning new agent to avoid stale data on retry
  rm -f "$output_file" 2>/dev/null || true

  local full_prompt
  full_prompt="$(<"$agent_prompt_file")

---

Task: $task_message

Story ID: $story_id
Communication Directory: $AGENT_COMM_DIR/$story_id"

  # Write prompt to file
  echo "$full_prompt" > "$prompt_file"

  # Run claude with auto-accept permissions for autonomous execution
  # IMPORTANT: Run from current directory (project root), not from communication directory
  # Pass COMMUNICATION_DIRECTORY as environment variable so agents know where to write markers
  # Use background execution with output capture
  # Start agent asynchronously. Do not use command substitution here; it would wait.
  # Use stdbuf so output is line-buffered (helps monitoring and heartbeat checks).
  COMMUNICATION_DIRECTORY="$AGENT_COMM_DIR/$story_id" \
    stdbuf -oL -eL claude --dangerously-skip-permissions < "$prompt_file" >"$output_file" 2>&1 &
  local agent_pid=$!

  # Some environments kill background jobs when the parent shell exits.
  # We want story agents to survive independently of ralph.sh/orchestrator.sh,
  # so detach the process from the parent job control when possible.
  disown "$agent_pid" 2>/dev/null || true

  # Persist PID for debugging/monitoring.
  echo "$agent_pid" >"$AGENT_COMM_DIR/$story_id/${agent_name}.pid"

  # Give claude a moment to start
  sleep 0.5

  # Extract task ID from running tasks
  # Claude Code spawns background tasks - we need to find the most recent one
  local task_id=""
  local max_attempts=5
  local attempt=0

  while [[ -z "$task_id" && $attempt -lt $max_attempts ]]; do
    # Try to get task ID from various sources
    # Method 2: Check for success marker (agent completed quickly)
    if [[ -f "$AGENT_COMM_DIR/$story_id/.${agent_name}-success" ]]; then
      task_id="sync"
      break
    fi

    ((attempt++))
    sleep 0.5
  done

  if [[ "$task_id" == "sync" ]]; then
    # Agent completed synchronously
    echo "cc-sync"
  else
    # Agent is running in background - return pid based identifier
    echo "cc-pid-$agent_pid"
  fi
}

# Wait for multiple agents to complete
# Args: $1=story_id, $2=agent_name, $3=agent_id
wait_for_agent() {
  local story_id=$1
  local agent_name=$2
  local agent_id=$3
  local success_file="$AGENT_COMM_DIR/$story_id/.${agent_name}-success"

  # Optional: allow orchestrator/monitor to force-abort an agent by dropping an abort marker.
  # This is useful when the CLI is hanging and not producing output.
  local abort_file="$AGENT_COMM_DIR/$story_id/.${agent_name}-abort"

  local timeout=${AGENT_TIMEOUT_SECS:-1800} # 30 minutes default
  local idle_timeout=${AGENT_IDLE_TIMEOUT_SECS:-300} # 5 minutes without output

  if [[ "$agent_id" =~ ^cc-task-([a-f0-9]+)$ ]]; then
    local task_id="${BASH_REMATCH[1]}"
    # Use claude task output command to wait for completion
    claude task output "$task_id" > /dev/null 2>&1 || true
  elif [[ "$agent_id" == "cc-sync" ]]; then
    # Synchronous execution, already complete
    :
  elif [[ "$agent_id" =~ ^cc-pid-([0-9]+)$ ]]; then
    local agent_pid="${BASH_REMATCH[1]}"
    local elapsed=0
    local check_interval=2
    local last_size=0
    if [[ -f "$AGENT_COMM_DIR/$story_id/${agent_name}-output.txt" ]]; then
      last_size=$(wc -c <"$AGENT_COMM_DIR/$story_id/${agent_name}-output.txt" | tr -d ' ')
    fi
    local idle_elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
      if [[ -f "$abort_file" ]]; then
        # Abort markers are meant to cancel the current attempt quickly.
        # Remove the marker so subsequent retries can proceed normally.
        rm -f "$abort_file" 2>/dev/null || true
        echo "WARNING: Agent $agent_name aborted by marker: $abort_file" >&2
        return 1
      fi

      if [[ -f "$success_file" ]]; then
        return 0
      fi

      # Heartbeat: detect if output is growing.
      local current_size=0
      if [[ -f "$AGENT_COMM_DIR/$story_id/${agent_name}-output.txt" ]]; then
        current_size=$(wc -c <"$AGENT_COMM_DIR/$story_id/${agent_name}-output.txt" | tr -d ' ')
      fi
      if [[ $current_size -gt $last_size ]]; then
        last_size=$current_size
        idle_elapsed=0
      else
        ((idle_elapsed += check_interval))
      fi

      if [[ $idle_elapsed -ge $idle_timeout ]]; then
        echo "WARNING: Agent $agent_name has no new output for ${idle_timeout}s" >&2
        return 1
      fi

      # If process already exited and no success marker, stop waiting.
      if ! kill -0 "$agent_pid" 2>/dev/null; then
        return 1
      fi

      sleep $check_interval
      ((elapsed += check_interval))
    done

    echo "WARNING: Agent $agent_name did not complete within ${timeout}s" >&2
    return 1
  fi
}

# Close/cleanup an agent
# Args: $1=agent_id
close_agent() {
  local agent_id=$1

  # Claude Code: Tasks are auto-managed, no explicit cleanup needed
  if [[ "$agent_id" =~ ^cc-task-([a-f0-9]+)$ ]]; then
    :
  fi
}

# Check if agent succeeded (by looking for success marker file)
# Args: $1=story_id, $2=agent_name
check_agent_success() {
  local story_id=$1
  local agent_name=$2
  local success_file="$AGENT_COMM_DIR/$story_id/.${agent_name}-success"

  [[ -f "$success_file" ]]
}

# Mark agent as successful
# Args: $1=story_id, $2=agent_name
mark_agent_success() {
  local story_id=$1
  local agent_name=$2
  local success_file="$AGENT_COMM_DIR/$story_id/.${agent_name}-success"

  touch "$success_file"
}

# Get agent output
# Args: $1=story_id, $2=agent_name
get_agent_output() {
  local story_id=$1
  local agent_name=$2
  local output_file="$AGENT_COMM_DIR/$story_id/${agent_name}-output.txt"

  if [[ -f "$output_file" ]]; then
    cat "$output_file"
  fi
}
