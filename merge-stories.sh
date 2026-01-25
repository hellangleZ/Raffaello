#!/usr/bin/env bash
# Merge Stories - Automatically merge story branches with intelligent conflict resolution
# Handles conflicts with smart three-tier resolution strategy

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/detect-cli.sh"
source "$SCRIPT_DIR/lib/agent-api.sh"
source "$SCRIPT_DIR/lib/conflict-analyzer.sh"

# Configuration
MAIN_BRANCH=${MAIN_BRANCH:-main}
COMM_DIR="${AGENT_COMM_DIR:-/tmp/ralph-parallel}/merge"

# Create communication directory
mkdir -p "$COMM_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
  echo -e "${BLUE}[MERGE]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[MERGE]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[MERGE]${NC} $*"
}

log_error() {
  echo -e "${RED}[MERGE]${NC} $*"
}

# Get all story branches
get_story_branches() {
  git branch | grep 'story-' | sed 's/^\* //' | sed 's/^  //'
}

# Auto-merge simple conflicts (LOW severity)
auto_merge_simple_conflicts() {
  local conflicted_files
  conflicted_files=$(git diff --name-only --diff-filter=U)

  if [[ -z "$conflicted_files" ]]; then
    return 0
  fi

  local resolved=0
  local failed=0

  while IFS= read -r file; do
    if [[ -z "$file" ]]; then
      continue
    fi

    local severity=$(analyze_conflict_severity "$file")

    if [[ "$severity" == "LOW" ]]; then
      log_info "Auto-merging LOW severity conflict: $file"

      # For LOW severity, use a simple strategy: prefer ours (main branch)
      # This is safe for things like whitespace, formatting, etc.
      if git checkout --ours "$file" 2>/dev/null && git add "$file"; then
        log_success "  Auto-merged: $file (kept main branch version)"
        ((resolved++))
      else
        log_warn "  Failed to auto-merge: $file"
        ((failed++))
      fi
    fi
  done <<< "$conflicted_files"

  log_info "Auto-merge results: $resolved resolved, $failed failed"
  return $failed
}

# Use AI to resolve medium severity conflicts
ai_resolve_conflicts() {
  local conflicted_files
  conflicted_files=$(git diff --name-only --diff-filter=U)

  if [[ -z "$conflicted_files" ]]; then
    return 0
  fi

  # Check if there are MEDIUM severity conflicts
  local has_medium=false
  while IFS= read -r file; do
    if [[ -z "$file" ]]; then
      continue
    fi

    local severity=$(analyze_conflict_severity "$file")
    if [[ "$severity" == "MEDIUM" ]]; then
      has_medium=true
      break
    fi
  done <<< "$conflicted_files"

  if ! $has_medium; then
    return 0
  fi

  log_info "Invoking AI conflict resolver for MEDIUM severity conflicts..."

  # Prepare conflict information
  local conflict_info
  conflict_info=$(analyze_all_conflicts 2>&1)

  # Spawn conflict-resolver agent
  local cli=$(detect_cli)
  local task_message="Resolve merge conflicts in the following files:

$conflicted_files

Conflict Analysis:
$conflict_info

Repository root: $(pwd)
Communication directory: $COMM_DIR

Instructions:
1. Analyze each conflicted file
2. Resolve MEDIUM severity conflicts intelligently
3. Stage resolved files with 'git add'
4. Create success marker if all resolved
5. Create escalation report if manual review needed
"

  local agent_id
  agent_id=$(spawn_agent "conflict-resolver" "$task_message" "merge")

  log_info "Waiting for conflict resolver agent..."
  wait_for_agents "$agent_id"

  # Check if resolution succeeded
  if check_agent_success "merge" "conflict-resolver"; then
    log_success "AI conflict resolver completed successfully"
    close_agent "$agent_id" 2>/dev/null || true
    return 0
  else
    log_warn "AI conflict resolver did not complete successfully"

    # Check for escalation report
    if [[ -f "$COMM_DIR/conflict-escalation.md" ]]; then
      log_warn "Conflicts require manual review:"
      cat "$COMM_DIR/conflict-escalation.md"
    fi

    close_agent "$agent_id" 2>/dev/null || true
    return 1
  fi
}

# Merge a single branch with intelligent conflict resolution
merge_branch() {
  local branch=$1

  log_info "Merging branch: $branch"

  # Switch to main branch
  git checkout "$MAIN_BRANCH" 2>/dev/null || {
    log_error "Failed to checkout $MAIN_BRANCH"
    return 1
  }

  # Try fast-forward merge first
  if git merge --ff-only "$branch" 2>/dev/null; then
    log_success "Fast-forward merge succeeded for $branch"
    git branch -d "$branch" 2>/dev/null || true
    return 0
  fi

  # Fast-forward failed, try regular merge
  log_info "Fast-forward not possible, attempting regular merge..."

  if git merge --no-ff -m "Merge $branch into $MAIN_BRANCH" "$branch" 2>/dev/null; then
    log_success "Merge succeeded for $branch"
    git branch -d "$branch" 2>/dev/null || true
    return 0
  fi

  # Merge failed, analyze conflicts
  log_warn "Merge conflict detected in $branch"

  # Get conflict analysis
  local analysis_result
  analyze_all_conflicts 2>&1 || analysis_result=$?

  # Check severity
  if [[ ${analysis_result:-0} -eq 0 ]]; then
    # Only LOW severity conflicts - auto-merge
    log_info "Only LOW severity conflicts detected, auto-merging..."

    if auto_merge_simple_conflicts; then
      # Check if all resolved
      local remaining
      remaining=$(git diff --name-only --diff-filter=U | wc -l | tr -d ' ')

      if [[ $remaining -eq 0 ]]; then
        git commit --no-edit 2>/dev/null || true
        log_success "All conflicts auto-merged for $branch"
        git branch -d "$branch" 2>/dev/null || true
        return 0
      fi
    fi
  fi

  if [[ ${analysis_result:-0} -eq 1 ]]; then
    # MEDIUM severity conflicts - use AI
    log_info "MEDIUM severity conflicts detected, using AI resolver..."

    if ai_resolve_conflicts; then
      # Check if all resolved
      local remaining
      remaining=$(git diff --name-only --diff-filter=U | wc -l | tr -d ' ')

      if [[ $remaining -eq 0 ]]; then
        git commit --no-edit 2>/dev/null || true
        log_success "All conflicts AI-resolved for $branch"
        git branch -d "$branch" 2>/dev/null || true
        return 0
      fi
    fi
  fi

  # HIGH severity or AI failed - manual review required
  log_error "Manual review required for $branch"
  log_error "Conflicted files:"
  git diff --name-only --diff-filter=U | while read -r f; do
    local severity=$(analyze_conflict_severity "$f")
    echo "  [$severity] $f"
  done

  # Abort the merge
  git merge --abort 2>/dev/null || true

  return 1
}

# Main merge process
main() {
  log_info "Starting intelligent merge process..."

  # Get all story branches
  local branches
  branches=$(get_story_branches)

  if [[ -z "$branches" ]]; then
    log_info "No story branches to merge"
    return 0
  fi

  local total_count
  total_count=$(echo "$branches" | wc -l | tr -d ' ')
  log_info "Found $total_count story branches to merge"

  # Track success/failure
  local success_count=0
  local failed_count=0
  local failed_branches=()

  # Merge each branch
  for branch in $branches; do
    echo ""
    if merge_branch "$branch"; then
      ((success_count++))
    else
      ((failed_count++))
      failed_branches+=("$branch")
    fi
  done

  echo ""
  log_info "=== Merge Summary ==="
  log_success "Successfully merged: $success_count"

  if [[ $failed_count -gt 0 ]]; then
    log_error "Failed to merge: $failed_count"
    echo "Failed branches:"
    for branch in "${failed_branches[@]}"; do
      echo "  - $branch"
    done
    echo ""
    log_warn "Please resolve conflicts manually:"
    echo "  1. git checkout $MAIN_BRANCH"
    echo "  2. git merge <branch>"
    echo "  3. Resolve conflicts"
    echo "  4. git add <files>"
    echo "  5. git commit"
    return 1
  else
    log_success "All branches merged successfully!"
    return 0
  fi
}

# Run main
main
