<div align="center">

<img src="raffaello.png" alt="Raffaello" width="300"/>

# Raffaello 🐢

**The Parallel Execution Master** - Ralph's cooler, faster twin brother

*Named after Raphael, the red-masked Ninja Turtle known for his speed and parallel sai strikes*

[![GitHub](https://img.shields.io/github/license/re-zhou/Raffaello)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

> **English** | [中文](#中文版本)

</div>

---

Raffaello is the **parallel execution version** of Ralph - a next-generation autonomous agent system that executes multiple user stories simultaneously instead of sequentially.

**What Raffaello solves**:
1. **Parallel Execution** - Execute multiple user stories simultaneously instead of sequentially
2. **Subagent Utilization** - Properly leverage specialized agents (planner, coder, reviewer, tester)

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/re-zhou/Raffaello
cd Raffaello

# 2. Ensure dependencies are installed
brew install jq yq  # JSON and YAML parsing

# 3. Create your PRD
cp prd.json.example prd.json
# Edit prd.json with your user stories

# 4. Run Ralph Parallel
./ralph.sh
```

If you prefer a one-command wrapper (auto monitor + safer defaults):

```bash
/path/to/Raffaello/bin/ralph-start.sh --project-dir /path/to/your/project
```

See [QUICKSTART.md](QUICKSTART.md) for detailed setup instructions.
See [docs/RALPH-RUNBOOK.md](docs/RALPH-RUNBOOK.md) for a step-by-step start → monitor → merge → finish guide.

## Usage Instructions

### Running Raffaello

Raffaello reads `prd.json` from your **current directory** first, then falls back to the script directory if not found.

**Recommended workflow**:
```bash
# 1. Create a project directory
mkdir -p ~/projects/my-project
cd ~/projects/my-project

# 2. Copy or create your prd.json
cp /path/to/prd.json .
# OR generate using your PRD generator

# 3. Run Raffaello
/path/to/ralph-parallel/ralph.sh
```

**Important**: Raffaello will look for:
- `prd.json` in current directory (priority)
- `prd.json` in ralph-parallel directory (fallback)
- `workflows/` directory for workflow definitions

### PRD Field Compatibility

Raffaello supports both naming conventions:
- `projectName` (recommended) or `project` (legacy)
- Both are accepted by the validator

### Workflow Setup

Each story requires a `workflow` field. If not specified, defaults to `standard`.

**Ensure workflows exist**:
```bash
# Copy workflows to your project directory
cp -r /path/to/ralph-parallel/workflows .
```

Available workflows:
- `simple` - Fast (coder + tester only)
- `standard` - Balanced (planner + coder + reviewer + tester)
- `full-stack` - Complete (with optional specialists)

### Git Repository Requirement

Raffaello uses git branches to isolate work for each user story. Your project directory **must be a git repository**.

**First-time setup**:
```bash
cd ~/projects/my-project
git init
git add .
git commit -m "Initial commit"
```

Raffaello will offer to initialize git automatically if not found, with safety checks to prevent accidents.

## Why Ralph Parallel?

### Original Ralph (Sequential)
```
Iteration 1: Agent → Story 1 → passes:true (30 min)
Iteration 2: Agent → Story 2 → passes:true (30 min)
Iteration 3: Agent → Story 3 → passes:true (30 min)
Total Time: 90 minutes
```

### Ralph Parallel (Parallel)
```
           ┌→ Agent A → Story 1 → passes:true ┐
ralph.sh ──┼→ Agent B → Story 2 → passes:true ├→ Auto-merge
           └→ Agent C → Story 3 → passes:true ┘
Total Time: 30 minutes (3x faster!)
```

## Architecture Overview

Ralph Parallel uses a **three-level hierarchy** for execution:

### Level 1: Batch-Level Parallelism (ralph.sh)
```
ralph.sh analyzes dependencies and creates batches:

Batch 1 (parallel): Story US001, US002, US003  ← No dependencies
Batch 2 (parallel): Story US004, US005         ← Depend on US001
Batch 3 (serial):   Story US006                ← Depends on US004, US005
```

**Key point**: Stories within a batch run in **parallel** (3 simultaneous max). Batches run **sequentially**.

### Level 2: Story-Level Orchestration (orchestrator.sh)
```
Each story has its own orchestrator managing phases sequentially:

Story US001:
  orchestrator.sh US001
    ├─ Phase 1: planner   → Creates plan.md
    ├─ Phase 2: coder     → Implements code + tests
    ├─ Phase 3: reviewer  → Reviews for quality
    └─ Phase 4: tester    → Runs E2E tests
```

**Key point**: Phases within a story run **sequentially** (one after another).

### Level 3: Phase-Level Execution (agents)
```
Each phase is executed by a specialized agent:

Phase: coder
  └─ Agent: coder.md
      ├─ Reads plan.md
      ├─ Writes code
      ├─ Runs tests
      └─ Writes .coder-success marker
```

**Key point**: Each agent is autonomous and signals completion via success markers.

### Visual Example: 3 Stories in Parallel

```
Time ──────────────────────────────────────────────────>

ralph.sh starts Batch 1:
  │
  ├─ Story US001 (orchestrator.sh US001)
  │   ├─ planner ──> coder ──> reviewer ──> tester ──> ✅
  │
  ├─ Story US002 (orchestrator.sh US002)
  │   ├─ planner ──> coder ──> reviewer ──> tester ──> ✅
  │
  └─ Story US003 (orchestrator.sh US003)
      ├─ planner ──> coder ──> reviewer ──> tester ──> ✅

All 3 orchestrators run in parallel!
But within each orchestrator, phases run sequentially.
```

## Key Features

### 🚀 Parallel Execution at Story Level
- Execute up to 3 stories simultaneously
- Smart dependency analysis (DAG-based)
- Independent git branches per story
- Automatic merging on completion

**Important**: Parallelism happens at the **story level**, not the phase level. Each story's phases (planner → coder → reviewer → tester) run sequentially.

### 🤖 Sequential Orchestration at Phase Level
Each story is managed by an orchestrator with 4 specialized agents running **in sequence**:
- **Planner** - Creates implementation plans (Phase 1)
- **Coder** - Implements code following TDD (Phase 2)
- **Reviewer** - Reviews code for quality and security (Phase 3)
- **Tester** - Runs E2E tests and validates (Phase 4)

### 🔀 Intelligent Conflict Resolution
Three-tier resolution strategy:
- **LOW** severity → Auto-merge (simple conflicts)
- **MEDIUM** severity → AI resolver (import conflicts, formatting)
- **HIGH** severity → Manual review (logic conflicts)

### 📋 Flexible Workflows
Three built-in workflows + custom workflow support:
- **simple** - Fast (coder + tester only)
- **standard** - Balanced (all 4 agents)
- **full-stack** - Complete (includes optional specialists)

### 🔧 CLI Requirements
Requires:
- Claude Code CLI (installed and configured)
- Agent execution via Task tool

## 🛡️ Safety Features

### Git Initialization Protection

Raffaello includes comprehensive safety checks to prevent accidental git initialization in dangerous locations.

**Blocked locations**:
- **Home directories**: `$HOME`, `/Users/username`, `/home/username`
- **System directories**: `/`, `/usr`, `/var`, `/etc`, `/System`, `/Library`
- **Critical paths**: `/bin`, `/boot`, `/lib`, `/opt`, `/proc`, `/root`, `/sbin`, `/sys`, `/tmp`
- **Mount points**: `/mnt`, `/media`, `/srv`

**Safety mechanisms**:
1. **Pre-flight checks** - Detects and blocks dangerous paths before any git operation
2. **Visual confirmation** - Shows current directory and files before initialization
3. **Double confirmation** - Requires explicit "yes" answers (not just "y")
4. **File count preview** - Shows how many files will be tracked before `git add`
5. **Abort and cleanup** - Removes `.git` directory if user cancels at any step

**Example warning screen**:
```
════════════════════════════════════════
⚠️  GIT INITIALIZATION WARNING
════════════════════════════════════════

Current directory:
  /Users/alice/projects/my-app

This will:
  1. Run: git init
  2. Run: git add -A (stage ALL files in this directory)
  3. Run: git commit -m 'Initial commit'

Files in current directory:
[shows first 10 files]

Is this the CORRECT project directory? (yes/no)
Type 'yes' to proceed, anything else to abort:
```

**Cross-platform support**: Safety checks work on both macOS and Linux.

## Project Structure

```
ralph-parallel/
├── ralph.sh                 # Main parallel execution engine
├── orchestrator.sh          # Single-story phase management
├── merge-stories.sh         # Smart git merge system
├── prd.json                 # Your PRD file
├── progress.txt             # Execution log
├── lib/
│   ├── detect-cli.sh        # CLI detection
│   ├── agent-api.sh         # Agent API
│   ├── dependency-analyzer.sh  # DAG builder
│   ├── workflow-parser.sh   # YAML workflow parser
│   ├── conflict-analyzer.sh # Conflict severity grading
│   └── load-agents.sh       # Agent discovery
├── agents/
│   ├── planner.md           # Planning agent
│   ├── coder.md             # Implementation agent
│   ├── reviewer.md          # Code review agent
│   ├── tester.md            # Testing agent
│   └── conflict-resolver.md # Conflict resolution agent
├── workflows/
│   ├── simple.yaml          # Fast workflow
│   ├── standard.yaml        # Balanced workflow
│   └── full-stack.yaml      # Complete workflow
└── docs/
    ├── DESIGN.md            # Complete design documentation
    ├── WORKFLOWS.md         # Workflow system guide
    ├── ARCHITECTURE.md      # Architecture deep-dive
    └── COMPARISON.md        # vs Original Ralph
```

## PRD Format

```json
{
  "projectName": "My Project",
  "branchName": "main",
  "userStories": [
    {
      "id": "US001",
      "title": "User Authentication",
      "description": "Implement user login and registration",
      "workflow": "standard",
      "dependencies": [],
      "passes": false
    },
    {
      "id": "US002",
      "title": "Dashboard UI",
      "description": "Create user dashboard",
      "workflow": "simple",
      "dependencies": ["US001"],
      "passes": false
    }
  ]
}
```

### Key Fields

- **id** - Unique story identifier
- **title** - Brief story title
- **description** - Detailed requirements
- **workflow** - Which workflow to use (simple/standard/full-stack)
- **dependencies** - Array of story IDs this depends on
- **passes** - Set to false initially, Ralph sets to true when complete

## How It Works

### 1. Dependency Analysis
Ralph analyzes your PRD and builds a dependency graph:
```bash
./lib/dependency-analyzer.sh prd.json
```

Stories are grouped into batches where each batch contains independent stories.

### 2. Parallel Execution
Ralph executes batches sequentially, stories within batch in parallel:
```bash
Batch 1: US001, US002, US003 (parallel)
Batch 2: US004, US005 (parallel, depend on US001)
Batch 3: US006 (depends on US004, US005)
```

### 3. Story Orchestration
For each story, an orchestrator manages 4 phases:
```bash
Story US001:
  Phase 1: planner   → Create plan.md
  Phase 2: coder     → Implement code + tests
  Phase 3: reviewer  → Review for quality/security
  Phase 4: tester    → Run E2E tests
```

### 4. Smart Merging
After all stories in a batch complete, Ralph merges them:
```bash
./merge-stories.sh
# Automatically handles conflicts using 3-tier strategy
```

## Workflows

**Important**: Workflows define the **sequential execution order** of phases within a single story. They do NOT control parallelism (which happens at the story level).

### How Workflows Work

A workflow is simply a list of phases to execute **in order**:

```yaml
# workflows/standard.yaml
phases:
  - planner    # Step 1: Execute first
  - coder      # Step 2: Execute after planner succeeds
  - reviewer   # Step 3: Execute after coder succeeds
  - tester     # Step 4: Execute after reviewer succeeds
```

**Execution flow for one story**:
```
orchestrator.sh US001
  ├─ Read workflow: standard.yaml
  ├─ Execute phase 1: planner   (wait for success)
  ├─ Execute phase 2: coder     (wait for success)
  ├─ Execute phase 3: reviewer  (wait for success)
  └─ Execute phase 4: tester    (wait for success)
```

If any phase fails, the orchestrator retries based on `retry_policy`, then stops if max attempts reached.

### Simple Workflow (Fastest)
```yaml
name: simple
phases:
  - coder      # Skip planning, go straight to implementation
  - tester     # Run tests to verify

retry_policy:
  coder:
    max_attempts: 2
  tester:
    max_attempts: 1
```
**Use for**: Bug fixes, simple features, low-risk changes

**Execution time**: ~5-10 minutes per story

### Standard Workflow (Recommended)
```yaml
name: standard
phases:
  - planner    # Create implementation plan
  - coder      # Implement following the plan
  - reviewer   # Review code quality and security
  - tester     # Run E2E tests

retry_policy:
  planner:
    max_attempts: 1
  coder:
    max_attempts: 2    # Allow retry if implementation fails
  reviewer:
    max_attempts: 2    # Allow retry if review finds issues
  tester:
    max_attempts: 1
```
**Use for**: Most user stories, new features, refactoring

**Execution time**: ~10-20 minutes per story

### Full-Stack Workflow (Complete)
```yaml
name: full-stack
phases:
  - planner              # Create plan
  - architect            # Design system architecture (optional agent)
  - frontend-coder       # Implement frontend (optional agent)
  - backend-coder        # Implement backend (optional agent)
  - reviewer             # Code review
  - security-reviewer    # Security audit (optional agent)
  - ui-tester           # UI testing (optional agent)
  - integration-tester  # Integration testing (optional agent)

retry_policy:
  # ... (each phase has max_attempts)
```
**Use for**: Complex features, multi-layer changes, critical paths

**Execution time**: ~20-40 minutes per story

**Note**: Optional agents (architect, frontend-coder, etc.) must exist in `~/.claude/agents/` directory. If not found, the workflow will fail.

### Understanding retry_policy

```yaml
retry_policy:
  coder:
    max_attempts: 2
```

This means:
- Attempt 1: Run coder agent
  - If **success marker exists** → Continue to next phase
  - If **no success marker** → Retry
- Attempt 2: Run coder agent again
  - If **success marker exists** → Continue
  - If **no success marker** → **Story fails**, stop orchestration

### Custom Workflows

You can create your own workflow YAML file:

```yaml
# workflows/my-custom.yaml
name: my-custom
description: Custom workflow for my project
phases:
  - planner
  - my-custom-agent  # Must exist in ~/.claude/agents/my-custom-agent.md
  - coder
  - tester

retry_policy:
  planner:
    max_attempts: 1
  my-custom-agent:
    max_attempts: 1
  coder:
    max_attempts: 2
  tester:
    max_attempts: 1
```

Then reference it in your PRD:
```json
{
  "id": "US001",
  "workflow": "my-custom",
  ...
}
```

See [WORKFLOWS.md](docs/WORKFLOWS.md) for custom workflow creation.

## Conflict Resolution

Ralph uses a three-tier strategy:

### Tier 1: Auto-Merge (LOW Severity)
Automatically resolves:
- Whitespace conflicts
- Formatting differences
- Simple text conflicts (<5% of file)

### Tier 2: AI Resolver (MEDIUM Severity)
AI resolves:
- Import conflicts (merge both)
- Configuration merges (combine keys)
- Adjacent function additions
- Documentation conflicts

### Tier 3: Manual Review (HIGH Severity)
Requires human intervention:
- Logic conflicts (function body changes)
- Large conflicts (>20% of file)
- Complex business logic

Ralph will pause and provide a detailed conflict report for manual resolution.

## Configuration

### Environment Variables

```bash
# Maximum parallel stories (default: 3)
export MAX_PARALLEL_STORIES=3

# Communication directory (default: /tmp/ralph-parallel)
export AGENT_COMM_DIR=/tmp/ralph-parallel

# Main branch name (default: main)
export MAIN_BRANCH=main
```

### CLI Detection

Ralph requires Claude Code CLI:
```bash
# Claude Code
claude --version
# → Uses Task tool for agent management
```

## Commands

### Main Commands
```bash
./ralph.sh                    # Run parallel execution
./merge-stories.sh            # Merge story branches
```

### Utility Commands
```bash
# Analyze dependencies
./lib/dependency-analyzer.sh prd.json

# List workflows
./lib/workflow-parser.sh list

# Validate workflow
./lib/workflow-parser.sh validate standard

# Analyze conflicts
./lib/conflict-analyzer.sh analyze

# Run tests
./test-workflows.sh
```

## Comparison with Original Ralph

| Feature | Original Ralph | Ralph Parallel |
|---------|---------------|----------------|
| Execution Mode | Sequential | Parallel |
| Agent Count | 1 (reused) | N (simultaneous) |
| Subagents | Not used | Fully utilized |
| Speed | Slow | 2-3x faster |
| Complexity | Low | Medium |
| Conflict Handling | N/A (sequential) | Smart 3-tier system |
| Workflow System | None | YAML-based |
| Best For | Small projects | Large projects |

See [COMPARISON.md](docs/COMPARISON.md) for detailed analysis.

## Requirements

- **Bash**: 3.2+ (macOS compatible)
- **jq**: JSON parsing (`brew install jq`)
- **yq**: YAML parsing (`brew install yq`)
- **git**: Version control
- **Claude Code CLI**: AI execution engine

## Known Issues

### Issue 1: `wait -n` not supported in Bash 3.2 (macOS only)

**Symptom**: Warning message during execution:
```
wait: -n: invalid option
wait: usage: wait [n]
```

**Impact**: None - functionality works perfectly. Parallel execution still functions correctly.

**Explanation**:
- macOS ships with Bash 3.2 (released 2007) which doesn't support `wait -n`
- The system uses a fallback method that waits for all stories in a batch to complete
- **Ubuntu/Linux users**: This warning does NOT appear (Bash 5.0+ supports `wait -n`)

**Workaround**: Ignore the warning, or upgrade Bash:
```bash
brew install bash
# Then use /opt/homebrew/bin/bash instead of /bin/bash
```

### Issue 2: Auto-merge can fail if on story branch

**Symptom**: Merge errors at the end of execution:
```
[MERGE] Failed to checkout main
[MERGE] Failed to merge: 4
```

**Impact**: All stories complete successfully and are committed to their branches. Only the automatic merge to main fails.

**Cause**: If you're currently on a story branch (e.g., `story-US001`) when ralph.sh finishes, the auto-merge script cannot switch to `main`.

**Solution**: Manually merge the story branches:
```bash
git checkout main

# Merge each story branch
git merge story-US001
git merge story-US002
git merge story-US003

# Delete story branches (optional)
git branch -d story-US001 story-US002 story-US003
```

**Prevention**: Ensure you're on `main` branch before running `./ralph.sh`

## Limitations

### Current Limitations
1. **Parallel limit**: Max 3 stories to avoid API rate limits
2. **Manual conflicts**: High-severity conflicts require human intervention
3. **No cross-story communication**: Stories can't coordinate during execution
4. **File-level granularity**: Conflict detection at file level

### Planned Improvements
- Token cost optimization (use Haiku for planner/reviewer)
- Cross-story file locking
- Finer-grained conflict detection
- Rollback support for failed merges

## Troubleshooting & Debugging

### Avoid Committing `.ralph-worktrees/`

`.ralph-worktrees/` contains git worktrees and build artifacts, and should not be committed.

You only need to run `git rm -r --cached .ralph-worktrees` if you already accidentally committed it (one-time fix).

```bash
# Remove from index if accidentally committed
git rm -r --cached .ralph-worktrees || true

# Ensure it is ignored
echo '.ralph-worktrees/' >> .gitignore
```

### Understanding the Log Output

Ralph Parallel produces color-coded logs with different prefixes:

```bash
[INFO]         # General information (blue)
[SUCCESS]      # Successful operations (green)
[WARN]         # Warnings (yellow)
[ERROR]        # Errors (red)
[ORCHESTRATOR] # Orchestrator-level messages (blue)
[MERGE]        # Merge-related messages (blue/red)
```

### Viewing Real-Time Logs

Ralph Parallel outputs logs to stdout in real-time:

```bash
./ralph.sh

# Output:
[INFO] === Ralph Parallel - Starting Execution ===
[INFO] Found 4 incomplete stories
[INFO] Analyzing dependencies...
[INFO] Execution plan: 2 batches

[INFO] === Batch 1 / 2 ===
[INFO] Starting story: US001 - Add Header Component
[INFO] Starting story: US002 - Add Footer Component
[ORCHESTRATOR] Starting orchestration for story: US001
[ORCHESTRATOR] Executing phase: coder (max attempts: 2)
...
```

### Quick Commands (Copy/Paste)

```bash
# Tail a specific story log
tail -f .ralph-logs/STORY-001.log

# Inspect agent communication directory for a story
ls -la /tmp/ralph-parallel/STORY-001/

# Tail key phase output
tail -n 80 /tmp/ralph-parallel/STORY-001/coder-output.txt

# Check background agent pid (if present)
pid=$(cat /tmp/ralph-parallel/STORY-001/coder.pid 2>/dev/null || true)
[[ -n "$pid" ]] && ps -p "$pid" -o pid,ppid,cmd || echo "no pid"

# Watch whether output is still growing (helps spot stalls)
watch -n 2 'wc -c /tmp/ralph-parallel/STORY-001/*-output.txt 2>/dev/null || true'

# If a story looks "instantly passed" but produced no output, clear stale markers from older runs
rm -rf /tmp/ralph-parallel/STORY-001
```

### Background Monitor (Optional)

You can run a lightweight monitor in the background to periodically report story/agent status.

```bash
# Observe-only (recommended)
nohup /aml/raffaello/raffaello/monitor.sh /aml/test > /aml/test/.ralph-logs/monitor.nohup.log 2>&1 &
tail -f /aml/test/.ralph-logs/monitor.nohup.log

# Kill-stalled mode (use with care)
# - Kills an agent PID if: alive=yes, success=no, and output hasn't grown for STALL_SECS
# - Also writes an abort marker so the orchestrator stops waiting immediately.
STALL_SECS=300 INTERVAL_SECS=10 \
  nohup /aml/raffaello/raffaello/monitor-kill.sh /aml/test > /aml/test/.ralph-logs/monitor-kill.nohup.log 2>&1 &
tail -f /aml/test/.ralph-logs/monitor-kill.nohup.log

# Foreground (prints to terminal)
STALL_SECS=300 INTERVAL_SECS=10 \
  /aml/raffaello/raffaello/monitor-kill.sh /aml/test

# Quick stop + optional clean (kills ralph + agents)
/aml/raffaello/raffaello/kill-all.sh --project-dir /aml/test --clean

# Auto-enable kill-stalled monitor when running ralph.sh (use with care)
AUTO_MONITOR_KILL=true MONITOR_STALL_SECS=300 MONITOR_INTERVAL_SECS=10 \
  /aml/raffaello/ralph.sh

# Global rerun iterations (re-runs incomplete stories if any failed)
GLOBAL_MAX_ITERATIONS=2 /aml/raffaello/ralph.sh
```

### Check Story Progress

Each story writes its output to the agent communication directory:

```bash
# List all active stories
ls -la /tmp/ralph-parallel/

# Output:
drwxr-xr-x  US001/
drwxr-xr-x  US002/
drwxr-xr-x  US003/

# Check phases completed for a specific story
ls -la /tmp/ralph-parallel/US001/

# Output:
-rw-r--r--  .planner-success   # ✅ Planner completed
-rw-r--r--  .coder-success     # ✅ Coder completed
-rw-r--r--  .reviewer-success  # ✅ Reviewer completed
(missing .tester-success)      # ❌ Tester still running
```

### Check Agent Output

Each agent writes its prompt and output:

```bash
# View the prompt sent to an agent
cat /tmp/ralph-parallel/US001/coder-prompt.txt

# View the agent's execution output (if synchronous)
cat /tmp/ralph-parallel/US001/coder-output.txt
```

### Check Background Agent PID

Each phase persists its background process PID (when available) to help debugging.

```bash
# View the PID for a running phase
cat /tmp/ralph-parallel/US001/coder.pid

# Inspect the process
ps -p "$(cat /tmp/ralph-parallel/US001/coder.pid)" -o pid,ppid,cmd

# Follow live output
tail -f /tmp/ralph-parallel/US001/coder-output.txt
```

### Check PRD Status

The PRD file (`prd.json`) is updated in real-time:

```bash
# Check which stories are complete
jq '.userStories[] | select(.passes == true) | .id' prd.json

# Output:
"US001"
"US002"

# Check which stories are still pending
jq '.userStories[] | select(.passes == false) | .id' prd.json

# Output:
"US003"
"US004"
```

### Check Git Branches

Each story creates its own git branch:

```bash
# List all story branches
git branch | grep story-

# Output:
  story-US001
  story-US002
  story-US003

# Check commits on a story branch
git log story-US001 --oneline

# Output:
a1b2c3d feat: US001 - Add Header Component
e4f5g6h (main) Previous commit

# View changes in a story branch
git diff main...story-US001
```

### Common Debugging Scenarios

#### Scenario 1: Story Stuck in Phase

**Symptom**: Orchestrator shows phase running but never completes

**Debug steps**:
```bash
# 1. Check if success marker exists
ls /tmp/ralph-parallel/US001/.coder-success

# 2. If missing, check agent prompt
cat /tmp/ralph-parallel/US001/coder-prompt.txt

# 3. Check if claude task is running
claude task list

# 4. Check task output
claude task output <task-id>
```

**Common causes**:
- Agent waiting for user input (shouldn't happen with `--dangerously-skip-permissions`)
- Agent encountered an error
- Success marker not written correctly

#### Scenario 2: Phase Failed After Max Retries

**Symptom**: `[ORCHESTRATOR] Phase coder FAILED after 2 attempts`

**Debug steps**:
```bash
# 1. Check what the agent tried to do
cat /tmp/ralph-parallel/US001/coder-output.txt

# 2. Check git commits (agent may have partially completed)
git log story-US001 --oneline

# 3. Check if files were created
git status story-US001

# 4. Read the agent prompt to understand requirements
cat /tmp/ralph-parallel/US001/coder-prompt.txt
```

**Common causes**:
- Tests failed (coder didn't write success marker)
- Build errors
- Missing dependencies

#### Scenario 3: Merge Conflicts

**Symptom**: `[MERGE] Failed to merge: 3`

**Debug steps**:
```bash
# 1. Check which branches failed to merge
git branch | grep story-

# 2. Try manual merge to see conflicts
git checkout main
git merge story-US001

# 3. View conflict files
git diff --name-only --diff-filter=U

# 4. Analyze conflict severity
./lib/conflict-analyzer.sh severity <file>
```

**Resolution**:
```bash
# If conflicts are simple:
git checkout main
git merge story-US001
# Edit conflict files
git add .
git commit

# If conflicts are complex:
# Review both versions and merge manually
git diff main story-US001 -- src/components/Header.js
```

#### Scenario 4: Dependency Analysis Failed

**Symptom**: `[ERROR] Circular dependency detected`

**Debug steps**:
```bash
# 1. Visualize dependency graph
./lib/dependency-analyzer.sh prd.json

# 2. Check PRD dependencies manually
jq '.userStories[] | {id: .id, deps: .dependencies}' prd.json

# Output:
{"id": "US001", "deps": []}
{"id": "US002", "deps": ["US001"]}
{"id": "US003", "deps": ["US002", "US001"]}  # ← Circular!
```

**Resolution**: Fix circular dependencies in `prd.json`

### Stories Stuck in Progress
```bash
# Check agent communication directory
ls -la /tmp/ralph-parallel/

# Check for success markers
ls -la /tmp/ralph-parallel/US001/.coder-success
```

### Merge Conflicts
```bash
# View conflict analysis
./lib/conflict-analyzer.sh analyze

# Check specific file severity
./lib/conflict-analyzer.sh severity src/api/users.ts

# Manual resolution
git checkout main
git merge story-US001
# Resolve conflicts
git add .
git commit
```

### Workflow Validation Failed
```bash
# Check available agents
./lib/load-agents.sh

# List available workflows
./lib/workflow-parser.sh list

# Validate specific workflow
./lib/workflow-parser.sh validate my-workflow
```

## Examples

See [examples/](examples/) directory for:
- Simple TODO app PRD
- E-commerce platform PRD
- API service PRD
- Full-stack application PRD

## Contributing

Contributions welcome! Areas for improvement:
- Additional conflict resolution strategies
- New workflow templates
- Performance optimizations
- Better error reporting
- Cross-CLI compatibility

## Documentation

- [QUICKSTART.md](QUICKSTART.md) - Get started in 5 minutes
- [DESIGN.md](docs/DESIGN.md) - Complete design documentation
- [WORKFLOWS.md](docs/WORKFLOWS.md) - Workflow system guide
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - Architecture deep-dive
- [COMPARISON.md](docs/COMPARISON.md) - vs Original Ralph

## License

MIT License - see [LICENSE](LICENSE) for details

## Credits

Built on the foundation of the original Ralph autonomous agent system.

Inspired by:
- Claude Code's Task tool
- Modern CI/CD parallel execution patterns
- Git's merge strategies

## Support

- GitHub Issues: [Report bugs](https://github.com/yourusername/ralph-parallel/issues)
- Discussions: [Ask questions](https://github.com/yourusername/ralph-parallel/discussions)
- Documentation: [Read the docs](docs/)

---

# 中文版本

<div align="center">

<img src="raffaello.png" alt="Raffaello" width="300"/>

# Raffaello 🐢

**并行执行大师** - Ralph 更酷、更快的双胞胎兄弟

*以忍者神龟中戴红色面罩的拉斐尔命名，以速度和双叉攻击闻名*

> [English](#raffaello-) | **中文**

</div>

---

**Raffaello** 是 Ralph 的**并行执行版本** - 新一代自主代理系统，同时执行多个用户故事而非串行。

**Raffaello 解决的问题**：
1. **并行执行** - 同时执行多个用户故事而非串行
2. **子代理利用** - 正确利用专业化代理（planner、coder、reviewer、tester）

## 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/hellangleZ/Raffaello
cd Raffaello

# 2. 确保依赖已安装
brew install jq yq  # JSON 和 YAML 解析

# 3. 创建你的 PRD
cp prd.json.example prd.json
# 编辑 prd.json 添加你的用户故事

# 4. 运行 Ralph Parallel
./ralph.sh
```

查看 [QUICKSTART.md](QUICKSTART.md) 获取详细设置说明。

## 为什么选择 Ralph Parallel？

### 原始 Ralph（串行）
```
迭代 1: 代理 → 故事 1 → passes:true (30 分钟)
迭代 2: 代理 → 故事 2 → passes:true (30 分钟)
迭代 3: 代理 → 故事 3 → passes:true (30 分钟)
总时间: 90 分钟
```

### Ralph Parallel（并行）
```
           ┌→ 代理 A → 故事 1 → passes:true ┐
ralph.sh ──┼→ 代理 B → 故事 2 → passes:true ├→ 自动合并
           └→ 代理 C → 故事 3 → passes:true ┘
总时间: 30 分钟 (快 3 倍!)
```

## 架构概览

Ralph Parallel 使用**三层执行架构**：

### 第 1 层：Batch 级别的并行（ralph.sh）
```
ralph.sh 分析依赖关系并创建批次：

Batch 1 (并行): Story US001, US002, US003  ← 无依赖
Batch 2 (并行): Story US004, US005         ← 依赖 US001
Batch 3 (串行): Story US006                ← 依赖 US004, US005
```

**关键点**：一个 batch 内的 stories **并行**执行（最多 3 个）。Batch 之间**串行**执行。

### 第 2 层：Story 级别的编排（orchestrator.sh）
```
每个 story 有自己的编排器，按顺序管理各个 phase：

Story US001:
  orchestrator.sh US001
    ├─ Phase 1: planner   → 创建 plan.md
    ├─ Phase 2: coder     → 实现代码 + 测试
    ├─ Phase 3: reviewer  → 代码审查
    └─ Phase 4: tester    → 运行 E2E 测试
```

**关键点**：一个 story 内的 phases **串行**执行（一个接一个）。

### 第 3 层：Phase 级别的执行（agents）
```
每个 phase 由专门的 agent 执行：

Phase: coder
  └─ Agent: coder.md
      ├─ 读取 plan.md
      ├─ 编写代码
      ├─ 运行测试
      └─ 写入 .coder-success 标记
```

**关键点**：每个 agent 是自主的，通过 success markers 表示完成。

### 可视化示例：3 个 Stories 并行

```
时间 ──────────────────────────────────────────────────>

ralph.sh 启动 Batch 1:
  │
  ├─ Story US001 (orchestrator.sh US001)
  │   ├─ planner ──> coder ──> reviewer ──> tester ──> ✅
  │
  ├─ Story US002 (orchestrator.sh US002)
  │   ├─ planner ──> coder ──> reviewer ──> tester ──> ✅
  │
  └─ Story US003 (orchestrator.sh US003)
      ├─ planner ──> coder ──> reviewer ──> tester ──> ✅

3 个 orchestrator 并行运行！
但每个 orchestrator 内部的 phases 串行执行。
```

## 项目结构

```
ralph-parallel/
├── ralph.sh                 # 主并行执行引擎
├── orchestrator.sh          # 单个 story 的 phase 管理
├── merge-stories.sh         # 智能 git 合并系统
├── prd.json                 # 你的 PRD 文件
├── progress.txt             # 执行日志
├── lib/
│   ├── detect-cli.sh        # CLI 检测
│   ├── agent-api.sh         # Agent API
│   ├── dependency-analyzer.sh  # DAG 构建器
│   ├── workflow-parser.sh   # YAML 工作流解析器
│   ├── conflict-analyzer.sh # 冲突严重性分级
│   └── load-agents.sh       # Agent 发现
├── agents/
│   ├── planner.md           # 规划 agent
│   ├── coder.md             # 实现 agent
│   ├── reviewer.md          # 代码审查 agent
│   ├── tester.md            # 测试 agent
│   └── conflict-resolver.md # 冲突解决 agent
├── workflows/
│   ├── simple.yaml          # 快速工作流
│   ├── standard.yaml        # 平衡工作流
│   └── full-stack.yaml      # 完整工作流
└── docs/
    ├── DESIGN.md            # 完整设计文档
    ├── WORKFLOWS.md         # 工作流系统指南
    ├── ARCHITECTURE.md      # 架构深入解析
    └── COMPARISON.md        # 与原始 Ralph 的对比
```

## PRD 格式

```json
{
  "projectName": "My Project",
  "branchName": "main",
  "userStories": [
    {
      "id": "US001",
      "title": "User Authentication",
      "description": "Implement user login and registration",
      "workflow": "standard",
      "dependencies": [],
      "passes": false
    },
    {
      "id": "US002",
      "title": "Dashboard UI",
      "description": "Create user dashboard",
      "workflow": "simple",
      "dependencies": ["US001"],
      "passes": false
    }
  ]
}
```

### 关键字段

- **id** - 唯一的 story 标识符
- **title** - 简短的 story 标题
- **description** - 详细需求
- **workflow** - 使用哪个工作流（simple/standard/full-stack）
- **dependencies** - 此 story 依赖的 story ID 数组
- **passes** - 初始设置为 false，Ralph 完成后设置为 true

## 工作原理

### 1. 依赖分析
Ralph 分析你的 PRD 并构建依赖图：
```bash
./lib/dependency-analyzer.sh prd.json
```

Stories 被分组到批次中，每个批次包含独立的 stories。

### 2. 并行执行
Ralph 顺序执行批次，批次内的 stories 并行执行：
```bash
Batch 1: US001, US002, US003（并行）
Batch 2: US004, US005（并行，依赖 US001）
Batch 3: US006（依赖 US004, US005）
```

### 3. Story 编排
对于每个 story，编排器管理 4 个 phase：
```bash
Story US001:
  Phase 1: planner   → 创建 plan.md
  Phase 2: coder     → 实现代码 + 测试
  Phase 3: reviewer  → 审查质量/安全性
  Phase 4: tester    → 运行 E2E 测试
```

### 4. 智能合并
每个 story 完成后，Ralph 将 story 分支合并到 main：
- 分析冲突严重性
- 自动合并 LOW 严重性冲突
- 为 MEDIUM 严重性冲突调用 AI 解决器
- 标记 HIGH 严重性冲突供人工审查

## 核心特性

### 🚀 Story 级别的并行执行
- 同时执行最多 3 个 stories
- 智能依赖分析（基于 DAG）
- 每个 story 独立的 git 分支
- 完成后自动合并

**重要**：并行发生在 **story 级别**，不是 phase 级别。每个 story 的 phases（planner → coder → reviewer → tester）是串行执行的。

### 🤖 Phase 级别的串行编排
每个 story 由编排器管理 4 个专业 agents **按顺序**执行：
- **Planner** - 创建实现计划（Phase 1）
- **Coder** - 遵循 TDD 实现代码（Phase 2）
- **Reviewer** - 审查代码质量和安全性（Phase 3）
- **Tester** - 运行 E2E 测试和验证（Phase 4）

### 🔀 智能冲突解决
三层解决策略：
- **LOW** 严重性 → 自动合并（简单冲突）
- **MEDIUM** 严重性 → AI 解决器（导入冲突、格式化）
- **HIGH** 严重性 → 人工审查（逻辑冲突）

### 📋 灵活的工作流
三种预定义工作流：
- **Simple**（5-10 分钟）- 快速修复和简单功能
- **Standard**（10-20 分钟）- 推荐用于大多数 stories
- **Full-Stack**（20-40 分钟）- 复杂功能和关键路径

查看 [WORKFLOWS.md](docs/WORKFLOWS.md) 了解自定义工作流。

### 🔧 CLI 要求
仅支持：
- Claude Code CLI（已安装并配置）
- 通过 Task 工具执行 Agent

## 项目结构

**重要**：工作流定义单个 story 内 phases 的**串行执行顺序**。它们不控制并行性（并行发生在 story 级别）。

### 工作流如何工作

工作流只是按顺序执行的 phases 列表：

```yaml
# workflows/standard.yaml
phases:
  - planner    # 步骤 1：首先执行
  - coder      # 步骤 2：planner 成功后执行
  - reviewer   # 步骤 3：coder 成功后执行
  - tester     # 步骤 4：reviewer 成功后执行
```

**单个 story 的执行流程**：
```
orchestrator.sh US001
  ├─ 读取工作流：standard.yaml
  ├─ 执行 phase 1: planner   (等待成功)
  ├─ 执行 phase 2: coder     (等待成功)
  ├─ 执行 phase 3: reviewer  (等待成功)
  └─ 执行 phase 4: tester    (等待成功)
```

如果任何 phase 失败，编排器会根据 `retry_policy` 重试，如果达到最大尝试次数则停止。

### 简单工作流（最快）
```yaml
name: simple
phases:
  - coder      # 跳过规划，直接实现
  - tester     # 运行测试验证

retry_policy:
  coder:
    max_attempts: 2
  tester:
    max_attempts: 1
```
**适用于**：Bug 修复、简单功能、低风险变更

**执行时间**：每个 story 约 5-10 分钟

### 标准工作流（推荐）
```yaml
name: standard
phases:
  - planner    # 创建实现计划
  - coder      # 按计划实现
  - reviewer   # 审查代码质量和安全性
  - tester     # 运行 E2E 测试

retry_policy:
  planner:
    max_attempts: 1
  coder:
    max_attempts: 2    # 如果实现失败允许重试
  reviewer:
    max_attempts: 2    # 如果审查发现问题允许重试
  tester:
    max_attempts: 1
```
**适用于**：大多数用户故事、新功能、重构

**执行时间**：每个 story 约 10-20 分钟

### 全栈工作流（完整）
```yaml
name: full-stack
phases:
  - planner              # 创建计划
  - architect            # 设计系统架构（可选 agent）
  - frontend-coder       # 实现前端（可选 agent）
  - backend-coder        # 实现后端（可选 agent）
  - reviewer             # 代码审查
  - security-reviewer    # 安全审计（可选 agent）
  - ui-tester           # UI 测试（可选 agent）
  - integration-tester  # 集成测试（可选 agent）

retry_policy:
  # ...（每个 phase 都有 max_attempts）
```
**适用于**：复杂功能、多层变更、关键路径

**执行时间**：每个 story 约 20-40 分钟

**注意**：可选 agents（architect、frontend-coder 等）必须存在于 `~/.claude/agents/` 目录中。如果找不到，工作流将失败。

### 理解 retry_policy

```yaml
retry_policy:
  coder:
    max_attempts: 2
```

这意味着：
- 尝试 1：运行 coder agent
  - 如果**存在成功标记** → 继续下一个 phase
  - 如果**没有成功标记** → 重试
- 尝试 2：再次运行 coder agent
  - 如果**存在成功标记** → 继续
  - 如果**没有成功标记** → **Story 失败**，停止编排

### 自定义工作流

你可以创建自己的工作流 YAML 文件：

```yaml
# workflows/my-custom.yaml
name: my-custom
description: 我的项目的自定义工作流
phases:
  - planner
  - my-custom-agent  # 必须存在于 ~/.claude/agents/my-custom-agent.md
  - coder
  - tester

retry_policy:
  planner:
    max_attempts: 1
  my-custom-agent:
    max_attempts: 1
  coder:
    max_attempts: 2
  tester:
    max_attempts: 1
```

然后在你的 PRD 中引用它：
```json
{
  "id": "US001",
  "workflow": "my-custom",
  ...
}
```

查看 [WORKFLOWS.md](docs/WORKFLOWS.md) 了解自定义工作流创建。

## 冲突解决

三层解决策略基于冲突严重性：

### 第 1 层：自动合并（LOW 严重性）
**标准**：冲突比率 < 5%，无逻辑冲突

**策略**：使用 `git checkout --ours` 或 `--theirs`

**示例**：
```diff
<<<<<<< HEAD
import { A } from './a';
=======
import { B } from './b';
>>>>>>> story-US002

解决后：
import { A } from './a';
import { B } from './b';
```

### 第 2 层：AI 解决器（MEDIUM 严重性）
**标准**：冲突比率 5-20%，多个小冲突

**策略**：生成 `conflict-resolver` agent

**示例**：两个 story 都添加函数
```javascript
// 冲突：都添加函数
<<<<<<< HEAD
function validateEmail(email) { ... }
=======
function validatePassword(pwd) { ... }
>>>>>>> story-US002

// 解决后：保留两个
function validateEmail(email) { ... }
function validatePassword(pwd) { ... }
```

### 第 3 层：人工审查（HIGH 严重性）
**标准**：冲突比率 > 20%，逻辑冲突

**策略**：停止合并，通知用户

**要求**：手动解决冲突并提交

## 配置

### 环境变量

```bash
# 最大并行 stories（默认：3）
export MAX_PARALLEL_STORIES=3

# Agent 通信目录（默认：/tmp/ralph-parallel）
export AGENT_COMM_DIR="/tmp/ralph-parallel"

# 工作流目录（默认：./workflows）
export WORKFLOW_DIR="./workflows"
```

### CLI 检测

系统自动检测 Claude Code CLI：

```bash
# 检测已安装的 CLI
./lib/detect-cli.sh

# 输出：claude-code
# → 使用 Task 工具进行 agent 管理
```

## 命令

### 主要命令

```bash
# 运行 Ralph Parallel（执行所有未完成的 stories）
./ralph.sh

# 运行特定 story
./orchestrator.sh US001
```

### 实用命令

```bash
# 验证 PRD 格式
jq empty prd.json  # 有效则无输出

# 检查依赖关系
./lib/dependency-analyzer.sh prd.json

# 列出可用的 agents
./lib/load-agents.sh

# 列出可用的工作流
ls workflows/*.yaml

# 验证工作流格式
yq eval workflows/standard.yaml

# 清理临时文件
rm -rf /tmp/ralph-parallel/*

# 查看所有 story 分支
git branch | grep story-
```

## 与原始 Ralph 对比

| 功能 | 原始 Ralph | Ralph Parallel |
|------|------------|----------------|
| 执行模式 | 串行（一次一个 story） | 并行（同时最多 3 个 stories） |
| 执行时间 | N × 时间/story | 时间/story（如果独立） |
| 分支策略 | 单个工作分支 | 每个 story 独立分支 |
| 冲突处理 | 手动 | 三层（AUTO/AI/MANUAL） |
| Agent 角色 | 单角色 | 多角色（planner/coder/reviewer/tester） |
| 工作流 | 固定 | 可配置 YAML |
| 并发限制 | 1 | 可配置（默认 3） |

## 系统要求

- **Bash**: 3.2+（macOS 兼容）
- **jq**: JSON 解析（`brew install jq`）
- **yq**: YAML 解析（`brew install yq`）
- **git**: 版本控制
- **Claude Code CLI**: AI 执行引擎

## 已知问题

### 问题 1: `wait -n` 在 Bash 3.2 中不支持（仅 macOS）

**症状**：执行时出现警告信息：
```
wait: -n: invalid option
wait: usage: wait [n]
```

**影响**：无 - 功能完全正常。并行执行仍然正确工作。

**解释**：
- macOS 自带 Bash 3.2（2007 年发布），不支持 `wait -n`
- 系统使用备用方法，等待 batch 中所有 stories 完成
- **Ubuntu/Linux 用户**：不会出现此警告（Bash 5.0+ 支持 `wait -n`）

**解决方法**：忽略警告，或升级 Bash：
```bash
brew install bash
# 然后使用 /opt/homebrew/bin/bash 而不是 /bin/bash
```

### 问题 2: 在 story 分支时自动合并可能失败

**症状**：执行结束时出现合并错误：
```
[MERGE] Failed to checkout main
[MERGE] Failed to merge: 4
```

**影响**：所有 stories 成功完成并提交到各自分支。只有自动合并到 main 失败。

**原因**：如果 ralph.sh 结束时你在 story 分支（如 `story-US001`），自动合并脚本无法切换到 `main`。

**解决方法**：手动合并 story 分支：
```bash
git checkout main

# 合并每个 story 分支
git merge story-US001
git merge story-US002
git merge story-US003

# 删除 story 分支（可选）
git branch -d story-US001 story-US002 story-US003
```

**预防**：运行 `./ralph.sh` 前确保在 `main` 分支

## 限制

### 当前限制
1. **并行限制**：最多 3 个 stories 以避免 API 速率限制
2. **手动冲突**：高严重性冲突需要人工干预
3. **无跨 story 通信**：Stories 在执行期间无法协调
4. **文件级粒度**：冲突检测在文件级别

### 计划改进
- Token 成本优化（对 planner/reviewer 使用 Haiku）
- 跨 story 文件锁定
- 更细粒度的冲突检测
- 失败合并的回滚支持

## 故障排除和调试

### 理解日志输出

Ralph Parallel 产生带颜色前缀的日志：

```bash
[INFO]         # 一般信息（蓝色）
[SUCCESS]      # 成功操作（绿色）
[WARN]         # 警告（黄色）
[ERROR]        # 错误（红色）
[ORCHESTRATOR] # 编排器级别消息（蓝色）
[MERGE]        # 合并相关消息（蓝色/红色）
```

### 查看实时日志

Ralph Parallel 实时输出日志到 stdout：

```bash
./ralph.sh

# 输出：
[INFO] === Ralph Parallel - 开始执行 ===
[INFO] 找到 4 个未完成的 stories
[INFO] 分析依赖关系...
[INFO] 执行计划：2 个批次

[INFO] === Batch 1 / 2 ===
[INFO] 启动 story: US001 - Add Header Component
[ORCHESTRATOR] 开始编排 story: US001
[ORCHESTRATOR] 执行 phase: coder (最大尝试次数: 2)
...
```

### 检查 Story 进度

每个 story 将输出写入 agent 通信目录：

```bash
# 列出所有活动的 stories
ls -la /tmp/ralph-parallel/

# 输出：
drwxr-xr-x  US001/
drwxr-xr-x  US002/
drwxr-xr-x  US003/

# 检查特定 story 完成的 phases
ls -la /tmp/ralph-parallel/US001/

# 输出：
-rw-r--r--  .planner-success   # ✅ Planner 完成
-rw-r--r--  .coder-success     # ✅ Coder 完成
-rw-r--r--  .reviewer-success  # ✅ Reviewer 完成
(缺少 .tester-success)         # ❌ Tester 仍在运行
```

### 检查 PRD 状态

`prd.json` 文件实时更新：

```bash
# 检查哪些 stories 已完成
jq '.userStories[] | select(.passes == true) | .id' prd.json

# 输出：
"US001"
"US002"

# 检查哪些 stories 仍在等待
jq '.userStories[] | select(.passes == false) | .id' prd.json

# 输出：
"US003"
"US004"
```

### 检查 Git 分支

每个 story 创建自己的 git 分支：

```bash
# 列出所有 story 分支
git branch | grep story-

# 输出：
  story-US001
  story-US002
  story-US003

# 检查 story 分支上的提交
git log story-US001 --oneline

# 输出：
a1b2c3d feat: US001 - Add Header Component
e4f5g6h (main) 之前的提交

# 查看 story 分支中的更改
git diff main...story-US001
```

## 示例

查看 [examples/](examples/) 目录了解：
- 简单 TODO 应用 PRD
- 电子商务平台 PRD
- API 服务 PRD
- 全栈应用 PRD

## 贡献

欢迎贡献！改进领域：
- 额外的冲突解决策略
- 新的工作流模板
- 性能优化
- 更好的错误报告
- 跨 CLI 兼容性

## 文档

- [QUICKSTART.md](QUICKSTART.md) - 5 分钟快速开始
- [DESIGN.md](docs/DESIGN.md) - 完整设计文档
- [WORKFLOWS.md](docs/WORKFLOWS.md) - 工作流系统指南
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - 架构深度解析
- [COMPARISON.md](docs/COMPARISON.md) - 与原始 Ralph 对比

## 许可证

MIT License - 查看 [LICENSE](LICENSE) 了解详情

## 致谢

建立在原始 Ralph 自主代理系统的基础上。

灵感来源：
- Claude Code 的 Task 工具
- 现代 CI/CD 并行执行模式
- Git 的合并策略

## 支持

- GitHub Issues: [报告 bug](https://github.com/yourusername/ralph-parallel/issues)
- Discussions: [提问](https://github.com/yourusername/ralph-parallel/discussions)
- 文档: [阅读文档](docs/)

---

**Ralph Parallel** - 自主代理，并行执行 🚀
