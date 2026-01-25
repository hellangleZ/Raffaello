#!/usr/bin/env bash
# Orchestrator - Manages execution phases for a single story
# Loads workflow configuration and executes each phase with appropriate agents

set -euo pipefail

# Project root directory (inherited from ralph.sh via SCRIPT_DIR)
# Do NOT redefine SCRIPT_DIR here to avoid path collision
PROJECT_ROOT="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Source libraries
source "$PROJECT_ROOT/lib/detect-cli.sh"
source "$PROJECT_ROOT/lib/agent-api.sh"
source "$PROJECT_ROOT/lib/load-agents.sh"

# Configuration
PRD_FILE="${PRD_FILE:-$PROJECT_ROOT/prd.json}"
WORKFLOWS_DIR="$PROJECT_ROOT/workflows"

# Get story ID from argument
STORY_ID=${1:-}

if [[ -z "$STORY_ID" ]]; then
  echo "ERROR: Story ID required"
  echo "Usage: $0 <story_id>"
  exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  echo -e "${BLUE}[ORCHESTRATOR]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[ORCHESTRATOR]${NC} $*"
}

log_error() {
  echo -e "${RED}[ORCHESTRATOR]${NC} $*"
}

# Get story details from PRD
get_story() {
  jq ".userStories[] | select(.id == \"$STORY_ID\")" "$PRD_FILE"
}

# Get story workflow type (default: standard)
get_story_workflow() {
  get_story | jq -r '.workflow // "standard"'
}

# Get story title
get_story_title() {
  get_story | jq -r '.title'
}

# Get story description
get_story_description() {
  get_story | jq -r '.description'
}

# Get story acceptance criteria
get_story_acceptance_criteria() {
  get_story | jq -r '.acceptanceCriteria[]?' 2>/dev/null || echo ""
}

# Update PRD to mark story as passed
update_story_status() {
  local passes=$1

  # Create temporary file
  local tmp_file=$(mktemp)

  # Update the story's passes field
  jq "(.userStories[] | select(.id == \"$STORY_ID\") | .passes) = $passes" "$PRD_FILE" > "$tmp_file"

  # Replace original file
  mv "$tmp_file" "$PRD_FILE"

  log_success "Updated story $STORY_ID: passes = $passes"
}

# Parse workflow YAML
parse_workflow() {
  local workflow_name=$1
  local workflow_file="$WORKFLOWS_DIR/${workflow_name}.yaml"

  if [[ ! -f "$workflow_file" ]]; then
    log_error "Workflow file not found: $workflow_file"
    exit 1
  fi

  # Export workflow data as global variables
  export WORKFLOW_NAME=$(yq '.name' "$workflow_file")

  # Get phases as array
  WORKFLOW_PHASES=()
  while IFS= read -r phase; do
    WORKFLOW_PHASES+=("$phase")
  done < <(yq '.phases[]' "$workflow_file")

  # Get retry policy (use temp file for Bash 3.2 compatibility)
  RETRY_POLICY_FILE=$(mktemp)
  for phase in "${WORKFLOW_PHASES[@]}"; do
    local max_attempts=$(yq ".retry_policy.$phase.max_attempts // 1" "$workflow_file")
    echo "$phase:$max_attempts" >> "$RETRY_POLICY_FILE"
  done
}

# Execute a single phase
execute_phase() {
  local phase=$1

  # Get max_attempts from retry policy file
  local max_attempts=1
  if [[ -f "$RETRY_POLICY_FILE" ]]; then
    max_attempts=$(grep "^$phase:" "$RETRY_POLICY_FILE" | cut -d: -f2)
    max_attempts=${max_attempts:-1}
  fi

  local attempt=1

  log_info "Executing phase: $phase (max attempts: $max_attempts)"

  while [[ $attempt -le $max_attempts ]]; do
    log_info "  Attempt $attempt/$max_attempts"

    # Prepare task message
    local task_message="Execute $phase for story $STORY_ID

Story: $(get_story_title)
Description: $(get_story_description)

Acceptance Criteria:
$(get_story_acceptance_criteria)
"

    # Check if agent exists (may be optional)
    if ! agent_exists "$phase"; then
      log_error "Agent not found: $phase"
      return 1
    fi

    # Prepare optional agent if needed
    prepare_optional_agent "$phase" 2>/dev/null || true

    # Spawn agent
    local cli=$(detect_cli)
    local agent_id
    agent_id=$(spawn_agent "$phase" "$task_message" "$STORY_ID")

    log_info "  Spawned agent: $agent_id"

    # Wait for agent to complete
    wait_for_agents "$agent_id"

    # Check if phase succeeded
    if check_agent_success "$STORY_ID" "$phase"; then
      log_success "  Phase $phase PASSED"
      close_agent "$agent_id" 2>/dev/null || true
      return 0
    else
      log_error "  Phase $phase FAILED (attempt $attempt/$max_attempts)"

      # Get agent output for debugging
      local output
      output=$(get_agent_output "$STORY_ID" "$phase")
      if [[ -n "$output" ]]; then
        echo "  Agent output:"
        echo "$output" | head -n 20
      fi

      close_agent "$agent_id" 2>/dev/null || true
    fi

    ((attempt++))
  done

  log_error "Phase $phase FAILED after $max_attempts attempts"
  return 1
}

# Main orchestrator logic
main() {
  log_info "Starting orchestration for story: $STORY_ID"

  # Get story details
  local story_title
  story_title=$(get_story_title)
  log_info "Story: $story_title"

  # Get workflow type
  local workflow
  workflow=$(get_story_workflow)
  log_info "Workflow: $workflow"

  # Parse workflow configuration
  parse_workflow "$workflow"
  log_info "Workflow has ${#WORKFLOW_PHASES[@]} phases: ${WORKFLOW_PHASES[*]}"

  # Validate workflow agents exist
  if ! validate_workflow_agents "$WORKFLOWS_DIR/${workflow}.yaml" "$(detect_cli)"; then
    log_error "Workflow validation failed"
    exit 1
  fi

  # Execute each phase sequentially
  for phase in "${WORKFLOW_PHASES[@]}"; do
    if ! execute_phase "$phase"; then
      log_error "Orchestration failed at phase: $phase"
      update_story_status "false"
      exit 1
    fi
  done

  # All phases passed - update PRD
  update_story_status "true"

  # Commit the story implementation
  log_info "Committing story implementation..."
  git add -A
  git commit -m "feat: $STORY_ID - $story_title

$(get_story_description)

Workflow: $workflow
Phases: ${WORKFLOW_PHASES[*]}

Co-Authored-By: Claude <noreply@anthropic.com>" || true

  log_success "Story $STORY_ID completed successfully!"

  # Cleanup temp file
  [[ -f "$RETRY_POLICY_FILE" ]] && rm -f "$RETRY_POLICY_FILE"
}

# Run main
main
