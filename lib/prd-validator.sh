#!/usr/bin/env bash
# PRD Validator - Validates PRD file structure and content
# Checks for required fields, circular dependencies, and invalid workflows

set -euo pipefail

# Validate PRD file structure and content
# Args: $1=prd_file_path
# Returns: 0 on success, 1 on error
validate_prd() {
  local prd_file=$1

  if [[ ! -f "$prd_file" ]]; then
    echo "ERROR: PRD file not found: $prd_file" >&2
    return 1
  fi

  # Check if valid JSON
  if ! jq empty "$prd_file" 2>/dev/null; then
    echo "ERROR: PRD file is not valid JSON" >&2
    return 1
  fi

  # Check required top-level fields
  # Support both "project" and "projectName" for compatibility
  if ! jq -e '.projectName // .project' "$prd_file" > /dev/null 2>&1; then
    echo "ERROR: Missing required field: projectName or project" >&2
    return 1
  fi

  if ! jq -e '.branchName' "$prd_file" > /dev/null 2>&1; then
    echo "ERROR: Missing required field: branchName" >&2
    return 1
  fi

  if ! jq -e '.userStories' "$prd_file" > /dev/null 2>&1; then
    echo "ERROR: Missing required field: userStories" >&2
    return 1
  fi

  # Check userStories is an array
  if [[ $(jq -r '.userStories | type' "$prd_file") != "array" ]]; then
    echo "ERROR: userStories must be an array" >&2
    return 1
  fi

  # Validate each story
  local story_count
  story_count=$(jq '.userStories | length' "$prd_file")

  if [[ $story_count -eq 0 ]]; then
    echo "ERROR: PRD must contain at least one user story" >&2
    return 1
  fi

  local idx=0
  while [[ $idx -lt $story_count ]]; do
    # Check required story fields
    local story_id
    story_id=$(jq -r ".userStories[$idx].id // \"\"" "$prd_file")

    if [[ -z "$story_id" ]]; then
      echo "ERROR: Story at index $idx is missing 'id' field" >&2
      return 1
    fi

    # Check for other required fields
    local story_title
    story_title=$(jq -r ".userStories[$idx].title // \"\"" "$prd_file")
    if [[ -z "$story_title" ]]; then
      echo "ERROR: Story $story_id is missing 'title' field" >&2
      return 1
    fi

    local story_desc
    story_desc=$(jq -r ".userStories[$idx].description // \"\"" "$prd_file")
    if [[ -z "$story_desc" ]]; then
      echo "ERROR: Story $story_id is missing 'description' field" >&2
      return 1
    fi

    # Validate passes field exists and is boolean
    if ! jq -e ".userStories[$idx].passes | type == \"boolean\"" "$prd_file" > /dev/null; then
      echo "ERROR: Story $story_id is missing 'passes' field or it's not a boolean" >&2
      return 1
    fi

    # Validate dependencies is array (if present)
    if jq -e ".userStories[$idx].dependencies" "$prd_file" > /dev/null 2>&1; then
      if [[ $(jq -r ".userStories[$idx].dependencies | type" "$prd_file") != "array" ]]; then
        echo "ERROR: Story $story_id 'dependencies' field must be an array" >&2
        return 1
      fi

      # Check dependencies reference valid stories
      local deps
      deps=$(jq -r ".userStories[$idx].dependencies[]?" "$prd_file")
      for dep in $deps; do
        if ! jq -e ".userStories[] | select(.id == \"$dep\")" "$prd_file" > /dev/null; then
          echo "ERROR: Story $story_id has invalid dependency: $dep (story not found)" >&2
          return 1
        fi
      done
    fi

    # Validate workflow exists (if specified)
    local workflow
    workflow=$(jq -r ".userStories[$idx].workflow // \"standard\"" "$prd_file")
    if [[ -n "$workflow" && "$workflow" != "null" ]]; then
      local workflow_file="workflows/${workflow}.yaml"
      if [[ ! -f "$workflow_file" ]]; then
        echo "ERROR: Story $story_id references non-existent workflow: $workflow" >&2
        echo "  Expected file: $workflow_file" >&2
        return 1
      fi
    fi

    ((idx++))
  done

  # Check for duplicate story IDs
  local unique_ids
  unique_ids=$(jq -r '.userStories[].id' "$prd_file" | sort | uniq | wc -l | tr -d ' ')
  if [[ $unique_ids -ne $story_count ]]; then
    echo "ERROR: Duplicate story IDs detected" >&2
    jq -r '.userStories[].id' "$prd_file" | sort | uniq -d | while read -r dup_id; do
      echo "  Duplicate: $dup_id" >&2
    done
    return 1
  fi

  # Check for circular dependencies (basic check)
  if ! check_circular_dependencies "$prd_file"; then
    return 1
  fi

  echo "✓ PRD validation passed"
  return 0
}

# Check for circular dependencies
check_circular_dependencies() {
  local prd_file=$1
  local temp_dir
  temp_dir=$(mktemp -d)

  local visited_file="$temp_dir/visited"
  local rec_stack_file="$temp_dir/rec_stack"

  # DFS to detect cycles
  local all_stories
  all_stories=$(jq -r '.userStories[].id' "$prd_file")

  local result=0
  for story in $all_stories; do
    if ! has_cycle_dfs "$story" "$prd_file" "$visited_file" "$rec_stack_file"; then
      result=1
      break
    fi
  done

  # Cleanup
  rm -rf "$temp_dir"
  return $result
}

# DFS helper for cycle detection
has_cycle_dfs() {
  local story=$1
  local prd_file=$2
  local visited_file=$3
  local rec_stack_file=$4

  # Check if already visited
  if grep -q "^${story}$" "$visited_file" 2>/dev/null; then
    return 0
  fi

  # Mark as visited and add to recursion stack
  echo "$story" >> "$visited_file"
  echo "$story" >> "$rec_stack_file"

  # Get dependencies
  local deps
  deps=$(jq -r ".userStories[] | select(.id == \"$story\") | .dependencies[]?" "$prd_file")

  for dep in $deps; do
    # If dependency is in recursion stack, we have a cycle
    if grep -q "^${dep}$" "$rec_stack_file" 2>/dev/null; then
      echo "ERROR: Circular dependency detected: $story -> $dep" >&2
      return 1
    fi

    # Recurse
    if ! has_cycle_dfs "$dep" "$prd_file" "$visited_file" "$rec_stack_file"; then
      return 1
    fi
  done

  # Remove from recursion stack
  grep -v "^${story}$" "$rec_stack_file" > "$rec_stack_file.tmp" 2>/dev/null || true
  mv "$rec_stack_file.tmp" "$rec_stack_file" 2>/dev/null || true

  return 0
}

# Main execution if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <prd_file>"
    exit 1
  fi

  if validate_prd "$1"; then
    exit 0
  else
    exit 1
  fi
fi
