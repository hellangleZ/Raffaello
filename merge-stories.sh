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

# Source unified logging
export LOG_PREFIX="MERGE"
source "$SCRIPT_DIR/lib/logging.sh"

# CLI options
USE_AI_MERGE=${USE_AI_MERGE:-false}
MERGE_REPORT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ai)
      USE_AI_MERGE=true
      shift
      ;;
    --report)
      MERGE_REPORT_FILE="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: merge-stories.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --ai              Use Claude Code to resolve conflicts"
      echo "  --report FILE     Output merge report to FILE (default: merge-report.md)"
      echo "  --help, -h        Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Configuration
# Auto-detect main branch: use env var, or detect from git, fallback to 'main'
if [[ -z "${MAIN_BRANCH:-}" ]]; then
  # Try to detect: prefer current branch if it's main/master, else check which exists
  _current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$_current" == "main" || "$_current" == "master" ]]; then
    MAIN_BRANCH="$_current"
  elif git rev-parse --verify main &>/dev/null; then
    MAIN_BRANCH="main"
  elif git rev-parse --verify master &>/dev/null; then
    MAIN_BRANCH="master"
  else
    MAIN_BRANCH="main"  # fallback
  fi
  unset _current
fi
COMM_DIR="${AGENT_COMM_DIR:-/tmp/raffaello}/merge"

# Create communication directory
mkdir -p "$COMM_DIR"

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

  # Check if there are MEDIUM or HIGH severity conflicts
  local has_medium=false
  local has_high=false
  while IFS= read -r file; do
    if [[ -z "$file" ]]; then
      continue
    fi

    local severity=$(analyze_conflict_severity "$file")
    if [[ "$severity" == "MEDIUM" ]]; then
      has_medium=true
    elif [[ "$severity" == "HIGH" ]]; then
      has_high=true
      break  # If we have HIGH, no point using AI
    fi
  done <<< "$conflicted_files"

  # HIGH severity conflicts need manual review, return error
  if $has_high; then
    log_warn "HIGH severity conflicts detected, manual review required"
    return 1
  fi

  # No MEDIUM conflicts, nothing to do
  if ! $has_medium; then
    return 0
  fi

  log_info "Invoking AI conflict resolver for MEDIUM severity conflicts..."

  # Prepare a default escalation report up-front so manual resolution always has context
  # even if the agent fails to run or times out.
  cat >"$COMM_DIR/conflict-escalation.md" <<EOF
# Merge Conflict Escalation Report

## Branch
- Target: $MAIN_BRANCH

## Conflicted Files
$(echo "$conflicted_files" | sed 's/^/- /')

## Recommendations
- Resolve conflicts manually, then run: git add <files> && git commit

EOF

  # Prepare conflict information
  local conflict_info
  conflict_info=$(analyze_all_conflicts 2>&1)

  # Append analysis output to the escalation report for manual resolution.
  if [[ -f "$COMM_DIR/conflict-escalation.md" ]]; then
    {
      echo "## Conflict Analysis"
      echo
      echo '```'
      echo "$conflict_info"
      echo '```'
      echo
    } >>"$COMM_DIR/conflict-escalation.md"
  fi

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
  if ! wait_for_agent "merge" "conflict-resolver" "$agent_id"; then
    log_warn "Conflict resolver did not complete successfully (timeout or early exit)"
  fi

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
      log_warn "Escalation report: $COMM_DIR/conflict-escalation.md"
      # Keep console output short; file contains full context.
      sed -n '1,120p' "$COMM_DIR/conflict-escalation.md" || true
    fi

    close_agent "$agent_id" 2>/dev/null || true
    return 1
  fi
}

# Use Claude Code to resolve conflicts (--ai mode)
# This calls Claude Code directly to intelligently merge conflicted files
claude_code_resolve_conflicts() {
  local branch=$1
  local conflicted_files
  conflicted_files=$(git diff --name-only --diff-filter=U)

  if [[ -z "$conflicted_files" ]]; then
    return 0
  fi

  log_info "Using Claude Code to resolve conflicts..."

  # Prepare conflict details for Claude
  local conflict_details=""
  local file_list=""
  while IFS= read -r file; do
    if [[ -z "$file" ]]; then
      continue
    fi
    local severity=$(analyze_conflict_severity "$file")
    conflict_details+="- [$severity] $file"$'\n'
    file_list+="$file "
  done <<< "$conflicted_files"

  # Build a simpler, more direct prompt for Claude Code
  local prompt="Resolve git merge conflicts in these files: $file_list

Instructions:
1. Read each file with conflict markers (<<<<<<, =======, >>>>>>>)
2. Combine both versions intelligently - keep all functionality from both sides
3. Remove ALL conflict markers
4. Run 'git add <filename>' for each resolved file
5. Verify with 'git status' that no conflicts remain

Do NOT create commits. Just resolve conflicts and stage files."

  local output_file="$COMM_DIR/claude-resolve-${branch//\//-}.log"

  log_info "Spawning Claude Code to resolve conflicts (timeout: 600s)..."

  # Run Claude Code with timeout
  # Use -p for non-interactive print mode
  # Use --dangerously-skip-permissions to allow file edits without prompts
  local timeout_secs=600
  if timeout "$timeout_secs" claude -p --dangerously-skip-permissions "$prompt" > "$output_file" 2>&1; then
    log_success "Claude Code finished processing"
  else
    local exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      log_warn "Claude Code timed out after ${timeout_secs}s"
    else
      log_warn "Claude Code exited with status $exit_code"
    fi
  fi

  # Check if conflicts are resolved
  local remaining
  remaining=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l | tr -d ' ')

  if [[ $remaining -eq 0 ]]; then
    log_success "All conflicts resolved by Claude Code"
    return 0
  else
    log_warn "Some conflicts remain after Claude Code resolution: $remaining files"
    # Show what Claude did
    if [[ -f "$output_file" ]]; then
      log_info "Claude Code output (last 20 lines):"
      tail -20 "$output_file" | sed 's/^/  /'
    fi
    return 1
  fi
}

# Record merge result for report
declare -a MERGE_REPORT_ENTRIES=()

record_merge_result() {
  local branch=$1
  local status=$2  # success, auto-merged, ai-resolved, failed
  local details=${3:-""}

  MERGE_REPORT_ENTRIES+=("$branch|$status|$details")
}

# Generate merge report
generate_merge_report() {
  local report_file=${MERGE_REPORT_FILE:-"merge-report.md"}

  log_info "Generating merge report: $report_file"

  cat > "$report_file" <<EOF
# Merge Report

Generated: $(date '+%Y-%m-%d %H:%M:%S')
Target Branch: $MAIN_BRANCH

## Summary

| Branch | Status | Details |
|--------|--------|---------|
EOF

  local success=0
  local failed=0

  for entry in "${MERGE_REPORT_ENTRIES[@]}"; do
    local branch=$(echo "$entry" | cut -d'|' -f1)
    local status=$(echo "$entry" | cut -d'|' -f2)
    local details=$(echo "$entry" | cut -d'|' -f3-)

    local status_emoji=""
    case "$status" in
      success) status_emoji="✅"; ((success++)) ;;
      auto-merged) status_emoji="🔄"; ((success++)) ;;
      ai-resolved) status_emoji="🤖"; ((success++)) ;;
      failed) status_emoji="❌"; ((failed++)) ;;
    esac

    echo "| $branch | $status_emoji $status | $details |" >> "$report_file"
  done

  cat >> "$report_file" <<EOF

## Statistics

- **Total branches:** ${#MERGE_REPORT_ENTRIES[@]}
- **Successfully merged:** $success
- **Failed:** $failed

EOF

  # Add detailed conflict resolution info if AI was used
  if [[ "$USE_AI_MERGE" == "true" ]]; then
    cat >> "$report_file" <<EOF
## AI Merge Details

AI merge mode was enabled. Claude Code was used to resolve conflicts that couldn't be auto-merged.

### Resolution Strategy

1. **LOW severity conflicts** - Auto-merged using main branch version
2. **MEDIUM/HIGH severity conflicts** - Resolved by Claude Code analyzing both sides and intelligently combining changes

EOF

    # Include any Claude Code logs
    if [[ -d "$COMM_DIR" ]]; then
      local has_logs=false
      for logfile in "$COMM_DIR"/claude-resolve-*.log; do
        if [[ -f "$logfile" ]]; then
          if [[ "$has_logs" == "false" ]]; then
            echo "### Claude Code Resolution Logs" >> "$report_file"
            echo "" >> "$report_file"
            has_logs=true
          fi
          echo "<details>" >> "$report_file"
          echo "<summary>$(basename "$logfile")</summary>" >> "$report_file"
          echo "" >> "$report_file"
          echo '```' >> "$report_file"
          head -200 "$logfile" >> "$report_file" 2>/dev/null || true
          echo '```' >> "$report_file"
          echo "</details>" >> "$report_file"
          echo "" >> "$report_file"
        fi
      done
    fi
  fi

  # Add failed branch details
  if [[ $failed -gt 0 ]]; then
    cat >> "$report_file" <<EOF
## Failed Merges

The following branches could not be merged automatically:

EOF
    for entry in "${MERGE_REPORT_ENTRIES[@]}"; do
      local branch=$(echo "$entry" | cut -d'|' -f1)
      local status=$(echo "$entry" | cut -d'|' -f2)
      local details=$(echo "$entry" | cut -d'|' -f3-)

      if [[ "$status" == "failed" ]]; then
        cat >> "$report_file" <<EOF
### $branch

**Reason:** $details

**Manual resolution steps:**
\`\`\`bash
git checkout $MAIN_BRANCH
git merge $branch
# Resolve conflicts manually
git add <resolved-files>
git commit
\`\`\`

EOF
      fi
    done
  fi

  log_success "Merge report saved to: $report_file"
}

# Merge a single branch with intelligent conflict resolution
merge_branch() {
  local branch=$1

  log_info "Merging branch: $branch"

  # Switch to main branch
  git checkout "$MAIN_BRANCH" 2>/dev/null || {
    log_error "Failed to checkout $MAIN_BRANCH"
    record_merge_result "$branch" "failed" "Failed to checkout $MAIN_BRANCH"
    return 1
  }

  # Try fast-forward merge first
  if git merge --ff-only "$branch" 2>/dev/null; then
    log_success "Fast-forward merge succeeded for $branch"
    record_merge_result "$branch" "success" "Fast-forward merge"
    git branch -d "$branch" 2>/dev/null || true
    return 0
  fi

  # Fast-forward failed, try regular merge
  log_info "Fast-forward not possible, attempting regular merge..."

  if git merge --no-ff -m "Merge $branch into $MAIN_BRANCH" "$branch" 2>/dev/null; then
    log_success "Merge succeeded for $branch"
    record_merge_result "$branch" "success" "Regular merge (no conflicts)"
    git branch -d "$branch" 2>/dev/null || true
    return 0
  fi

  # Merge failed, analyze conflicts
  log_warn "Merge conflict detected in $branch"

  # Get conflict analysis
  local analysis_output
  analysis_output=$(analyze_all_conflicts 2>&1)
  local analysis_result=$?
  echo "$analysis_output"

  # Get list of conflicted files for reporting
  local conflicted_files_list
  conflicted_files_list=$(git diff --name-only --diff-filter=U | tr '\n' ', ' | sed 's/,$//')

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
        record_merge_result "$branch" "auto-merged" "LOW severity conflicts auto-resolved: $conflicted_files_list"
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
        record_merge_result "$branch" "ai-resolved" "MEDIUM severity conflicts: $conflicted_files_list"
        git branch -d "$branch" 2>/dev/null || true
        return 0
      fi
    fi
  fi

  # HIGH severity or previous methods failed - try Claude Code if --ai is enabled
  if [[ "$USE_AI_MERGE" == "true" ]]; then
    log_info "Using Claude Code to resolve HIGH severity conflicts..."

    if claude_code_resolve_conflicts "$branch"; then
      # Check if all resolved
      local remaining
      remaining=$(git diff --name-only --diff-filter=U | wc -l | tr -d ' ')

      if [[ $remaining -eq 0 ]]; then
        git commit --no-edit 2>/dev/null || true
        log_success "All conflicts resolved by Claude Code for $branch"
        record_merge_result "$branch" "ai-resolved" "Claude Code resolved HIGH severity conflicts: $conflicted_files_list"
        git branch -d "$branch" 2>/dev/null || true
        return 0
      fi
    fi
  fi

  # All methods failed - manual review required
  log_error "Manual review required for $branch"
  log_error "Conflicted files:"
  local conflict_details=""
  git diff --name-only --diff-filter=U | while read -r f; do
    local severity=$(analyze_conflict_severity "$f")
    echo "  [$severity] $f"
    conflict_details+="[$severity] $f, "
  done

  record_merge_result "$branch" "failed" "Conflicts require manual review: $conflicted_files_list"

  # Abort the merge
  git merge --abort 2>/dev/null || true

  return 1
}

# Main merge process
main() {
  log_info "Starting intelligent merge process..."

  if [[ "$USE_AI_MERGE" == "true" ]]; then
    log_info "AI merge mode enabled (--ai)"
  fi

  # Ensure clean working directory before merge
  # prd.json is often modified by raffaello.sh but not committed
  if [[ -n "$(git status --porcelain 2>/dev/null | grep -v '^??' || true)" ]]; then
    log_info "Stashing uncommitted changes before merge..."
    git stash push -m "raffaello-merge-temp" --include-untracked 2>/dev/null || true
    trap 'git stash pop 2>/dev/null || true' EXIT
  fi

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
      ((success_count++)) || true
    else
      ((failed_count++)) || true
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
  else
    log_success "All branches merged successfully!"
  fi

  # Generate merge report
  generate_merge_report

  if [[ $failed_count -gt 0 ]]; then
    return 1
  else
    return 0
  fi
}

# Run main
main
