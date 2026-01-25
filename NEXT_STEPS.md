# Ralph Parallel - Next Steps

## Current Status: 89% Complete ✅

**What's Done**:
- ✅ All core architecture (parallel execution, DAG, git branching, workflows, merging)
- ✅ Comprehensive documentation (2500+ lines)
- ✅ Automated testing (18 tests)
- ✅ Bug fixes (4 critical bugs resolved)
- ✅ Bash 3.2 compatibility
- ✅ CLI abstraction (Claude Code + Codex)

**What's Left**: Agent integration completion (11%)

---

## Option 1: Complete Claude Code Integration (2-3 hours)

### Step 1: Update Agent Prompts

Add success marker instructions to all agent files:

#### agents/coder.md
Add at the end:
```markdown
## 🎯 Success Marker

**CRITICAL**: After successfully completing all work and committing code, write the success marker:

```bash
mkdir -p "$COMMUNICATION_DIRECTORY"
echo "success" > "$COMMUNICATION_DIRECTORY/.coder-success"
```

**DO NOT** write the marker if:
- ❌ Tests failed
- ❌ Build failed
- ❌ Code not committed
- ❌ Quality checks failed

**Example**:
```bash
# After git commit succeeds
mkdir -p /tmp/ralph-parallel/US001
echo "success" > /tmp/ralph-parallel/US001/.coder-success
```
```

#### agents/planner.md
Add at the end:
```markdown
## 🎯 Success Marker

After creating the implementation plan (`plan.md`), write the success marker:

```bash
mkdir -p "$COMMUNICATION_DIRECTORY"
echo "success" > "$COMMUNICATION_DIRECTORY/.planner-success"
```
```

#### agents/reviewer.md
Add at the end:
```markdown
## 🎯 Success Marker

After completing code review (APPROVED or CHANGES_REQUESTED), write the success marker:

```bash
mkdir -p "$COMMUNICATION_DIRECTORY"
echo "success" > "$COMMUNICATION_DIRECTORY/.reviewer-success"
```

Note: Write the marker even if requesting changes - the orchestrator will handle retry logic.
```

#### agents/tester.md
Add at the end:
```markdown
## 🎯 Success Marker

After running all tests and generating the test report, write the success marker:

```bash
mkdir -p "$COMMUNICATION_DIRECTORY"
echo "success" > "$COMMUNICATION_DIRECTORY/.tester-success"
```
```

### Step 2: Fix Agent Output Retrieval

Update `lib/agent-api.sh` function `get_agent_output()`:

```bash
# Get agent output
# Args: $1=story_id, $2=agent_name, $3=agent_id (optional)
get_agent_output() {
  local story_id=$1
  local agent_name=$2
  local agent_id=${3:-}
  local output_file="$AGENT_COMM_DIR/$story_id/${agent_name}-output.txt"

  # If agent_id is a Claude Code task, retrieve from task output
  if [[ "$agent_id" =~ ^cc-task-([a-f0-9]+)$ ]]; then
    local task_id="${BASH_REMATCH[1]}"
    claude task output "$task_id" 2>/dev/null || true
  elif [[ -f "$output_file" ]]; then
    cat "$output_file"
  fi
}
```

Update orchestrator.sh line 166 to pass agent_id:
```bash
output=$(get_agent_output "$STORY_ID" "$phase" "$agent_id")
```

### Step 3: Handle Interactive Approval

Agents currently wait for user approval. Update agent prompts to be fully autonomous:

Add to all agent prompts after the success marker section:
```markdown
## 🤖 Autonomous Mode

You are running in **autonomous mode**. DO NOT wait for user approval.

**When you're done**:
1. ✅ Commit your changes immediately
2. ✅ Write the success marker
3. ✅ Exit (do not ask for approval)

**No user interaction expected** - proceed directly to completion.
```

### Step 4: Test End-to-End

```bash
cd /Users/chilikevin/aml/ralph-parallel/test-project
rm -rf /tmp/ralph-parallel
bash -c 'export PRD_FILE="$PWD/prd.json"; export PROGRESS_FILE="$PWD/progress.txt"; exec ../ralph.sh'
```

Expected outcome:
- ✅ All 3 stories complete successfully
- ✅ Success markers written
- ✅ PRD updated with `passes: true`
- ✅ Git commits created
- ✅ Branches merged

---

## Option 2: Use Codex (30 minutes)

Codex has native multi-agent support and should work **out of the box**.

### Prerequisites
1. Install Codex CLI
2. Enable multi-agents in `~/.codex/config.toml`:
   ```toml
   [features]
   multi-agents = true
   ```

### Test
```bash
cd /Users/chilikevin/aml/ralph-parallel/test-project
bash -c 'export PRD_FILE="$PWD/prd.json"; export PROGRESS_FILE="$PWD/progress.txt"; exec ../ralph.sh'
```

Codex's `spawn_agent` API handles:
- ✅ Agent lifecycle management
- ✅ Task completion detection
- ✅ Output retrieval
- ✅ Cleanup

**No agent prompt updates needed** for Codex!

---

## Option 3: Build Custom MCP Server (4-6 hours)

Create a Claude Code MCP server specifically for multi-agent orchestration.

**Server capabilities**:
- `spawn_agent(prompt, role)` → Returns agent_id
- `wait_agent(agent_id)` → Blocks until complete
- `get_agent_output(agent_id)` → Returns output
- `check_agent_success(agent_id)` → Returns true/false

**Implementation**:
1. Create MCP server using TypeScript/Python
2. Integrate with Claude Code's task system
3. Register server in `~/.claude/mcp.json`
4. Update `lib/agent-api.sh` to use MCP tools

**Benefits**:
- Native multi-agent support for Claude Code
- Reusable across projects
- Clean API abstraction

**Drawbacks**:
- Most time-consuming
- Requires MCP SDK knowledge
- Maintenance overhead

---

## Recommendation

### 🥇 Best for Quick Win: Option 1 (Update Agent Prompts)
- 2-3 hours of work
- Validates the full system
- Works with Claude Code (what you're using now)
- No additional dependencies

### 🥈 Best for Production: Option 2 (Use Codex)
- 30 minutes setup
- Battle-tested multi-agent API
- Zero agent prompt updates needed
- Designed for this use case

### 🥉 Best for Long-Term: Option 3 (MCP Server)
- 4-6 hours initial investment
- Cleanest architecture
- Reusable across projects
- Future-proof

---

## Quick Start Commands

### For Option 1:
```bash
# 1. Update agent prompts (manual editing)
vim agents/coder.md  # Add success marker section
vim agents/planner.md
vim agents/reviewer.md
vim agents/tester.md

# 2. Update get_agent_output in lib/agent-api.sh

# 3. Test
cd test-project && bash -c 'export PRD_FILE="$PWD/prd.json"; export PROGRESS_FILE="$PWD/progress.txt"; exec ../ralph.sh'
```

### For Option 2:
```bash
# 1. Install Codex
# (Follow Codex installation instructions)

# 2. Enable multi-agents
echo -e "[features]\nmulti-agents = true" >> ~/.codex/config.toml

# 3. Test
cd test-project && bash -c 'export PRD_FILE="$PWD/prd.json"; export PROGRESS_FILE="$PWD/progress.txt"; exec ../ralph.sh'
```

---

## Validation Checklist

After completing any option, verify:

- [ ] All 3 stories in test PRD complete successfully
- [ ] Success markers written to `/tmp/ralph-parallel/US*/.*-success`
- [ ] PRD updated: all stories have `passes: true`
- [ ] Git commits created for each story
- [ ] Branches merged to main
- [ ] No errors in ralph-execution.log
- [ ] progress.txt updated with story completions

---

## Support

**Documentation**:
- `README.md` - Project overview
- `QUICKSTART.md` - 5-minute onboarding
- `docs/ARCHITECTURE.md` - Deep technical details
- `TESTING_RESULTS.md` - Current test status
- `docs/COMPARISON.md` - vs original Ralph

**Questions?**
- Review TESTING_RESULTS.md for known issues
- Check ARCHITECTURE.md for design decisions
- Read agent prompts in `agents/` for examples

---

**Ralph Parallel** - Ready for the final 11%! 🚀
