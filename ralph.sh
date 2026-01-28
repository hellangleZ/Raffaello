#!/usr/bin/env bash
# Ralph Parallel - Main Execution Loop
# Orchestrates parallel execution of multiple user stories

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "$SCRIPT_DIR/lib/detect-cli.sh"
source "$SCRIPT_DIR/lib/agent-api.sh"
source "$SCRIPT_DIR/lib/prd-validator.sh"

# Source unified logging
export LOG_PREFIX="INFO"
source "$SCRIPT_DIR/lib/logging.sh"

# Configuration
MAX_PARALLEL_STORIES=${MAX_PARALLEL_STORIES:-3}

# Try current directory first, then script directory
if [[ -f "prd.json" ]]; then
  PRD_FILE="${PRD_FILE:-$(pwd)/prd.json}"
else
  PRD_FILE="${PRD_FILE:-$SCRIPT_DIR/prd.json}"
fi

if [[ -f "progress.txt" ]]; then
  PROGRESS_FILE="${PROGRESS_FILE:-$(pwd)/progress.txt}"
else
  PROGRESS_FILE="${PROGRESS_FILE:-$SCRIPT_DIR/progress.txt}"
fi

# Temporary directory for PID tracking (Bash 3.2 compatible)
PID_TRACKING_DIR=$(mktemp -d)
trap 'rm -rf "$PID_TRACKING_DIR"' EXIT

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

  # Validate PRD structure and content
  log_info "Validating PRD file..."
  if ! validate_prd "$PRD_FILE" 2>&1 | while IFS= read -r line; do
    if [[ "$line" =~ ^ERROR: ]]; then
      log_error "${line#ERROR: }"
    elif [[ "$line" =~ ^✓ ]]; then
      log_success "${line#✓ }"
    else
      echo "$line"
    fi
  done; then
    log_error "PRD validation failed"
    exit 1
  fi

  # Check if current directory is a git repository
  if ! git rev-parse --git-dir &>/dev/null; then
    log_warn "Current directory is not a git repository"
    echo ""
    echo "Ralph uses git branches to isolate work for each user story."
    echo "This allows parallel execution and easy rollback if needed."
    echo ""

    # Safety checks before initializing git
    local current_dir
    current_dir="$(pwd)"

    # CRITICAL: Prevent git init in dangerous locations
    # Block home directory (any user)
    if [[ "$current_dir" == "$HOME" ]]; then
      log_error "UNSAFE LOCATION: Cannot initialize git in home directory!"
      log_error "Current directory: $current_dir"
      echo ""
      echo "Initializing git in your home directory would track ALL personal files."
      echo ""
      echo "Please:"
      echo "  1. Create a dedicated project directory"
      echo "  2. cd into that directory"
      echo "  3. Run ralph.sh again"
      echo ""
      echo "Example:"
      echo "  mkdir -p ~/projects/my-project"
      echo "  cd ~/projects/my-project"
      echo "  cp /path/to/prd.json ."
      echo "  /path/to/ralph.sh"
      exit 1
    fi

    # Block system critical directories (macOS and Linux)
    local dangerous_dirs=(
      "/"                    # Root
      "/bin"                 # System binaries
      "/boot"                # Boot files (Linux)
      "/dev"                 # Device files
      "/etc"                 # System configuration
      "/lib"                 # System libraries
      "/lib64"               # 64-bit libraries (Linux)
      "/opt"                 # Optional packages
      "/proc"                # Process info (Linux)
      "/root"                # Root user home (Linux)
      "/sbin"                # System binaries
      "/sys"                 # System info (Linux)
      "/tmp"                 # Temporary files
      "/usr"                 # User programs
      "/var"                 # Variable data
      "/System"              # macOS system
      "/Library"             # macOS system library
      "/Applications"        # macOS applications
      "/Users"               # macOS users directory
      "/home"                # Linux users directory
      "/mnt"                 # Mount points (Linux)
      "/media"               # Removable media (Linux)
      "/srv"                 # Service data (Linux)
    )

    for dangerous_dir in "${dangerous_dirs[@]}"; do
      if [[ "$current_dir" == "$dangerous_dir" ]]; then
        log_error "UNSAFE LOCATION: Cannot initialize git in system directory!"
        log_error "Current directory: $current_dir"
        echo ""
        echo "This is a critical system directory."
        echo "Initializing git here could damage your system."
        echo ""
        echo "Please create a project directory in a safe location:"
        echo "  mkdir -p ~/projects/my-project"
        echo "  cd ~/projects/my-project"
        exit 1
      fi
    done

    # Block top-level user directories (e.g., /Users/username, /home/username)
    if [[ "$current_dir" =~ ^/Users/[^/]+$ ]] || \
       [[ "$current_dir" =~ ^/home/[^/]+$ ]]; then
      log_error "UNSAFE LOCATION: Cannot initialize git in user home directory!"
      log_error "Current directory: $current_dir"
      echo ""
      echo "This is a user home directory."
      echo "Please create a subdirectory for your project:"
      echo "  mkdir -p $current_dir/projects/my-project"
      echo "  cd $current_dir/projects/my-project"
      exit 1
    fi

    # Show current directory prominently
    echo "════════════════════════════════════════"
    echo "⚠️  GIT INITIALIZATION WARNING"
    echo "════════════════════════════════════════"
    echo ""
    echo "Current directory:"
    echo "  $current_dir"
    echo ""
    echo "This will:"
    echo "  1. Run: git init"
    echo "  2. Run: git add -A (stage ALL files in this directory)"
    echo "  3. Run: git commit -m 'Initial commit'"
    echo ""
    echo "Files in current directory:"
    ls -la | head -10
    echo ""
    echo "════════════════════════════════════════"
    echo ""
    echo "Is this the CORRECT project directory? (yes/no)"
    echo "Type 'yes' to proceed, anything else to abort:"
    read -r answer

    if [[ "$answer" == "yes" ]]; then
      log_info "Initializing git repository in: $current_dir"

      # Initialize git
      if ! git init; then
        log_error "git init failed"
        exit 1
      fi

      # Show what will be added
      echo ""
      log_info "Files to be added to git:"
      git status --short | head -20
      local file_count
      file_count=$(git status --short | wc -l | tr -d ' ')
      if [[ $file_count -gt 20 ]]; then
        echo "... and $((file_count - 20)) more files"
      fi
      echo ""

      # Final confirmation before git add
      echo "About to stage $file_count files. Continue? (yes/no)"
      read -r confirm
      if [[ "$confirm" != "yes" ]]; then
        log_warn "Aborting. Cleaning up git repository..."
        rm -rf .git
        exit 1
      fi

      # Add and commit
      git add -A
      if git commit -m "Initial commit"; then
        log_success "Git repository initialized successfully"
      else
        log_error "git commit failed (this is okay if there are no files)"
      fi
    else
      log_error "Git repository required to use Ralph"
      echo ""
      echo "To initialize manually in the correct directory:"
      echo "  cd /path/to/your/project"
      echo "  git init"
      echo "  git add -A"
      echo "  git commit -m 'Initial commit'"
      exit 1
    fi
  fi

  # Check if on main/master branch
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ -n "$current_branch" && "$current_branch" != "main" && "$current_branch" != "master" ]]; then
    log_warn "Not on main/master branch (currently on: $current_branch)"
    echo ""
    echo "Ralph works best when starting from main/master branch."
    echo "Would you like to checkout main? (y/n)"
    read -r answer
    if [[ "$answer" =~ ^[Yy] ]]; then
      # Try main first, then master
      if git rev-parse --verify main &>/dev/null; then
        git checkout main
        log_success "Checked out main branch"
      elif git rev-parse --verify master &>/dev/null; then
        git checkout master
        log_success "Checked out master branch"
      else
        log_warn "Neither main nor master branch exists, staying on $current_branch"
      fi
    else
      log_warn "Continuing on branch: $current_branch"
    fi
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
  local title
  title=$(get_story "$story_id" | jq -r '.title')
  if [[ -z "$title" || "$title" == "null" ]]; then
    log_error "Story not found in PRD: $story_id"
    return 1
  fi
  echo "$title"
}

# Get story workflow (default to 'standard')
get_story_workflow() {
  local story_id=$1
  get_story "$story_id" | jq -r '.workflow // "standard"'
}

# Validate story exists in PRD
validate_story_exists() {
  local story_id=$1
  local story
  story=$(get_story "$story_id")
  if [[ -z "$story" || "$story" == "null" ]]; then
    log_error "Story not found in PRD: $story_id"
    log_error "Available stories: $(jq -r '.userStories[].id' "$PRD_FILE" | tr '\n' ' ')"
    return 1
  fi
  return 0
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

  # Validate story exists
  if ! validate_story_exists "$story_id"; then
    return 1
  fi

  # Check if branch already exists (idempotency)
  local branch_name="story-$story_id"
  if git rev-parse --verify "$branch_name" &>/dev/null; then
    log_warn "Branch $branch_name already exists, checking out existing branch"
    git checkout "$branch_name" 2>/dev/null || {
      log_error "Failed to checkout existing branch: $branch_name"
      return 1
    }
  else
    # Create story branch
    git checkout -b "$branch_name" 2>/dev/null || {
      log_error "Failed to create branch: $branch_name"
      return 1
    }
  fi

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
      story_title=$(get_story_title "$story_id") || continue

      # Start story execution in background
      execute_story "$story_id" "$story_title" &
      local pid=$!
      pids+=("$pid")

      # Store PID to story_id mapping in file (Bash 3.2 compatible)
      echo "$story_id" > "$PID_TRACKING_DIR/$pid"

      ((concurrent++))

      # If we've reached max parallel, wait for one to finish
      if [[ $concurrent -ge $MAX_PARALLEL_STORIES ]]; then
        # Bash 3.2 compatible: wait for all, then decrement
        if wait -n "${pids[@]}" 2>/dev/null; then
          ((concurrent--))
        else
          # wait -n not supported (Bash 3.2), wait for any PID
          wait "${pids[0]}" || true
          ((concurrent--))
        fi
      fi
    done

    # Wait for all stories in this batch to complete
    log_info "Waiting for batch $((batch_idx + 1)) to complete..."
    for pid in "${pids[@]}"; do
      local story_id
      if [[ -f "$PID_TRACKING_DIR/$pid" ]]; then
        story_id=$(<"$PID_TRACKING_DIR/$pid")
      else
        story_id="unknown"
      fi

      if wait "$pid"; then
        log_success "Story $story_id finished successfully"
      else
        log_error "Story $story_id failed"
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
