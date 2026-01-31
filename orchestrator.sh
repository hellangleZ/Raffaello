#!/usr/bin/env bash
# Orchestrator - Manages execution phases for a single story
# Loads workflow configuration and executes each phase with appropriate agents

# Ensure we always run under bash even if invoked via sh/dash
if [[ -z "${BASH_VERSION:-}" ]]; then
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

# Fast fail if this script is syntactically broken in the current environment.
# This helps diagnose cases where runtime output is misleading (e.g. parallel logs).
if ! bash -n "$0" 2>/dev/null; then
  echo "[ORCHESTRATOR] ERROR: bash syntax check failed for $0" >&2
  bash -n "$0" >&2 || true
  exit 2
fi

# Project root directory (inherited from raffaello.sh via SCRIPT_DIR)
# Do NOT redefine SCRIPT_DIR here to avoid path collision
PROJECT_ROOT="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Source libraries
source "$PROJECT_ROOT/lib/detect-cli.sh"
source "$PROJECT_ROOT/lib/agent-api.sh"
source "$PROJECT_ROOT/lib/load-agents.sh"
source "$PROJECT_ROOT/lib/contract-files.sh" 2>/dev/null || true

# Source unified logging
export LOG_PREFIX="ORCHESTRATOR"
source "$PROJECT_ROOT/lib/logging.sh"

# Configuration
# Try current directory first, then project root
if [[ -f "prd.json" ]]; then
  PRD_FILE="${PRD_FILE:-$(pwd)/prd.json}"
else
  PRD_FILE="${PRD_FILE:-$PROJECT_ROOT/prd.json}"
fi
WORKFLOWS_DIR="$(cd "$(dirname "$PRD_FILE")" && pwd)/workflows"

# Get story ID from argument
STORY_ID=${1:-}

if [[ -z "$STORY_ID" ]]; then
  log_error "Story ID required"
  echo "Usage: $0 <story_id>"
  exit 1
fi

# Temporary file for retry policy
RETRY_POLICY_FILE=""

# Cleanup function
cleanup() {
  [[ -n "$RETRY_POLICY_FILE" && -f "$RETRY_POLICY_FILE" ]] && rm -f "$RETRY_POLICY_FILE"
}

# Set up trap for cleanup
trap cleanup EXIT INT TERM

# Get story details from PRD
get_story() {
  local story
  story=$(jq ".userStories[] | select(.id == \"$STORY_ID\")" "$PRD_FILE")
  if [[ -z "$story" || "$story" == "null" ]]; then
    log_error "Story not found in PRD: $STORY_ID"
    log_error "Available stories: $(jq -r '.userStories[].id' "$PRD_FILE" | tr '\n' ' ')"
    exit 1
  fi
  echo "$story"
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

get_baseline_contract_text() {
  local repo_root
  repo_root=$(cd "$(dirname "$PRD_FILE")" && pwd)
  local contract="$repo_root/workflows/${CONTRACT_BASENAME:-BASELINE_CONTRACT.md}"
  if [[ -f "$contract" ]]; then
    echo "
Baseline Contract (workflows/${CONTRACT_BASENAME:-BASELINE_CONTRACT.md}):"
    cat "$contract"
  fi
}

# Get baseline environment snapshot (dependencies, toolchain info)
# Only inject for non-baseline stories
get_baseline_environment_snapshot() {
  local repo_root
  repo_root=$(cd "$(dirname "$PRD_FILE")" && pwd)

  # Check if this is the baseline story (STORY-001 or priority=1)
  local is_baseline=false
  local story_priority
  story_priority=$(get_story | jq -r '.priority // 999')
  if [[ "$STORY_ID" == "STORY-001" || "$story_priority" == "1" ]]; then
    is_baseline=true
  fi

  # Only inject environment info for non-baseline stories
  if [[ "$is_baseline" == "true" ]]; then
    return
  fi

  local has_env=false

  # Node.js / JavaScript
  if [[ -f "$repo_root/package.json" ]]; then
    has_env=true
    echo ""
    echo "## Baseline Environment (Established by STORY-001)"
    echo ""
    echo "### Node.js Dependencies"
    echo "The following dependencies are already installed. USE THESE instead of adding new ones:"
    echo '```json'
    jq '{dependencies, devDependencies}' "$repo_root/package.json" 2>/dev/null || echo "{}"
    echo '```'
    echo ""
    echo "### Available Scripts"
    echo '```json'
    jq '.scripts // {}' "$repo_root/package.json" 2>/dev/null || echo "{}"
    echo '```'
  fi

  # Python
  if [[ -f "$repo_root/requirements.txt" ]]; then
    has_env=true
    echo ""
    echo "### Python Dependencies (requirements.txt)"
    echo '```'
    cat "$repo_root/requirements.txt"
    echo '```'
  fi

  if [[ -f "$repo_root/pyproject.toml" ]]; then
    has_env=true
    echo ""
    echo "### Python Project (pyproject.toml)"
    echo '```toml'
    cat "$repo_root/pyproject.toml"
    echo '```'
  fi

  # Go
  if [[ -f "$repo_root/go.mod" ]]; then
    has_env=true
    echo ""
    echo "### Go Modules (go.mod)"
    echo '```'
    cat "$repo_root/go.mod"
    echo '```'
  fi

  # Rust
  if [[ -f "$repo_root/Cargo.toml" ]]; then
    has_env=true
    echo ""
    echo "### Rust Dependencies (Cargo.toml)"
    echo '```toml'
    cat "$repo_root/Cargo.toml"
    echo '```'
  fi

  if [[ "$has_env" == "true" ]]; then
    echo ""
    echo "**IMPORTANT**: If you need to add new dependencies, document the reason in implementation-summary.md"
  fi
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

append_run_feedback() {
  local phase=$1
  local comm_dir="$AGENT_COMM_DIR/$STORY_ID"
  local feedback_file="$comm_dir/.restart-feedback.md"

  {
    echo "# Workflow restart feedback"
    echo
    echo "Failed phase: $phase"
    echo "Timestamp: $(date -Is)"
    echo
    echo "## Recent phase output (head 40 + tail 80)"
    if [[ -f "$comm_dir/${phase}-output.txt" ]]; then
      echo "--- head ---"
      head -n 40 "$comm_dir/${phase}-output.txt"
      echo
      echo "--- tail ---"
      tail -n 80 "$comm_dir/${phase}-output.txt"
    else
      echo "(no ${phase}-output.txt)"
    fi
    echo
  } >>"$feedback_file" 2>/dev/null || true
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
  export WORKFLOW_NAME=$(yq -r '.name' "$workflow_file")

  # Get phases as array
  WORKFLOW_PHASES=()
  while IFS= read -r phase; do
    WORKFLOW_PHASES+=("$phase")
  done < <(yq -r '.phases[]' "$workflow_file")

  # Recreate retry policy temp file (Bash 3.2 compatible)
  if [[ -n "$RETRY_POLICY_FILE" && -f "$RETRY_POLICY_FILE" ]]; then
    rm -f "$RETRY_POLICY_FILE"
  fi
  RETRY_POLICY_FILE=$(mktemp)
  for phase in "${WORKFLOW_PHASES[@]}"; do
    local max_attempts=$(yq -r ".retry_policy.$phase.max_attempts // 1" "$workflow_file")
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

    # If a previous attempt was aborted (e.g. by monitor-kill), clear the marker so retries can proceed.
    rm -f "$AGENT_COMM_DIR/$STORY_ID/.${phase}-abort" 2>/dev/null || true

    local feedback_hint=""
    local feedback_file="$AGENT_COMM_DIR/$STORY_ID/.restart-feedback.md"
    # Only inject feedback into planner/coder so they can adjust plan/implementation.
    # Keep reviewer/tester prompts small to reduce noise.
    if [[ ( "$phase" == "planner" || "$phase" == "coder" ) && -f "$feedback_file" ]]; then
      feedback_hint="

Previous run feedback (must address):
$(cat "$feedback_file")
"
    fi

    local comm_dir="$AGENT_COMM_DIR/$STORY_ID"

    # Prepare task message
    local task_message="Execute $phase for story $STORY_ID

Story: $(get_story_title)
Description: $(get_story_description)

Acceptance Criteria:
$(get_story_acceptance_criteria)
$(get_baseline_contract_text)
$(get_baseline_environment_snapshot)

Communication Directory (absolute path): $comm_dir

IMPORTANT:
- Any files you create MUST be under the communication directory above.
- When referencing \$COMMUNICATION_DIRECTORY, treat it as that same absolute path.
- Do not write to /aml, /, or any other directory.

$feedback_hint
"

    # Check if agent exists (may be optional)
    if ! agent_exists "$phase"; then
      log_error "Agent not found: $phase"
      return 1
    fi

    # Prepare optional agent if needed
    prepare_optional_agent "$phase" 2>/dev/null || true

    # Spawn agent
    local agent_id

    # Always start phases from a clean comm dir to avoid mixing outputs across retries.
    local comm_dir="$AGENT_COMM_DIR/$STORY_ID"
    rm -f "$comm_dir/plan.md" \
      "$comm_dir/implementation-summary.md" \
      "$comm_dir/review-changes.md" \
      "$comm_dir/review-approved.md" \
      "$comm_dir/e2e-report.md" \
      "$comm_dir/test-results.json" \
      2>/dev/null || true

    agent_id=$(spawn_agent "$phase" "$task_message" "$STORY_ID")

    log_info "  Spawned agent: $agent_id"
    if [[ "$agent_id" =~ ^cc-pid-([0-9]+)$ ]]; then
      log_info "  Agent PID: ${BASH_REMATCH[1]}"
    fi

    # Wait for agent to complete
    if ! wait_for_agent "$STORY_ID" "$phase" "$agent_id"; then
      close_agent "$agent_id" 2>/dev/null || true

      # For reviewer/tester failures, restart the workflow from planner.
      # Rationale: a failed review or failed tests usually implies the plan/implementation needs revision.
      if [[ "$phase" == "reviewer" || "$phase" == "tester" ]]; then
        append_run_feedback "$phase"
        log_warn "Phase $phase failed; restarting workflow from planner"
        return 2
      fi

      # Otherwise, allow retry within this phase.
      ((attempt++))
      continue
    fi

    # Artifact-based success (phase-specific) to avoid relying solely on marker files.
    # This is important when the CLI completes the work but doesn't create the marker.
    local comm_dir="$AGENT_COMM_DIR/$STORY_ID"
    if [[ "$phase" == "planner" && -f "$comm_dir/plan.md" ]]; then
      mark_agent_success "$STORY_ID" "$phase" 2>/dev/null || true
    fi
    if [[ "$phase" == "coder" ]]; then
      # Consider coder successful when it leaves behind a work summary artifact.
      # This avoids brittle reliance on a hidden marker file.
      if [[ -f "$comm_dir/implementation-summary.md" ]]; then
        mark_agent_success "$STORY_ID" "$phase" 2>/dev/null || true
      fi
    fi
    if [[ "$phase" == "reviewer" && ( -f "$comm_dir/review-changes.md" || -f "$comm_dir/review-approved.md" ) ]]; then
      mark_agent_success "$STORY_ID" "$phase" 2>/dev/null || true
    fi
    if [[ "$phase" == "tester" ]]; then
      if [[ -f "$comm_dir/e2e-report.md" || -f "$comm_dir/test-results.json" ]]; then
        mark_agent_success "$STORY_ID" "$phase" 2>/dev/null || true
      fi
    fi

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

      # Show what files were created
      local comm_dir="$AGENT_COMM_DIR/$STORY_ID"
      echo "  Files in $comm_dir:"
      ls -la "$comm_dir/" 2>/dev/null | grep -E "(review-|success|${phase}-output)" | head -10 || echo "    (no review files found)"

      # If reviewer failed, show the review findings
      if [[ "$phase" == "reviewer" ]]; then
        local review_file="$comm_dir/review-changes.md"
        if [[ -f "$review_file" ]]; then
          echo "  Review findings:"
          grep -E '^##|^###|^\-\s+\*\*' "$review_file" | head -20 | sed 's/^/    /'
        fi
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
  log_debug "Bash: ${BASH_VERSION:-unknown}"
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
  local start_index=0
  local idx=0
  while [[ $idx -lt ${#WORKFLOW_PHASES[@]} ]]; do
    local phase=${WORKFLOW_PHASES[$idx]}
    set +e
    execute_phase "$phase"
    local phase_rc=$?
    set -e

    if [[ $phase_rc -eq 0 ]]; then
      ((idx++)) || true
      continue
    fi

    if [[ $phase_rc -eq 2 ]]; then
      idx=0
      continue
    fi

    log_error "Orchestration failed at phase: $phase"
    update_story_status "false"
    exit 1
  done

  # All phases passed - update PRD
  update_story_status "true"

  # Commit the story implementation
  log_info "Committing story implementation..."

  # Never commit build artifacts, coverage reports, or dependencies.
  # Agents may generate these during tests; keeping them out of git avoids
  # huge commits and merge conflicts.
  git add -A
  git reset -q -- node_modules dist coverage playwright-report test-results .playwright .vite .turbo .next 2>/dev/null || true
  git checkout -q -- node_modules dist coverage playwright-report test-results .playwright .vite .turbo .next 2>/dev/null || true
  git clean -fdq -- node_modules dist coverage playwright-report test-results .playwright .vite .turbo .next 2>/dev/null || true

  local commit_msg_file
  commit_msg_file=$(mktemp)
  {
    echo "feat: $STORY_ID - $story_title"
    echo
    get_story_description
    echo
    echo "Workflow: $workflow"
    echo "Phases: ${WORKFLOW_PHASES[*]}"
    echo
    echo "Co-Authored-By: Claude <noreply@anthropic.com>"
  } >"$commit_msg_file"

  git commit -F "$commit_msg_file" || true
  rm -f "$commit_msg_file" 2>/dev/null || true

  log_success "Story $STORY_ID completed successfully!"

  # Some Claude CLI runs can hang after the phase is marked successful (e.g. during
  # pre-flight). At this point the story is already committed and PRD updated, so
  # it is safe to force-terminate any still-running phase pids to prevent the
  # whole batch from appearing stuck.
  local force_kill_after=${FORCE_KILL_DONE_PIDS_SECS:-30}
  sleep "$force_kill_after" 2>/dev/null || true
  for phase in planner coder reviewer tester; do
    local pid_file="$AGENT_COMM_DIR/$STORY_ID/${phase}.pid"
    [[ -f "$pid_file" ]] || continue
    local pid
    pid=$(tr -d ' \n\r\t' <"$pid_file" 2>/dev/null || true)
    [[ -n "$pid" ]] || continue
    if kill -0 "$pid" 2>/dev/null; then
      log_warn "Force-terminating lingering pid after completion: story=$STORY_ID phase=$phase pid=$pid"
      kill -TERM "$pid" 2>/dev/null || true
      sleep 2
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done
}

# Run main
main
