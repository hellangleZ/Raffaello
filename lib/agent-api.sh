#!/usr/bin/env bash
# Unified Agent API
# Provides a consistent interface for spawning and managing agents across Claude Code and Codex

set -euo pipefail

# Source CLI detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect-cli.sh"

# Temporary directory for agent communication
AGENT_COMM_DIR="${AGENT_COMM_DIR:-/tmp/ralph-parallel}"
mkdir -p "$AGENT_COMM_DIR"

# Spawn an agent with a specific role
# Args: $1=agent_name, $2=task_message, $3=story_id (optional)
spawn_agent() {
  local cli=$(detect_cli)
  local agent_name=$1
  local task_message=$2
  local story_id=${3:-"default"}

  local agent_prompt_file="$SCRIPT_DIR/../agents/${agent_name}.md"

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

  if [[ "$cli" == "claude-code" ]]; then
    # Claude Code: Use stdin for prompt
    # Task tool manages agent lifecycle automatically
    local output_file="$AGENT_COMM_DIR/$story_id/${agent_name}-output.txt"

    echo "$full_prompt" | claude --print > "$output_file" 2>&1 &
    local agent_pid=$!

    # Return agent ID (using PID as identifier for Claude Code)
    echo "cc-$agent_pid"

  elif [[ "$cli" == "codex" ]]; then
    # Codex: Use spawn_agent API
    local agent_type="worker"

    # Create temporary file for Codex input
    local codex_input="$AGENT_COMM_DIR/$story_id/${agent_name}-input.json"
    cat > "$codex_input" <<EOF
{
  "tool": "spawn_agent",
  "message": $(echo "$full_prompt" | jq -Rs .),
  "agent_type": "$agent_type"
}
EOF

    # Call Codex and capture agent_id
    local response
    response=$(codex < "$codex_input")

    # Extract agent_id from response
    local agent_id
    agent_id=$(echo "$response" | jq -r '.agent_id // empty')

    if [[ -z "$agent_id" ]]; then
      echo "ERROR: Failed to spawn Codex agent" >&2
      echo "Response: $response" >&2
      exit 1
    fi

    echo "$agent_id"
  fi
}

# Wait for multiple agents to complete
# Args: $@=agent_ids
wait_for_agents() {
  local cli=$(detect_cli)

  if [[ "$cli" == "claude-code" ]]; then
    # Claude Code: Extract PIDs and wait
    for agent_id in "$@"; do
      if [[ "$agent_id" =~ ^cc-([0-9]+)$ ]]; then
        local pid="${BASH_REMATCH[1]}"
        wait "$pid" 2>/dev/null || true
      fi
    done

  elif [[ "$cli" == "codex" ]]; then
    # Codex: Use wait API
    local ids_json
    ids_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)

    local codex_input
    codex_input=$(cat <<EOF
{
  "tool": "wait",
  "agent_ids": $ids_json
}
EOF
)

    codex <<< "$codex_input" > /dev/null
  fi
}

# Close/cleanup an agent
# Args: $1=agent_id
close_agent() {
  local cli=$(detect_cli)
  local agent_id=$1

  if [[ "$cli" == "claude-code" ]]; then
    # Claude Code: Kill process if still running
    if [[ "$agent_id" =~ ^cc-([0-9]+)$ ]]; then
      local pid="${BASH_REMATCH[1]}"
      kill "$pid" 2>/dev/null || true
    fi

  elif [[ "$cli" == "codex" ]]; then
    # Codex: Use close_agent API
    local codex_input
    codex_input=$(cat <<EOF
{
  "tool": "close_agent",
  "agent_id": "$agent_id"
}
EOF
)

    codex <<< "$codex_input" > /dev/null
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
