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

  local full_prompt
  full_prompt="$(<"$agent_prompt_file")

---

Task: $task_message

Story ID: $story_id
Communication Directory: $AGENT_COMM_DIR/$story_id"

  # Claude Code: Use Task tool (spawns managed background task)
  # NOTE: Claude Code manages agent lifecycle automatically via Task system
  mkdir -p "$AGENT_COMM_DIR/$story_id"
  local prompt_file="$AGENT_COMM_DIR/$story_id/${agent_name}-prompt.txt"
  local output_file="$AGENT_COMM_DIR/$story_id/${agent_name}-output.txt"

  # Write prompt to file
  echo "$full_prompt" > "$prompt_file"

  # Run claude with auto-accept permissions for autonomous execution
  # IMPORTANT: Run from current directory (project root), not from communication directory
  # Pass COMMUNICATION_DIRECTORY as environment variable so agents know where to write markers
  local task_output
  task_output=$(COMMUNICATION_DIRECTORY="$AGENT_COMM_DIR/$story_id" claude --dangerously-skip-permissions --print < "$prompt_file" 2>&1)

  # Extract task ID from output (format: "Command running in background with ID: <id>")
  local task_id
  task_id=$(echo "$task_output" | grep -oE "ID: [a-f0-9]+" | cut -d' ' -f2 || echo "")

  if [[ -z "$task_id" ]]; then
    # If no task ID found, claude might have run synchronously (old version)
    echo "$task_output" > "$output_file"
    echo "cc-sync"
  else
    # Return task ID as agent ID
    echo "cc-task-$task_id"
  fi
}

# Wait for multiple agents to complete
# Args: $@=agent_ids
wait_for_agents() {
  # Claude Code: Wait for task completion using claude task output
  for agent_id in "$@"; do
    if [[ "$agent_id" =~ ^cc-task-([a-f0-9]+)$ ]]; then
      local task_id="${BASH_REMATCH[1]}"
      # Use claude task output command to wait for completion
      # This is a synchronous wait (blocks until task completes)
      claude task output "$task_id" > /dev/null 2>&1 || true
    elif [[ "$agent_id" == "cc-sync" ]]; then
      # Synchronous execution, already complete
      :
    fi
  done
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
