#!/usr/bin/env bash
# Dynamic Agent Loader
# Discovers and validates available agents (core + optional)

set -euo pipefail

# Source CLI detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/detect-cli.sh"

# Core agents (built-in, always required)
CORE_AGENTS=("planner" "coder" "reviewer" "tester")

# Discover optional agents from user's agent directory
# Returns: List of agent names (without .md extension)
discover_optional_agents() {
  local cli=$(detect_cli)
  local agent_dir=$(get_agent_dir "$cli")

  # List all .md files (excluding core agents)
  if [[ -d "$agent_dir" ]]; then
    find "$agent_dir" -maxdepth 1 -name "*.md" -type f | while read -r file; do
      local agent_name=$(basename "$file" .md)

      # Skip core agents (we have our own versions)
      if [[ ! " ${CORE_AGENTS[@]} " =~ " ${agent_name} " ]]; then
        echo "$agent_name"
      fi
    done
  fi
}

# Get all available agents (core + optional)
list_all_agents() {
  # Core agents
  printf '%s\n' "${CORE_AGENTS[@]}"

  # Optional agents
  discover_optional_agents
}

# Check if an agent exists (core or optional)
agent_exists() {
  local agent_name=$1
  local cli=$(detect_cli)

  # Check core agents first
  if [[ " ${CORE_AGENTS[@]} " =~ " ${agent_name} " ]]; then
    local core_agent_file="$SCRIPT_DIR/../agents/${agent_name}.md"
    [[ -f "$core_agent_file" ]]
    return $?
  fi

  # Check optional agents in user directory
  local agent_dir=$(get_agent_dir "$cli")
  local optional_agent_file="$agent_dir/${agent_name}.md"
  [[ -f "$optional_agent_file" ]]
}

# Validate that all agents in a workflow exist
# Args: $1=workflow_file
validate_workflow_agents() {
  local workflow_file=$1

  if [[ ! -f "$workflow_file" ]]; then
    echo "ERROR: Workflow file not found: $workflow_file" >&2
    exit 1
  fi

  # Check if yq is installed
  if ! command -v yq &> /dev/null; then
    echo "ERROR: yq is required for workflow parsing" >&2
    echo "Install: brew install yq" >&2
    exit 1
  fi

  # Read phases from workflow
  local phases
  phases=$(yq '.phases[]' "$workflow_file" 2>/dev/null || echo "")

  if [[ -z "$phases" ]]; then
    echo "ERROR: No phases found in workflow: $workflow_file" >&2
    exit 1
  fi

  # Validate each phase's agent exists
  local missing_agents=()
  while IFS= read -r phase_agent; do
    if ! agent_exists "$phase_agent"; then
      missing_agents+=("$phase_agent")
    fi
  done <<< "$phases"

  if [[ ${#missing_agents[@]} -gt 0 ]]; then
    echo "ERROR: Missing agents in workflow: $workflow_file" >&2
    echo "Missing: ${missing_agents[*]}" >&2
    echo "" >&2
    echo "Available agents:" >&2
    list_all_agents | sed 's/^/  - /' >&2
    exit 1
  fi

  return 0
}

# Copy optional agent from user directory to working directory
# This allows workflows to use both core and optional agents seamlessly
# Args: $1=agent_name
prepare_optional_agent() {
  local agent_name=$1
  local cli=$(detect_cli)

  # Skip if it's a core agent
  if [[ " ${CORE_AGENTS[@]} " =~ " ${agent_name} " ]]; then
    return 0
  fi

  local agent_dir=$(get_agent_dir "$cli")
  local source_file="$agent_dir/${agent_name}.md"
  local dest_file="$SCRIPT_DIR/../agents/${agent_name}.md"

  if [[ -f "$source_file" ]]; then
    cp "$source_file" "$dest_file"
  else
    echo "ERROR: Optional agent not found: $agent_name" >&2
    exit 1
  fi
}

# Main execution if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Core Agents:"
  printf '  - %s\n' "${CORE_AGENTS[@]}"

  echo ""
  echo "Optional Agents:"
  discover_optional_agents | while read -r agent; do
    echo "  - $agent"
  done

  echo ""
  echo "Total Available: $(list_all_agents | wc -l)"
fi
