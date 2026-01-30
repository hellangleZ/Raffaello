#!/usr/bin/env bash
# Workflow Parser - Parse and validate workflow YAML configurations
# Provides utilities for loading workflows and extracting phase information

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOWS_DIR="${WORKFLOWS_DIR:-$SCRIPT_DIR/../workflows}"

# Source CLI detection for agent validation
source "$SCRIPT_DIR/detect-cli.sh"
source "$SCRIPT_DIR/load-agents.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_error() {
  echo -e "${RED}[WORKFLOW-PARSER]${NC} $*" >&2
}

log_warn() {
  echo -e "${YELLOW}[WORKFLOW-PARSER]${NC} $*" >&2
}

log_info() {
  echo -e "${BLUE}[WORKFLOW-PARSER]${NC} $*" >&2
}

# Check if yq is available
check_yq() {
  if ! command -v yq &> /dev/null; then
    log_error "yq is required but not installed"
    echo "Install: brew install yq" >&2
    exit 1
  fi
}

# Get workflow file path
get_workflow_file() {
  local workflow_name=$1
  echo "$WORKFLOWS_DIR/${workflow_name}.yaml"
}

# Check if workflow exists
workflow_exists() {
  local workflow_name=$1
  local workflow_file=$(get_workflow_file "$workflow_name")
  [[ -f "$workflow_file" ]]
}

# List all available workflows
list_workflows() {
  if [[ ! -d "$WORKFLOWS_DIR" ]]; then
    return
  fi

  find "$WORKFLOWS_DIR" -maxdepth 1 -name "*.yaml" -type f | while read -r file; do
    basename "$file" .yaml
  done
}

# Get workflow name
get_workflow_name() {
  local workflow_file=$1
  yq -r '.name' "$workflow_file"
}

# Get workflow description
get_workflow_description() {
  local workflow_file=$1
  yq -r '.description // ""' "$workflow_file"
}

# Get workflow phases as array
get_workflow_phases() {
  local workflow_file=$1
  yq -r '.phases[]' "$workflow_file"
}

# Get retry policy for a specific phase
get_phase_max_attempts() {
  local workflow_file=$1
  local phase=$2
  yq -r ".retry_policy.$phase.max_attempts // 1" "$workflow_file"
}

# Parse full workflow and export to environment
# Sets: WORKFLOW_NAME, WORKFLOW_DESCRIPTION, WORKFLOW_PHASES (array)
# Also sets RETRY_POLICY_{PHASE} for each phase
parse_workflow() {
  local workflow_name=$1
  local workflow_file=$(get_workflow_file "$workflow_name")

  if [[ ! -f "$workflow_file" ]]; then
    log_error "Workflow file not found: $workflow_file"
    return 1
  fi

  # Export basic info
  export WORKFLOW_NAME=$(get_workflow_name "$workflow_file")
  export WORKFLOW_DESCRIPTION=$(get_workflow_description "$workflow_file")

  # Export phases as array
  WORKFLOW_PHASES=()
  while IFS= read -r phase; do
    WORKFLOW_PHASES+=("$phase")
  done < <(get_workflow_phases "$workflow_file")

  # Export retry policies (using dynamic variable names)
  for phase in "${WORKFLOW_PHASES[@]}"; do
    local max_attempts=$(get_phase_max_attempts "$workflow_file" "$phase")
    # Create dynamic variable: RETRY_POLICY_planner=1, etc.
    local var_name="RETRY_POLICY_${phase}"
    export "${var_name}=${max_attempts}"
  done

  log_info "Parsed workflow: $WORKFLOW_NAME (${#WORKFLOW_PHASES[@]} phases)"
}

# Get retry policy for a phase (from environment)
get_retry_policy() {
  local phase=$1
  local var_name="RETRY_POLICY_${phase}"
  echo "${!var_name:-1}"
}

# Validate workflow configuration
validate_workflow() {
  local workflow_name=$1
  local workflow_file=$(get_workflow_file "$workflow_name")

  if [[ ! -f "$workflow_file" ]]; then
    log_error "Workflow file not found: $workflow_file"
    return 1
  fi

  log_info "Validating workflow: $workflow_name"

  # Check required fields
  local name=$(yq -r '.name' "$workflow_file")
  if [[ -z "$name" || "$name" == "null" ]]; then
    log_error "Workflow missing 'name' field"
    return 1
  fi

  # Check phases exist
  local phases=$(yq '.phases' "$workflow_file")
  if [[ -z "$phases" || "$phases" == "null" ]]; then
    log_error "Workflow missing 'phases' field"
    return 1
  fi

  # Check phases is an array
  # Note: yq implementations differ (mikefarah/yq uses "!!seq"; python yq uses "array").
  local phases_type
  phases_type=$(yq -r '.phases | type' "$workflow_file" 2>/dev/null || echo "")
  if [[ "$phases_type" != "array" && "$phases_type" != "!!seq" ]]; then
    log_error "Workflow 'phases' must be an array"
    return 1
  fi

  # Check at least one phase
  local phase_count=$(yq '.phases | length' "$workflow_file")
  if [[ "$phase_count" -eq 0 ]]; then
    log_error "Workflow must have at least one phase"
    return 1
  fi

  # Validate each phase agent exists
  local cli=$(detect_cli)
  while IFS= read -r phase; do
    if ! agent_exists "$phase"; then
      log_error "Agent not found for phase: $phase"
      log_error "Available agents: $(list_all_agents | tr '\n' ' ')"
      return 1
    fi
  done < <(get_workflow_phases "$workflow_file")

  # Check retry_policy format (optional)
  if yq -e '.retry_policy' "$workflow_file" > /dev/null 2>&1; then
    # Validate retry_policy is an object
    local retry_type
    retry_type=$(yq -r '.retry_policy | type' "$workflow_file" 2>/dev/null || echo "")
    if [[ "$retry_type" != "object" && "$retry_type" != "!!map" ]]; then
      log_error "Workflow 'retry_policy' must be an object"
      return 1
    fi

    # Validate max_attempts are positive integers
    while IFS= read -r phase; do
      if yq -e ".retry_policy.$phase" "$workflow_file" > /dev/null 2>&1; then
        local max_attempts=$(yq -r ".retry_policy.$phase.max_attempts" "$workflow_file")
        if [[ "$max_attempts" != "null" ]]; then
          if ! [[ "$max_attempts" =~ ^[1-9][0-9]*$ ]]; then
            log_error "Invalid max_attempts for $phase: $max_attempts (must be positive integer)"
            return 1
          fi
        fi
      fi
    done < <(get_workflow_phases "$workflow_file")
  fi

  log_info "Workflow validation passed: $workflow_name"
  return 0
}

# Validate all workflows in workflows directory
validate_all_workflows() {
  check_yq

  local workflows
  workflows=$(list_workflows)

  if [[ -z "$workflows" ]]; then
    log_warn "No workflows found in $WORKFLOWS_DIR"
    return 0
  fi

  local total=0
  local passed=0
  local failed=0

  for workflow in $workflows; do
    ((total++))
    if validate_workflow "$workflow"; then
      ((passed++))
    else
      ((failed++))
    fi
  done

  echo ""
  echo "Validation Summary:"
  echo "  Total: $total"
  echo "  Passed: $passed"
  echo "  Failed: $failed"

  [[ $failed -eq 0 ]]
}

# Print workflow summary
print_workflow_summary() {
  local workflow_name=$1
  local workflow_file=$(get_workflow_file "$workflow_name")

  if [[ ! -f "$workflow_file" ]]; then
    log_error "Workflow file not found: $workflow_file"
    return 1
  fi

  echo "Workflow: $(get_workflow_name "$workflow_file")"
  echo "Description: $(get_workflow_description "$workflow_file")"
  echo ""
  echo "Phases:"
  local phase_num=1
  while IFS= read -r phase; do
    local max_attempts=$(get_phase_max_attempts "$workflow_file" "$phase")
    echo "  $phase_num. $phase (max attempts: $max_attempts)"
    ((phase_num++))
  done < <(get_workflow_phases "$workflow_file")
}

# Main CLI interface
main() {
  check_yq

  local command=${1:-}
  shift || true

  case "$command" in
    list)
      list_workflows
      ;;
    validate)
      if [[ $# -eq 0 ]]; then
        validate_all_workflows
      else
        validate_workflow "$1"
      fi
      ;;
    show)
      if [[ $# -eq 0 ]]; then
        log_error "Usage: $0 show <workflow_name>"
        exit 1
      fi
      print_workflow_summary "$1"
      ;;
    parse)
      if [[ $# -eq 0 ]]; then
        log_error "Usage: $0 parse <workflow_name>"
        exit 1
      fi
      parse_workflow "$1"
      # Print exported variables for debugging
      echo "WORKFLOW_NAME=$WORKFLOW_NAME"
      echo "WORKFLOW_DESCRIPTION=$WORKFLOW_DESCRIPTION"
      echo "WORKFLOW_PHASES=(${WORKFLOW_PHASES[*]})"
      for phase in "${WORKFLOW_PHASES[@]}"; do
        echo "RETRY_POLICY_$phase=$(get_retry_policy "$phase")"
      done
      ;;
    *)
      echo "Usage: $0 <command> [args]"
      echo ""
      echo "Commands:"
      echo "  list                    List all available workflows"
      echo "  validate [workflow]     Validate workflow(s)"
      echo "  show <workflow>         Show workflow summary"
      echo "  parse <workflow>        Parse and export workflow to environment"
      exit 1
      ;;
  esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
