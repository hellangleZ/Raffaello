#!/usr/bin/env bash
# Dependency Analyzer - Analyzes story dependencies and creates execution plan
# Builds a DAG and identifies parallelizable stories
# Compatible with bash 3.2+
# Optimized to minimize jq calls

set -euo pipefail

# Input: PRD file path
PRD_FILE=${1:-}

if [[ -z "$PRD_FILE" ]]; then
  echo "ERROR: PRD file required"
  echo "Usage: $0 <prd_file>"
  exit 1
fi

if [[ ! -f "$PRD_FILE" ]]; then
  echo "ERROR: PRD file not found: $PRD_FILE"
  exit 1
fi

# Temporary directory for tracking state
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

COMPLETED_FILE="$TMP_DIR/completed"
IN_BATCH_FILE="$TMP_DIR/in_batch"
DEPS_CACHE_FILE="$TMP_DIR/deps_cache"

# Cache all stories data once (optimization)
ALL_STORIES_DATA=$(jq -c '.userStories[]' "$PRD_FILE")

# Get all incomplete stories (optimized)
get_incomplete_stories() {
  echo "$ALL_STORIES_DATA" | jq -r 'select(.passes == false) | .id'
}

# Get dependencies for a story (cached)
get_story_dependencies() {
  local story_id=$1

  # Check cache first
  if [[ -f "$DEPS_CACHE_FILE" ]]; then
    local cached
    cached=$(grep "^${story_id}:" "$DEPS_CACHE_FILE" 2>/dev/null || echo "")
    if [[ -n "$cached" ]]; then
      echo "${cached#*:}"
      return 0
    fi
  fi

  # Get from data and cache it
  local deps
  deps=$(echo "$ALL_STORIES_DATA" | jq -r "select(.id == \"$story_id\") | .dependencies[]?" 2>/dev/null || echo "")
  echo "${story_id}:${deps}" >> "$DEPS_CACHE_FILE"
  echo "$deps"
}

# Mark a story as completed
mark_completed() {
  local story=$1
  echo "$story" >> "$COMPLETED_FILE"
}

# Check if story is completed
is_completed() {
  local story=$1
  [[ -f "$COMPLETED_FILE" ]] && grep -q "^${story}$" "$COMPLETED_FILE" 2>/dev/null
}

# Mark a story as in batch
mark_in_batch() {
  local story=$1
  echo "$story" >> "$IN_BATCH_FILE"
}

# Check if story is in a batch
is_in_batch() {
  local story=$1
  [[ -f "$IN_BATCH_FILE" ]] && grep -q "^${story}$" "$IN_BATCH_FILE" 2>/dev/null
}

# Build dependency graph and create execution batches
build_execution_plan() {
  local incomplete_stories
  incomplete_stories=$(get_incomplete_stories)

  if [[ -z "$incomplete_stories" ]]; then
    echo '{"batches":[],"unassigned":[]}'
    return
  fi

  # Mark already completed stories (optimized - single jq call)
  echo "$ALL_STORIES_DATA" | jq -r 'select(.passes == true) | .id' | while IFS= read -r story; do
    mark_completed "$story"
  done

  local batches='[]'

  # Keep building batches until all stories are assigned
  while true; do
    local current_batch='[]'
    local found_any=false

    # Find stories ready for execution (all dependencies met)
    for story in $incomplete_stories; do
      # Skip if already in a batch
      if is_in_batch "$story"; then
        continue
      fi

      # Check if all dependencies are met
      local deps
      deps=$(get_story_dependencies "$story")

      local deps_met=true
      if [[ -n "$deps" ]]; then
        for dep in $deps; do
          # Dependency must be completed
          if ! is_completed "$dep"; then
            deps_met=false
            break
          fi
        done
      fi

      # If dependencies met, add to current batch
      if $deps_met; then
        current_batch=$(echo "$current_batch" | jq ". += [\"$story\"]")
        mark_in_batch "$story"
        found_any=true
      fi
    done

    # If no stories found for this batch, we're done or have circular deps
    if ! $found_any; then
      break
    fi

    # Add this batch to batches
    batches=$(echo "$batches" | jq ". += [$current_batch]")

    # Mark stories in this batch as completed for next iteration
    while IFS= read -r story; do
      mark_completed "$story"
    done < <(echo "$current_batch" | jq -r '.[]')
  done

  # Check for unassigned stories (circular dependencies)
  local unassigned='[]'
  for story in $incomplete_stories; do
    if ! is_in_batch "$story"; then
      unassigned=$(echo "$unassigned" | jq ". += [\"$story\"]")
    fi
  done

  # Build final result
  local result
  result=$(jq -n \
    --argjson batches "$batches" \
    --argjson unassigned "$unassigned" \
    '{batches: $batches, unassigned: $unassigned}')

  echo "$result"
}

# Detect circular dependencies
detect_circular_dependencies() {
  local plan=$1
  local unassigned
  unassigned=$(echo "$plan" | jq -r '.unassigned[]?' 2>/dev/null || echo "")

  if [[ -n "$unassigned" ]]; then
    echo "ERROR: Circular dependencies detected or unresolvable dependencies:" >&2
    echo "$unassigned" | while read -r story; do
      echo "  - $story" >&2
    done
    return 1
  fi

  return 0
}

# Main execution
main() {
  # Build execution plan
  local plan
  plan=$(build_execution_plan)

  # Check for circular dependencies
  if ! detect_circular_dependencies "$plan"; then
    exit 1
  fi

  # Output the plan as JSON
  echo "$plan"
}

# Run main
main
