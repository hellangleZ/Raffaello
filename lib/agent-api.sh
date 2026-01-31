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

DEFAULT_CLAUDE_TOOLS=${DEFAULT_CLAUDE_TOOLS:-"Bash,Read,Write,Edit,Glob,Grep"}
DEFAULT_CLAUDE_MODEL=${DEFAULT_CLAUDE_MODEL:-"sonnet"}

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

  # Claude Code: run a single CLI process per phase.
  mkdir -p "$AGENT_COMM_DIR/$story_id"
  local prompt_file="$AGENT_COMM_DIR/$story_id/${agent_name}-prompt.txt"
  local output_file="$AGENT_COMM_DIR/$story_id/${agent_name}-output.txt"

  # Clear old output file before spawning new agent to avoid stale data on retry
  rm -f "$output_file" 2>/dev/null || true

  # Build prompt without markdown list prefixes at line starts.
  # Some Claude Code builds can hang when stdin contains long markdown lists,
  # especially when piping via `--print`.
  local full_prompt
  full_prompt="Agent role: $agent_name

$(sed 's/^\s*[-*]\s\+ /  /' "$agent_prompt_file")

Task:
$(printf '%s' "$task_message" | sed 's/^\s*[-*]\s\+ /  /')

Story ID: $story_id
Communication Directory: $AGENT_COMM_DIR/$story_id"

  # Write prompt to file
  echo "$full_prompt" > "$prompt_file"

  # Run claude in non-interactive print mode.
  # IMPORTANT:
  # - Use `--print` mode so output is captured to file.
  # - Use bypass permissions + skip permissions so tools can run.
  # - Prefer `--allowed-tools` to avoid interactive tool gating.
  # Feed the prompt via stdin. Also add the communication directory to Claude's
  # tool allowlist so file operations are permitted.
  COMMUNICATION_DIRECTORY="$AGENT_COMM_DIR/$story_id" \
    stdbuf -oL -eL bash -lc \
      "claude -p \
        --model '$DEFAULT_CLAUDE_MODEL' \
        --no-session-persistence \
        --permission-mode bypassPermissions \
        --add-dir '$AGENT_COMM_DIR/$story_id' \
        --allowed-tools '$DEFAULT_CLAUDE_TOOLS' \
        --dangerously-skip-permissions" \
      < "$prompt_file" >"$output_file" 2>&1 &
  local agent_pid=$!

  # Persist PID for debugging/monitoring.
  echo "$agent_pid" >"$AGENT_COMM_DIR/$story_id/${agent_name}.pid"

  # Give claude a moment to start
  sleep 0.5

  # Agent is running in background - return pid based identifier
  echo "cc-pid-$agent_pid"
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
  local preflight_timeout=${AGENT_PREFLIGHT_TIMEOUT_SECS:-120} # pre-flight hang cutoff

  if [[ "$agent_id" == "cc-sync" ]]; then
    # Synchronous execution, already complete
    :
  elif [[ "$agent_id" =~ ^cc-pid-([0-9]+)$ ]]; then
    local agent_pid="${BASH_REMATCH[1]}"
    local elapsed=0
    local check_interval=2
    local output_file="$AGENT_COMM_DIR/$story_id/${agent_name}-output.txt"
    local last_size=0
    if [[ -f "$output_file" ]]; then
      last_size=$(wc -c <"$output_file" | tr -d ' ')
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

      # If process already exited and no success marker, stop waiting.
      if ! kill -0 "$agent_pid" 2>/dev/null; then
        return 1
      fi

      # Heartbeat: detect if output is growing.
      local current_size=0
      if [[ -f "$output_file" ]]; then
        current_size=$(wc -c <"$output_file" | tr -d ' ')
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

  # Claude Code: no explicit cleanup needed.
  :
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
