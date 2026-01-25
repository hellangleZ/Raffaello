#!/usr/bin/env bash
# Ralph Parallel - Main Execution Loop
# Orchestrates parallel execution of multiple user stories

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/detect-cli.sh"
source "$SCRIPT_DIR/lib/agent-api.sh"

# Configuration
MAX_PARALLEL_STORIES=${MAX_PARALLEL_STORIES:-3}
PRD_FILE="${PRD_FILE:-$SCRIPT_DIR/prd.json}"
PROGRESS_FILE="${PROGRESS_FILE:-$SCRIPT_DIR/progress.txt}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

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
  get_story "$story_id" | jq -r '.title'
}

# Get story workflow (default to 'standard')
get_story_workflow() {
  local story_id=$1
  get_story "$story_id" | jq -r '.workflow // "standard"'
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

  # Create story branch
  local branch_name="story-$story_id"
  git checkout -b "$branch_name" 2>/dev/null || git checkout "$branch_name"

  # Execute orchestrator for this story
  if "$SCRIPT_DIR/orchestrator.sh" "$story_id"; then
    log_success "Story $story_id completed successfully"
    return 0
  else
    log_error "Story $story_id failed"
    return 1
  fi
}

# Main execution loop
main() {
  log_info "=== Ralph Parallel - Starting Execution ==="
  echo ""

  # Check prerequisites
  check_prerequisites
  echo ""

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
  log_info "Found $story_count incomplete stories"
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

  # Execute each batch
  local batch_idx=0
  while [[ $batch_idx -lt $batches ]]; do
    local batch_stories
    batch_stories=$(echo "$execution_plan" | jq -r ".batches[$batch_idx][]")

    log_info "=== Batch $((batch_idx + 1)) / $batches ==="

    # Track background processes
    local pids=()
    local story_pids=()

    # Execute stories in this batch (parallel, up to MAX_PARALLEL_STORIES at a time)
    local concurrent=0
    for story_id in $batch_stories; do
      local story_title
      story_title=$(get_story_title "$story_id")

      # Start story execution in background
      execute_story "$story_id" "$story_title" &
      local pid=$!
      pids+=("$pid")
      story_pids["$pid"]="$story_id"

      ((concurrent++))

      # If we've reached max parallel, wait for one to finish
      if [[ $concurrent -ge $MAX_PARALLEL_STORIES ]]; then
        wait -n "${pids[@]}" || true
        ((concurrent--))
      fi
    done

    # Wait for all stories in this batch to complete
    log_info "Waiting for batch $((batch_idx + 1)) to complete..."
    for pid in "${pids[@]}"; do
      if wait "$pid"; then
        log_success "Story ${story_pids[$pid]} finished successfully"
      else
        log_error "Story ${story_pids[$pid]} failed"
        # Continue with other stories even if one fails
      fi
    done

    echo ""
    ((batch_idx++))
  done

  # Merge all story branches
  log_info "=== Merging Story Branches ==="
  if "$SCRIPT_DIR/merge-stories.sh"; then
    log_success "All stories merged successfully"
  else
    log_warn "Some merge conflicts require manual resolution"
  fi

  echo ""
  log_success "=== Ralph Parallel - Execution Complete ==="
}

# Run main
main "$@"
