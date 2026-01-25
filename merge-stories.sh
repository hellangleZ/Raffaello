#!/usr/bin/env bash
# Merge Stories - Automatically merge story branches back to main
# Handles conflicts with smart resolution strategy

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
MAIN_BRANCH=${MAIN_BRANCH:-main}

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

# Merge a single branch
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
    # Delete the branch
    git branch -d "$branch" 2>/dev/null || true
    return 0
  fi

  # Fast-forward failed, try regular merge
  log_info "Fast-forward not possible, attempting regular merge..."

  if git merge --no-ff -m "Merge $branch into $MAIN_BRANCH" "$branch" 2>/dev/null; then
    log_success "Merge succeeded for $branch"
    # Delete the branch
    git branch -d "$branch" 2>/dev/null || true
    return 0
  fi

  # Merge failed, likely due to conflicts
  log_warn "Merge conflict detected in $branch"

  # Check if we're in a merge state
  if git rev-parse --git-dir > /dev/null 2>&1 && [ -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]; then
    # Get conflicted files
    local conflicted_files
    conflicted_files=$(git diff --name-only --diff-filter=U)

    if [[ -z "$conflicted_files" ]]; then
      # No conflicts, just commit
      git commit --no-edit 2>/dev/null || true
      log_success "Merge completed for $branch"
      git branch -d "$branch" 2>/dev/null || true
      return 0
    fi

    # Handle each conflicted file
    log_warn "Conflicted files:"
    echo "$conflicted_files"

    # For Phase 2, use simple strategy: abort and warn
    log_error "Automatic conflict resolution not yet implemented"
    log_error "Please resolve conflicts manually:"
    echo "$conflicted_files" | while read -r file; do
      echo "  - $file"
    done

    # Abort the merge
    git merge --abort 2>/dev/null || true

    return 1
  fi

  return 1
}

# Main merge process
main() {
  log_info "Starting merge process..."

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
    log_warn "Please resolve conflicts manually and re-run merge-stories.sh"
    return 1
  else
    log_success "All branches merged successfully!"
    return 0
  fi
}

# Run main
main
