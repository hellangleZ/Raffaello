# Ralph Parallel - Design Document

> **English** | [中文](#中文版本)

## Project Background

This project aims to create a new Multi-Agent version of Ralph, solving two key problems with the current version:

1. **Parallel story execution** - Instead of sequential execution
2. **Full utilization of subagents** - Current burn-in-cceverywhere-ralph agents (architect, planner, code-reviewer, etc.) are not used in the Ralph scenario

## Core Innovation

### From Sequential to Parallel

**Current Ralph (Sequential)**:
```
Iteration 1: Agent → Story 1 → passes:true
Iteration 2: Agent → Story 2 → passes:true
Iteration 3: Agent → Story 3 → passes:true
```

**Multi-Agent Ralph (Parallel)**:
```
           ┌→ Agent A → Story 1 → passes:true ┐
ralph.sh ──┼→ Agent B → Story 2 → passes:true ├→ Auto-merge
           └→ Agent C → Story 3 → passes:true ┘
```

### Proper Use of Subagents

**Current Problem Analysis**:
- Existing subagents (architect, planner, code-reviewer, etc.) exist in `~/.claude/agents/` or `~/.codex/agents/`
- But Ralph's CLAUDE.md instructions never call them
- Ralph is a "single-role agent": only does implementation, no role separation

**Multi-Agent Ralph Role Division**:
```
Story 1 requires 4 phases:
  1. planner agent    → Generate implementation plan
  2. coder agent      → Implement code
  3. reviewer agent   → Code review
  4. tester agent     → E2E testing
```

Each story is managed by an **orchestrator** that controls 4 phase subagents!

## Project Name and Architecture

### Project Name

**`ralph-parallel`**

Rationale:
- Simple and clear
- Highlights core feature (parallel execution)
- Consistent with original project naming style

### Directory Structure

```
/Users/chilikevin/aml/ralph-parallel/
├── ralph.sh              # Parallel version main loop
├── orchestrator.sh       # Single story orchestrator (manages subagents)
├── merge-stories.sh      # Auto-merge multiple story git branches
├── prd.json              # PRD file (compatible with old format)
├── progress.txt          # Progress log
├── agents/
│   ├── planner.md        # Planning agent (generate implementation plan)
│   ├── coder.md          # Implementation agent (write code)
│   ├── reviewer.md       # Review agent (code review)
│   └── tester.md         # Testing agent (E2E testing)
├── workflows/
│   ├── simple.yaml       # Simple story workflow (coder only)
│   ├── standard.yaml     # Standard story workflow (all 4 phases)
│   └── ui.yaml           # UI story workflow (includes browser testing)
└── docs/
    ├── ARCHITECTURE.md   # Architecture documentation
    ├── WORKFLOWS.md      # Workflow guide
    └── COMPARISON.md     # Comparison with original Ralph
```

## Core Design

### 1. Parallel Execution Engine

**ralph.sh Logic**:
```bash
# Read prd.json
stories=$(jq -r '.userStories[] | select(.passes == false) | .id' prd.json)

# Identify parallelizable stories (no dependencies)
parallel_stories=$(analyze_dependencies "$stories")

# Parallel execution (max 3 concurrent, avoid API rate limits)
for story in $parallel_stories; do
  (
    # Create independent git branch for each story
    git checkout -b "story-$story"

    # Call orchestrator to manage this story's 4 phases
    ./orchestrator.sh "$story"

    # Commit to branch
    git commit -am "feat: Story $story - [Title]"
  ) &
done

# Wait for all parallel tasks to complete
wait

# Auto-merge all story branches to main
./merge-stories.sh
```

### 2. Orchestrator (Story Manager)

**orchestrator.sh**:
```bash
story_id=$1

# Read story's workflow type
workflow=$(get_story_workflow "$story_id")

# Load corresponding workflow config
source "workflows/${workflow}.yaml"

# Execute workflow-defined phases
for phase in "${phases[@]}"; do
  agent="${phase}_agent"

  # Call Claude Code, pass corresponding agent instructions
  claude --agent "$agent" < "agents/${agent}.md"

  # Check if phase passed
  if ! check_phase_success; then
    echo "Phase $phase failed for story $story_id"
    exit 1
  fi
done

# All phases passed, mark story complete
update_prd "$story_id" "passes:true"
```

### 3. Subagent Role Definitions

#### planner.md (Planning Agent)
```markdown
# Planner Agent

You are a planning specialist. Your job:

1. Read the user story description
2. Analyze technical requirements
3. Create a step-by-step implementation plan
4. Identify dependencies and risks
5. Write plan to `plan.md`

DO NOT implement code. Only create the plan.
```

#### coder.md (Implementation Agent)
```markdown
# Coder Agent

You are an implementation specialist. Your job:

1. Read `plan.md` created by planner
2. Implement the code following the plan
3. Write unit tests (TDD)
4. Ensure all tests pass

Output: Commit with implemented code and tests.
```

#### reviewer.md (Review Agent)
```markdown
# Code Reviewer Agent

You are a code review specialist. Your job:

1. Review the code committed by coder
2. Check for:
   - Code quality issues
   - Security vulnerabilities
   - Best practices violations
3. Either:
   - Approve: Create `review-approved.txt`
   - Request changes: Create `review-changes.txt` with feedback

If changes requested, coder will fix and resubmit.
```

#### tester.md (Testing Agent)
```markdown
# E2E Tester Agent

You are an end-to-end testing specialist. Your job:

1. Run full E2E tests for this story
2. Verify UI changes in browser (if applicable)
3. Create test report in `e2e-report.md`

Output: Either `e2e-passed.txt` or `e2e-failed.txt`.
```

### 4. Dependency Analysis

**analyze_dependencies()**:
```bash
# Read dependencies field from prd.json
# Build DAG (Directed Acyclic Graph)
# Identify parallelizable stories

# Example:
# Story 1: [] (no deps) → Can start immediately
# Story 2: [1] (depends on 1) → Wait for Story 1
# Story 3: [] (no deps) → Can run parallel with Story 1
```

### 5. Auto-Merge Strategy

**merge-stories.sh**:
```bash
# Strategy 1: Rebase + Fast-forward (cleanest)
for branch in story-*; do
  git checkout main
  git merge --ff-only "$branch" || handle_conflict
done

# Strategy 2: Conflict handling
handle_conflict() {
  # Call conflict-resolver agent
  claude --agent conflict-resolver < agents/conflict-resolver.md
}
```

### 6. Workflow Configuration (YAML Format)

**workflows/standard.yaml**:
```yaml
name: standard
phases:
  - planner
  - coder
  - reviewer
  - tester

retry_policy:
  reviewer:
    max_attempts: 2  # Coder can fix up to 2 times
  tester:
    max_attempts: 1  # E2E failure doesn't retry (needs debug)
```

**workflows/simple.yaml**:
```yaml
name: simple
phases:
  - coder  # Skip planner (simple tasks)
  - tester # Skip reviewer (low risk)
```

## Technical Challenges

### Challenge 1: Git Concurrent Conflicts

**Problem**: Multiple stories may modify the same file

**Solutions**:
1. **Dependency analysis** - If two stories modify same file, execute serially
2. **File-level locking** - Mark files modified by each story in prd.json
3. **Conflict-resolver agent** - AI resolves merge conflicts

### Challenge 2: API Rate Limits

**Problem**: Too many parallel calls exceed API limits

**Solutions**:
- Limit max 3 parallel stories
- Implement exponential backoff retry strategy

### Challenge 3: Token Costs

**Problem**: Parallel execution increases token costs

**Solutions**:
- Each agent uses smaller context (specialized instructions)
- Prioritize Haiku over Opus (planner, reviewer can use Haiku)

### Challenge 4: Subagent Communication

**Problem**: planner → coder → reviewer need to pass information

**Solutions**:
- Use file system as communication medium (`plan.md`, `review-feedback.txt`)
- Or use Claude Code's Task system (if supported)

## Comparison Analysis

| Feature | Original Ralph | Multi-Agent Ralph |
|---------|---------------|-------------------|
| Execution Mode | Sequential | Parallel |
| Agent Count | 1 (repeated calls) | N (concurrent) |
| Subagents | Not used | Fully utilized |
| Speed | Slow (serial) | Fast (parallel) |
| Complexity | Low | Medium-High |
| Conflict Handling | None (serial = no conflicts) | Needs conflict-resolver |
| Use Case | Small projects | Large projects |

## Detailed Implementation Design

### CLI Detection and Adaptation Layer

**detect-cli.sh**:
```bash
detect_cli() {
  if command -v claude &> /dev/null; then
    echo "claude-code"
  elif command -v codex &> /dev/null; then
    echo "codex"
  else
    echo "ERROR: Neither Claude Code nor Codex CLI found"
    exit 1
  fi
}

# Check multi-agents support
check_multiagents_support() {
  local cli=$1
  if [[ "$cli" == "claude-code" ]]; then
    # Claude Code always supports Task tool
    return 0
  elif [[ "$cli" == "codex" ]]; then
    # Check Codex config.toml
    if grep -q "multi-agents = true" ~/.codex/config.toml 2>/dev/null; then
      return 0
    else
      echo "Add to ~/.codex/config.toml:"
      echo "[features]"
      echo "multi-agents = true"
      exit 1
    fi
  fi
  return 1
}
```

### Unified Agent Calling Interface

**agent-api.sh**:
```bash
# Unified agent spawn interface
spawn_agent() {
  local cli=$1
  local agent_name=$2
  local task_message=$3
  local agent_prompt_file="agents/${agent_name}.md"

  if [[ "$cli" == "claude-code" ]]; then
    # Claude Code: Use Task tool
    # Combine agent instructions and task message
    local full_prompt="$(<$agent_prompt_file)\n\nTask: $task_message"

    # Call Claude Code (Task tool auto-manages state)
    claude --print <<EOF
$full_prompt
EOF

  elif [[ "$cli" == "codex" ]]; then
    codex <<EOF
{
  "tool": "spawn_agent",
  "message": "$(cat $agent_prompt_file)\n\nTask: $task_message",
  "agent_type": "worker"
}
EOF
  fi
}

# Wait for agents to complete
wait_for_agents() {
  local cli=$1
  shift
  local agent_ids=("$@")

  if [[ "$cli" == "claude-code" ]]; then
    # Claude Code: Task tool auto-manages, no explicit wait needed
    :
  elif [[ "$cli" == "codex" ]]; then
    # Codex: Call wait API
    local ids_json=$(printf '%s\n' "${agent_ids[@]}" | jq -R . | jq -s .)
    codex <<EOF
{
  "tool": "wait",
  "agent_ids": $ids_json
}
EOF
  fi
}
```

### Dynamic Agent Loading

**load-agents.sh**:
```bash
# Load core agents (built-in)
CORE_AGENTS=("planner" "coder" "reviewer" "tester")

# Discover optional agents (from user config)
discover_optional_agents() {
  local cli=$1
  local agent_dir=""

  if [[ "$cli" == "claude-code" ]]; then
    agent_dir="$HOME/.claude/agents"
  elif [[ "$cli" == "codex" ]]; then
    agent_dir="$HOME/.codex/agents"
  fi

  # List all .md files (exclude core agents)
  if [[ -d "$agent_dir" ]]; then
    find "$agent_dir" -name "*.md" | while read -r file; do
      local agent_name=$(basename "$file" .md)
      # Exclude core agents
      if [[ ! " ${CORE_AGENTS[@]} " =~ " ${agent_name} " ]]; then
        echo "$agent_name"
      fi
    done
  fi
}

# Validate workflow agents exist
validate_workflow_agents() {
  local workflow_file=$1
  local cli=$2

  # Read phases from workflow
  local phases=$(yq '.phases[]' "$workflow_file")

  # Discover all available agents
  local available_agents=("${CORE_AGENTS[@]}")
  while IFS= read -r agent; do
    available_agents+=("$agent")
  done < <(discover_optional_agents "$cli")

  # Validate each phase's agent exists
  while IFS= read -r phase_agent; do
    if [[ ! " ${available_agents[@]} " =~ " ${phase_agent} " ]]; then
      echo "ERROR: Agent '$phase_agent' not found"
      echo "Available agents: ${available_agents[*]}"
      exit 1
    fi
  done <<< "$phases"
}
```

### Conflict Grading and Handling

**merge-conflict-resolver.sh**:
```bash
analyze_conflict_severity() {
  local file=$1

  # Analyze conflict markers
  local conflict_sections=$(grep -c "^<<<<<< " "$file" || echo 0)
  local file_size=$(wc -l < "$file")
  local conflict_ratio=$((conflict_sections * 100 / file_size))

  # Check conflict type
  local has_logic_conflict=$(grep -E "(function|class|if|while|for)" "$file" | grep -c "^<<<<<<" || echo 0)

  if [[ $has_logic_conflict -gt 0 ]]; then
    echo "HIGH"  # Logic conflict, needs manual review
  elif [[ $conflict_ratio -gt 20 ]]; then
    echo "HIGH"  # Too many conflicts, needs manual review
  elif [[ $conflict_ratio -gt 5 ]]; then
    echo "MEDIUM"  # Medium conflict, AI handles
  else
    echo "LOW"  # Simple conflict, auto-merge
  fi
}

handle_merge_conflict() {
  local cli=$1
  local file=$2
  local severity=$(analyze_conflict_severity "$file")

  case $severity in
    LOW)
      echo "Auto-merging $file (simple conflict)"
      # Use git rerere or simple strategy
      git checkout --ours "$file"  # or --theirs, based on strategy
      git add "$file"
      ;;
    MEDIUM)
      echo "AI resolving $file (medium conflict)"
      # Call conflict-resolver agent
      spawn_agent "$cli" "conflict-resolver" "Resolve merge conflict in $file"
      ;;
    HIGH)
      echo "MANUAL REVIEW REQUIRED for $file (complex conflict)"
      echo "  Conflict file: $file"
      echo "  Use: git mergetool $file"
      return 1  # Block auto-continue
      ;;
  esac
}
```

### Workflow YAML Parser

**workflow-parser.sh**:
```bash
parse_workflow() {
  local workflow_file=$1

  # Use yq to parse YAML
  WORKFLOW_NAME=$(yq '.name' "$workflow_file")
  WORKFLOW_PHASES=($(yq '.phases[]' "$workflow_file"))

  # Parse retry policy
  for phase in "${WORKFLOW_PHASES[@]}"; do
    local max_attempts=$(yq ".retry_policy.$phase.max_attempts // 1" "$workflow_file")
    RETRY_POLICY[$phase]=$max_attempts
  done
}

execute_workflow() {
  local story_id=$1
  local workflow_file=$2
  local cli=$3

  parse_workflow "$workflow_file"

  echo "Executing workflow: $WORKFLOW_NAME for story $story_id"

  for phase in "${WORKFLOW_PHASES[@]}"; do
    local max_attempts=${RETRY_POLICY[$phase]:-1}
    local attempt=1
    local success=false

    while [[ $attempt -le $max_attempts ]]; do
      echo "  Phase: $phase (attempt $attempt/$max_attempts)"

      # Call agent
      spawn_agent "$cli" "$phase" "Execute $phase for story $story_id"

      # Check success marker file
      if [[ -f ".ralph-phase-$phase-success" ]]; then
        success=true
        rm ".ralph-phase-$phase-success"
        break
      fi

      ((attempt++))
    done

    if [[ $success == false ]]; then
      echo "  Phase $phase FAILED after $max_attempts attempts"
      return 1
    fi
  done

  echo "Workflow completed successfully for story $story_id"
  return 0
}
```

## Implementation Plan

### Phase 1: Project Skeleton and CLI Adaptation ✅
**Time**: 1-2 hours

1. ✅ Create project directory `/Users/chilikevin/aml/ralph-parallel/`
2. ✅ Implement `detect-cli.sh` - CLI detection
3. ✅ Implement `agent-api.sh` - Unified agent calling interface
4. ✅ Implement `load-agents.sh` - Dynamic agent loading
5. ✅ Create 4 core agent instruction files
6. ✅ Test CLI detection and agent loading

### Phase 2: Core Parallel Engine
**Time**: 2-3 hours

1. Implement `ralph.sh` - Main loop (parallel execution)
2. Implement `orchestrator.sh` - Single story phase management
3. Implement `dependency-analyzer.sh` - Dependency analysis
4. Implement Git branch management logic
5. Test parallel execution of 2-3 independent stories

### Phase 3: Workflow System
**Time**: 1-2 hours

1. Implement `workflow-parser.sh` - YAML parsing
2. Create 3 predefined workflows:
   - `simple.yaml` - Minimal (coder + tester)
   - `standard.yaml` - Standard (all 4 core agents)
   - `full-stack.yaml` - Complete (includes optional agents)
3. Test workflow loading and execution

### Phase 4: Merge Strategy
**Time**: 2-3 hours

1. Implement `merge-stories.sh` - Auto-merge
2. Implement `merge-conflict-resolver.sh` - Conflict grading
3. Create `conflict-resolver` agent
4. Test various conflict scenarios:
   - No conflict (fast-forward)
   - Simple conflict (auto-merge)
   - Medium conflict (AI resolver)
   - Complex conflict (manual review)

### Phase 5: Documentation and Examples
**Time**: 1-2 hours

1. Write `README.md` - Project introduction
2. Write `docs/ARCHITECTURE.md` - Architecture documentation
3. Write `docs/WORKFLOWS.md` - Workflow guide
4. Write `docs/COMPARISON.md` - Comparison with original Ralph
5. Create example `prd.json` - With dependencies
6. Create `QUICKSTART.md` - Quick start guide

### Phase 6: End-to-End Testing
**Time**: 1-2 hours

1. Create test project (simple TODO app)
2. Write 3-story PRD (with dependencies)
3. Test complete flow:
   - Claude Code environment
   - Codex environment
   - Parallel execution
   - Conflict handling
   - Final verification

**Total Estimated Time**: 8-14 hours

## User Decisions ✅

### 1. Project Name: `ralph-parallel` ✅
Simple and clear, highlights core feature

### 2. Supported CLI: Both Claude Code and Codex ✅
- **Claude Code**: Uses Task tool (`~/.claude/tasks/`)
- **Config Detection**: Auto-identify CLI type

**Codex Multi-agents API Verification**:
- ✅ API: `spawn_agent(message, agent_type)` → `{agent_id}`
- ✅ API: `wait(agent_ids[])` → Wait for completion
- ✅ API: `close_agent(agent_id)` → Cleanup resources
- Documentation: `/Users/chilikevin/aml/burn-in-cceverywhere-codex/docs/multi-agents.md`

### 3. Subagent Role Design: Predefined + Optional ✅

**Core Roles (Required, Built-in)**:
1. `planner` - Planning specialist
2. `coder` - Implementation specialist
3. `reviewer` - Code review specialist
4. `tester` - Testing specialist

**Optional Roles (Loaded from `~/.claude/agents/` or `~/.codex/agents/`)**:
- `frontend-coder` - Frontend development specialist
- `backend-coder` - Backend development specialist
- `api-coder` - API development specialist
- `ui-tester` - UI testing specialist
- `integration-tester` - Integration testing specialist
- `architect` - Architecture design specialist
- `security-reviewer` - Security review specialist
- Any user-defined agent

**Workflow Configuration Example**:
```yaml
name: full-stack
phases:
  - planner                 # Core role
  - architect               # Optional role (if exists)
  - frontend-coder          # Optional role
  - backend-coder           # Optional role
  - reviewer                # Core role
  - ui-tester               # Optional role
  - integration-tester      # Optional role
```

### 4. Dependency Analysis: Mixed Mode (Manual + AI Assist) ✅

**Default Mode (Manual)**:
```json
{
  "userStories": [
    {
      "id": "US001",
      "dependencies": []
    },
    {
      "id": "US002",
      "dependencies": ["US001"]
    }
  ]
}
```

**AI Assist Mode (Optional)**:
```bash
ralph.sh --analyze-deps
# AI analyzes all stories, generates dependency suggestions
# User reviews and confirms
```

### 5. Git Merge Strategy: Smart Hybrid ✅

**Strategy 1: Auto-merge Simple Cases**
- Fast-forward merges (no conflicts)
- Different file modifications
- Same file, different region modifications

**Strategy 2: AI Resolver for Medium Conflicts**
- Same file, same region simple conflicts
- Import statement conflicts
- Format conflicts

**Strategy 3: Manual Intervention for Complex Cases**
- Logic conflicts (AI can't determine correctness)
- Multiple stories modify same function
- AI resolver failed cases

**Conflict Severity System**:
```javascript
conflict_severity = {
  LOW: "auto-merge",           // Auto-merge
  MEDIUM: "ai-resolver",       // AI resolves
  HIGH: "manual-review"        // Manual intervention
}
```

---

# 中文版本

> [English](#ralph-parallel---design-document) | **中文**

## 项目背景

本项目旨在创建一个新的 Multi-Agent 版本的 Ralph，解决当前版本的两个关键问题：

1. **并行执行 stories** - 而不是串行执行
2. **充分利用 subagents** - 当前 burn-in-cceverywhere-ralph 中的 agents（architect、planner、code-reviewer 等）在 Ralph 场景中用不上

## 核心创新

### 从串行到并行

**当前 Ralph（串行）**：
```
Iteration 1: Agent → Story 1 → passes:true
Iteration 2: Agent → Story 2 → passes:true
Iteration 3: Agent → Story 3 → passes:true
```

**Multi-Agent Ralph（并行）**：
```
           ┌→ 代理 A → 故事 1 → passes:true ┐
ralph.sh ──┼→ 代理 B → 故事 2 → passes:true ├→ 自动合并
           └→ 代理 C → 故事 3 → passes:true ┘
```

### 正确使用 Subagents

**当前问题分析**：
- 现有 subagents（architect、planner、code-reviewer 等）存在于 `~/.claude/agents/` 或 `~/.codex/agents/`
- 但 Ralph 的 CLAUDE.md 指令从未调用它们
- Ralph 是"单角色代理"：只做实现，不分角色

**Multi-Agent Ralph 的角色分工**：
```
故事 1 需要 4 个阶段：
  1. planner agent    → 生成实现计划
  2. coder agent      → 实现代码
  3. reviewer agent   → 代码审查
  4. tester agent     → E2E 测试
```

每个故事由一个 **orchestrator** 管理 4 个阶段的 subagents！

## 项目名称和架构

### 项目名称

**`ralph-parallel`**

理由：
- 简洁清晰
- 突出核心特性（并行执行）
- 与原项目命名风格一致

[其余内容与英文版相同，结构对应...]

## 实现计划

### Phase 1: 项目骨架和 CLI 适配 ✅
**时间**: 1-2 小时

1. ✅ 创建项目目录 `/Users/chilikevin/aml/ralph-parallel/`
2. ✅ 实现 `detect-cli.sh` - CLI 检测
3. ✅ 实现 `agent-api.sh` - 统一 agent 调用接口
4. ✅ 实现 `load-agents.sh` - 动态 agent 加载
5. ✅ 创建 4 个核心 agent 指令文件
6. ✅ 测试 CLI 检测和 agent 加载

### Phase 2: 核心并行引擎
**时间**: 2-3 小时

1. 实现 `ralph.sh` - 主循环（并行执行）
2. 实现 `orchestrator.sh` - 单 story 的阶段管理
3. 实现 `dependency-analyzer.sh` - 依赖分析
4. 实现 Git 分支管理逻辑
5. 测试并行执行 2-3 个独立 stories

### Phase 3: Workflow 系统
**时间**: 1-2 小时

1. 实现 `workflow-parser.sh` - YAML 解析
2. 创建 3 个预定义 workflows
3. 测试 workflow 加载和执行

### Phase 4: 合并策略
**时间**: 2-3 小时

1. 实现 `merge-stories.sh` - 自动合并
2. 实现 `merge-conflict-resolver.sh` - 冲突分级
3. 创建 `conflict-resolver` agent
4. 测试各种冲突场景

### Phase 5: 文档和示例
**时间**: 1-2 小时

1. 编写完整文档
2. 创建示例 PRD
3. 快速开始指南

### Phase 6: 端到端测试
**时间**: 1-2 小时

1. 创建测试项目
2. 完整流程测试

**总预计时间**: 8-14 小时

## 用户决策结果 ✅

[与英文版相同的决策结果...]
