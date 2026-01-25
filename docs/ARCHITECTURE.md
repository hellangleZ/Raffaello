# Ralph Parallel - Architecture Deep Dive

> **English** | [中文](#中文版本)

This document provides a deep technical dive into Ralph Parallel's architecture, design decisions, and implementation details.

## Table of Contents

1. [System Overview](#system-overview)
2. [Core Components](#core-components)
3. [Execution Flow](#execution-flow)
4. [Agent Communication](#agent-communication)
5. [Dependency Management](#dependency-management)
6. [Conflict Resolution](#conflict-resolution)
7. [Design Patterns](#design-patterns)
8. [Performance Considerations](#performance-considerations)
9. [Security](#security)
10. [Extensibility](#extensibility)

## System Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         User (PRD)                          │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                      ralph.sh                               │
│  • Read PRD                                                 │
│  • Analyze dependencies (DAG)                               │
│  • Group into batches                                       │
│  • Execute batches sequentially                             │
└─────────────────────────┬───────────────────────────────────┘
                          │
            ┌─────────────┴─────────────┐
            │     Parallel Stories      │
            │   (max 3 concurrent)      │
            └─────────────┬─────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ orchestrator │  │ orchestrator │  │ orchestrator │
│   Story 1    │  │   Story 2    │  │   Story 3    │
│              │  │              │  │              │
│  Git Branch  │  │  Git Branch  │  │  Git Branch  │
│  story-US001 │  │  story-US002 │  │  story-US003 │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       │                 │                 │
       │ 4 Phases        │ 4 Phases        │ 4 Phases
       ▼                 ▼                 ▼
 ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
 │ 1. planner  │   │ 1. planner  │   │ 1. planner  │
 │ 2. coder    │   │ 2. coder    │   │ 2. coder    │
 │ 3. reviewer │   │ 3. reviewer │   │ 3. reviewer │
 │ 4. tester   │   │ 4. tester   │   │ 4. tester   │
 └─────────────┘   └─────────────┘   └─────────────┘
       │                 │                 │
       └─────────────────┴─────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                   merge-stories.sh                          │
│  • Analyze conflicts (LOW/MEDIUM/HIGH)                      │
│  • Auto-merge (LOW)                                         │
│  • AI resolver (MEDIUM)                                     │
│  • Escalate (HIGH)                                          │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    main branch                              │
│              All stories merged ✓                           │
└─────────────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Isolation** - Each story executes in an independent git branch
2. **Parallelism** - Stories execute concurrently when dependencies allow
3. **Specialization** - Each agent has a single, focused responsibility
4. **Fail-Safe** - Conservative escalation when uncertain
5. **Idempotency** - Safe to re-run if interrupted

## Core Components

### 1. ralph.sh - Main Orchestrator

**Responsibilities**:
- Parse PRD file
- Analyze story dependencies
- Schedule batches for parallel execution
- Monitor story completion
- Trigger merge process

**Key Functions**:
```bash
execute_story() {
  # 1. Create git branch
  git checkout -b "story-$story_id"

  # 2. Invoke orchestrator
  ./orchestrator.sh "$story_id"

  # 3. Commit result
  git commit -am "feat: $story_id - $title"

  # 4. Update PRD
  update_prd_passes "$story_id" true
}

execute_batch() {
  # Execute stories in parallel (max 3)
  for story in $batch_stories; do
    execute_story "$story" &
    pids+=("$!")

    if [[ $concurrent -ge $MAX_PARALLEL_STORIES ]]; then
      wait -n "${pids[@]}"
      ((concurrent--))
    fi
  done

  wait "${pids[@]}"
}
```

**State Management**:
- Reads: `prd.json`
- Writes: `prd.json` (updates `passes` field)
- Logs: `progress.txt`

### 2. orchestrator.sh - Story Executor

**Responsibilities**:
- Load workflow configuration
- Execute phases sequentially
- Manage agent communication
- Handle phase retries
- Report success/failure

**Workflow Execution**:
```bash
execute_workflow() {
  local story_id=$1
  local workflow_file=$2

  # Parse workflow
  parse_workflow "$workflow_file"

  # Execute each phase
  for phase in "${WORKFLOW_PHASES[@]}"; do
    local max_attempts=${RETRY_POLICY[$phase]:-1}
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
      # Spawn agent
      agent_id=$(spawn_agent "$phase" "$task_message" "$story_id")

      # Wait for completion
      wait_for_agents "$agent_id"

      # Check success marker
      if check_agent_success "$story_id" "$phase"; then
        break
      fi

      ((attempt++))
    done

    # Phase failed after all retries
    if [[ $attempt -gt $max_attempts ]]; then
      return 1
    fi
  done

  return 0
}
```

**Communication Directory**:
```
/tmp/ralph-parallel/
├── US001/
│   ├── plan.md                  # Planner → Coder
│   ├── review-feedback.md       # Reviewer → Coder
│   ├── e2e-report.md           # Tester → Orchestrator
│   ├── .planner-success        # Phase success markers
│   ├── .coder-success
│   ├── .reviewer-success
│   └── .tester-success
├── US002/
│   └── ...
└── merge/
    ├── conflict-escalation.md  # High-severity conflicts
    └── .conflict-resolver-success
```

### 3. dependency-analyzer.sh - DAG Builder

**Responsibilities**:
- Parse story dependencies
- Build directed acyclic graph (DAG)
- Topologically sort stories
- Group into parallel batches

**Algorithm**:
```bash
# Input: prd.json
# Output: Batches of independent stories

# 1. Build dependency graph
for story in stories; do
  deps[story] = get_dependencies(story)
done

# 2. Topological sort (Kahn's algorithm)
while has_stories_without_deps; do
  # Find all stories with no dependencies
  batch = stories_with_no_deps()

  # Add to current batch
  batches.append(batch)

  # Mark as completed
  mark_completed(batch)

  # Remove from other stories' dependencies
  for story in remaining_stories; do
    deps[story].remove(batch)
  done
done

# 3. Output batches
echo batches | jq
```

**Bash 3.2 Compatibility**:
Since macOS uses bash 3.2 (no associative arrays), we use temp files:
```bash
TMP_DIR=$(mktemp -d)
COMPLETED_FILE="$TMP_DIR/completed"
IN_BATCH_FILE="$TMP_DIR/in_batch"

mark_completed() {
  echo "$story" >> "$COMPLETED_FILE"
}

is_completed() {
  grep -q "^${story}$" "$COMPLETED_FILE" 2>/dev/null
}
```

### 4. workflow-parser.sh - YAML Processor

**Responsibilities**:
- Load workflow YAML files
- Validate workflow structure
- Export environment variables
- Provide CLI interface

**CLI Commands**:
```bash
# List all workflows
./lib/workflow-parser.sh list

# Validate workflow
./lib/workflow-parser.sh validate standard

# Show workflow details
./lib/workflow-parser.sh show standard

# Parse workflow to environment
eval $(./lib/workflow-parser.sh parse standard)
```

**Workflow Structure**:
```yaml
name: standard
description: Standard workflow for most user stories
phases:
  - planner
  - coder
  - reviewer
  - tester

retry_policy:
  reviewer:
    max_attempts: 2   # Coder can fix and resubmit once
  tester:
    max_attempts: 1   # E2E failures need debugging
```

### 5. conflict-analyzer.sh - Severity Grader

**Responsibilities**:
- Analyze merge conflicts
- Grade severity (LOW/MEDIUM/HIGH)
- Recommend resolution strategy
- Extract conflict details

**Severity Criteria**:
```bash
analyze_conflict_severity() {
  local file=$1

  # Metrics
  conflict_count=$(grep -c "^<<<<<<< " "$file")
  file_size=$(wc -l < "$file")
  conflict_ratio=$((conflict_count * 100 / file_size))
  has_logic_conflict=$(grep -E "(function|class)" "$file" | grep -c "^<<<<<<<")

  # Decision tree
  if [[ $has_logic_conflict -gt 0 ]]; then
    echo "HIGH"    # Logic conflicts need human review
  elif [[ $conflict_ratio -gt 20 ]]; then
    echo "HIGH"    # Too many conflicts (>20%)
  elif [[ $conflict_ratio -gt 5 ]]; then
    echo "MEDIUM"  # Moderate conflicts (5-20%)
  else
    echo "LOW"     # Simple conflicts (<5%)
  fi
}
```

### 6. merge-stories.sh - Smart Merger

**Responsibilities**:
- Find all story branches
- Attempt fast-forward merges
- Route conflicts by severity
- Orchestrate AI resolver
- Escalate high-severity conflicts

**Three-Tier Strategy**:
```bash
merge_branch() {
  local branch=$1

  # Tier 1: Fast-forward (no conflicts)
  if git merge --ff-only "$branch" 2>/dev/null; then
    return 0
  fi

  # Tier 2: Regular merge with conflict handling
  if ! git merge --no-ff "$branch" 2>/dev/null; then
    # Analyze conflicts
    analyze_all_conflicts || analysis_result=$?

    if [[ $analysis_result -eq 0 ]]; then
      # LOW - auto-merge
      auto_merge_simple_conflicts
    elif [[ $analysis_result -eq 1 ]]; then
      # MEDIUM - AI resolver
      ai_resolve_conflicts
    else
      # HIGH - manual review
      log_error "Manual review required"
      git merge --abort
      return 1
    fi
  fi

  # Commit if resolved
  if [[ $(git diff --name-only --diff-filter=U | wc -l) -eq 0 ]]; then
    git commit --no-edit
    return 0
  fi

  return 1
}
```

## Execution Flow

### Complete Story Execution

```
┌─────────────────────────────────────────────────────────────┐
│ 1. ralph.sh starts                                          │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Read prd.json                                            │
│    • Parse user stories                                     │
│    • Filter where passes=false                              │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Analyze dependencies                                     │
│    • Build DAG                                              │
│    • Topological sort                                       │
│    • Group into batches                                     │
│    Example: [US001, US002], [US003]                        │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Execute Batch 1 (parallel)                               │
│    • US001 & US002 execute concurrently                     │
│    • Each in own git branch                                 │
│    • Each with own orchestrator                             │
└───────────────────────┬─────────────────────────────────────┘
                        │
        ┌───────────────┴───────────────┐
        │                               │
        ▼                               ▼
┌──────────────────┐            ┌──────────────────┐
│ US001:           │            │ US002:           │
│ git checkout -b  │            │ git checkout -b  │
│ story-US001      │            │ story-US002      │
└────────┬─────────┘            └────────┬─────────┘
         │                               │
         ▼                               ▼
┌──────────────────┐            ┌──────────────────┐
│ orchestrator.sh  │            │ orchestrator.sh  │
│ US001            │            │ US002            │
└────────┬─────────┘            └────────┬─────────┘
         │                               │
         ▼                               ▼
┌──────────────────┐            ┌──────────────────┐
│ Phase 1: planner │            │ Phase 1: planner │
│   • Read story   │            │   • Read story   │
│   • Create plan  │            │   • Create plan  │
│   • Write plan.md│            │   • Write plan.md│
└────────┬─────────┘            └────────┬─────────┘
         │                               │
         ▼                               ▼
┌──────────────────┐            ┌──────────────────┐
│ Phase 2: coder   │            │ Phase 2: coder   │
│   • Read plan    │            │   • Read plan    │
│   • Implement    │            │   • Implement    │
│   • Write tests  │            │   • Write tests  │
│   • Run tests    │            │   • Run tests    │
└────────┬─────────┘            └────────┬─────────┘
         │                               │
         ▼                               ▼
┌──────────────────┐            ┌──────────────────┐
│ Phase 3: reviewer│            │ Phase 3: reviewer│
│   • Review code  │            │   • Review code  │
│   • Check quality│            │   • Check quality│
│   • Check security│            │   • Check security│
└────────┬─────────┘            └────────┬─────────┘
         │                               │
         ▼                               ▼
┌──────────────────┐            ┌──────────────────┐
│ Phase 4: tester  │            │ Phase 4: tester  │
│   • Run E2E tests│            │   • Run E2E tests│
│   • Validate UI  │            │   • Validate UI  │
│   • Create report│            │   • Create report│
└────────┬─────────┘            └────────┬─────────┘
         │                               │
         ▼                               ▼
┌──────────────────┐            ┌──────────────────┐
│ git commit       │            │ git commit       │
│ Update PRD       │            │ Update PRD       │
│ passes=true      │            │ passes=true      │
└────────┬─────────┘            └────────┬─────────┘
         │                               │
         └───────────────┬───────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Batch 1 complete, wait for all stories                   │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. Execute Batch 2 (US003, depends on US001 & US002)       │
│    • Same flow as above                                     │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. All batches complete, merge all story branches          │
│    • ./merge-stories.sh                                     │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│ 8. Done! All stories on main branch                         │
└─────────────────────────────────────────────────────────────┘
```

## Agent Communication

### File-Based IPC

Agents communicate via files in `$AGENT_COMM_DIR` (default: `/tmp/ralph-parallel/`):

**Planner → Coder**:
```bash
# planner creates
$COMM_DIR/$STORY_ID/plan.md

# coder reads
plan=$(<"$COMM_DIR/$STORY_ID/plan.md")
```

**Reviewer → Coder**:
```bash
# reviewer creates
$COMM_DIR/$STORY_ID/review-feedback.md
$COMM_DIR/$STORY_ID/review-approved.md

# orchestrator checks
if [[ -f "$COMM_DIR/$STORY_ID/review-approved.md" ]]; then
  continue_to_tester
else
  retry_coder_with_feedback
fi
```

**Success Markers**:
```bash
# Agent creates on success
touch "$COMM_DIR/$STORY_ID/.${agent_name}-success"

# Orchestrator checks
check_agent_success() {
  [[ -f "$COMM_DIR/$STORY_ID/.${agent_name}-success" ]]
}
```

### CLI Abstraction Layer

**detect-cli.sh**: Detects which CLI is available
```bash
detect_cli() {
  if command -v claude &> /dev/null; then
    echo "claude-code"
  elif command -v codex &> /dev/null; then
    echo "codex"
  else
    echo "ERROR: No CLI found"
    exit 1
  fi
}
```

**agent-api.sh**: Unified interface
```bash
spawn_agent() {
  local cli=$(detect_cli)
  local agent_name=$1
  local task_message=$2
  local story_id=$3

  case "$cli" in
    claude-code)
      # Use Task tool
      claude <<EOF
$(<"agents/${agent_name}.md")

Task: $task_message
EOF
      ;;
    codex)
      # Use Multi-agents API
      codex spawn_agent \
        --message "$(<agents/${agent_name}.md)\n\nTask: $task_message" \
        --agent_type "worker"
      ;;
  esac
}
```

## Dependency Management

### DAG Construction

Example PRD:
```json
{
  "userStories": [
    {"id": "US001", "dependencies": []},
    {"id": "US002", "dependencies": []},
    {"id": "US003", "dependencies": ["US001"]},
    {"id": "US004", "dependencies": ["US001", "US002"]},
    {"id": "US005", "dependencies": ["US003", "US004"]}
  ]
}
```

Resulting DAG:
```
US001 ─┬─→ US003 ───┐
       │            │
       └─→ US004 ───┼─→ US005
              ▲     │
              │     │
US002 ────────┴─────┘
```

Batches:
```json
{
  "batches": [
    ["US001", "US002"],    // Batch 1: Independent
    ["US003", "US004"],    // Batch 2: Depend on Batch 1
    ["US005"]              // Batch 3: Depends on Batch 2
  ]
}
```

### Parallel Execution Constraints

**Max Concurrent Stories**: 3
- Reason: API rate limits
- Configuration: `MAX_PARALLEL_STORIES=3`

**Batch Ordering**: Sequential
- Batches execute sequentially
- Stories within batch execute in parallel

## Conflict Resolution

### Three-Tier System

**Tier 1: Auto-Merge (LOW Severity)**
- **Criteria**:
  - Conflict ratio < 5%
  - No logic conflicts
  - Small conflict sections
- **Strategy**: `git checkout --ours` or `--theirs`
- **Example**:
```diff
<<<<<<< HEAD
import { A } from './a';
=======
import { B } from './b';
>>>>>>> story-US002

Resolved:
import { A } from './a';
import { B } from './b';
```

**Tier 2: AI Resolver (MEDIUM Severity)**
- **Criteria**:
  - Conflict ratio 5-20%
  - Multiple small conflicts
  - No function/class modifications
- **Strategy**: Spawn `conflict-resolver` agent
- **Agent Instructions**: See `agents/conflict-resolver.md`
- **Example**:
```javascript
// Conflict: Both add functions
<<<<<<< HEAD
function validateEmail(email) { ... }
=======
function validatePassword(pwd) { ... }
>>>>>>> story-US002

// Resolved: Keep both
function validateEmail(email) { ... }
function validatePassword(pwd) { ... }
```

**Tier 3: Manual Review (HIGH Severity)**
- **Criteria**:
  - Conflict ratio > 20%
  - Logic conflicts (function bodies)
  - AI resolver failed
- **Strategy**: Abort merge, create report
- **Example**:
```javascript
// HIGH severity - same function modified
<<<<<<< HEAD
function login(user) {
  return jwt.sign({id: user.id}, secret);  // JWT auth
}
=======
function login(user) {
  return sessions.create(user);  // Session auth
}
>>>>>>> story-US002

// Cannot auto-resolve - architectural decision needed
```

## Design Patterns

### 1. Command Pattern (CLI Tools)
Each script provides a CLI interface:
```bash
./lib/workflow-parser.sh <command> [args]
./lib/conflict-analyzer.sh <command> [args]
./lib/dependency-analyzer.sh <file>
```

### 2. Strategy Pattern (Conflict Resolution)
Different strategies based on severity:
```bash
resolve_conflict() {
  local severity=$(analyze_conflict_severity "$file")

  case "$severity" in
    LOW) auto_merge_strategy ;;
    MEDIUM) ai_resolver_strategy ;;
    HIGH) manual_review_strategy ;;
  esac
}
```

### 3. Template Method Pattern (Orchestrator)
Workflow execution follows fixed template:
```bash
execute_workflow() {
  for phase in "${WORKFLOW_PHASES[@]}"; do
    execute_phase "$phase"  # Template method
  done
}
```

### 4. Observer Pattern (Success Markers)
Agents signal completion via files:
```bash
# Agent
touch "$COMM_DIR/$STORY_ID/.${agent_name}-success"

# Orchestrator observes
check_agent_success "$story_id" "$agent_name"
```

### 5. Fail-Safe Pattern
Always escalate when uncertain:
```bash
if can_resolve_automatically; then
  auto_resolve
elif can_resolve_with_ai; then
  ai_resolve
else
  escalate_to_human  # Fail-safe
fi
```

## Performance Considerations

### Token Cost Optimization

**Strategy 1: Use Haiku for Simple Agents**
```yaml
# Future: Model selection per agent
agents:
  planner:
    model: haiku     # Planning doesn't need Opus
  coder:
    model: sonnet    # Implementation needs quality
  reviewer:
    model: haiku     # Review is pattern-matching
  tester:
    model: haiku     # Test execution is straightforward
```

**Strategy 2: Minimize Context**
- Each agent gets only relevant files
- No full codebase context
- Focused instructions per role

### Parallel Execution

**Benefits**:
- 3 stories in parallel = 3x speedup (theoretical)
- Independent branches avoid conflicts
- Better resource utilization

**Constraints**:
- API rate limits (max 3 concurrent)
- Git I/O not parallelized
- Dependency chains reduce parallelism

**Example Speedup**:
```
Sequential: 10 stories × 30 min = 300 min (5 hours)
Parallel (3x):
  - Batch 1: 3 stories × 30 min = 30 min
  - Batch 2: 3 stories × 30 min = 30 min
  - Batch 3: 3 stories × 30 min = 30 min
  - Batch 4: 1 story × 30 min = 30 min
  Total: 120 min (2 hours, 2.5x speedup)
```

## Security

### Sandboxing
- Each story in isolated git branch
- No cross-story file access
- Communication only via designated files

### Secret Management
- Never commit `.env` files
- Conflict resolver checks for secrets
- Escalate if sensitive files conflict

### Code Review
- Every story goes through reviewer agent
- Security checks enforced
- Can't skip review phase

## Extensibility

### Adding Custom Agents

1. Create agent instructions:
```bash
mkdir -p ~/.claude/agents
cat > ~/.claude/agents/my-custom-agent.md <<EOF
# My Custom Agent

You are a specialist in...

Your responsibilities:
1. ...
2. ...
EOF
```

2. Reference in workflow:
```yaml
name: my-custom-workflow
phases:
  - planner
  - my-custom-agent
  - coder
  - reviewer
  - tester
```

3. Validate:
```bash
./lib/workflow-parser.sh validate my-custom-workflow
```

### Adding Custom Workflows

1. Create workflow file:
```bash
cat > workflows/my-workflow.yaml <<EOF
name: my-workflow
description: Custom workflow for specific use case
phases:
  - phase1
  - phase2

retry_policy:
  phase1:
    max_attempts: 3
EOF
```

2. Use in PRD:
```json
{
  "userStories": [
    {
      "id": "US001",
      "workflow": "my-workflow",
      ...
    }
  ]
}
```

---

# 中文版本

> [English](#ralph-parallel---architecture-deep-dive) | **中文**

本文档提供 Ralph Parallel 架构、设计决策和实现细节的深度技术解析。

## 目录

1. [系统概述](#系统概述-1)
2. [核心组件](#核心组件-1)
3. [执行流程](#执行流程-1)
4. [代理通信](#代理通信-1)
5. [依赖管理](#依赖管理-1)
6. [冲突解决](#冲突解决-1)
7. [设计模式](#设计模式-1)
8. [性能考虑](#性能考虑-1)
9. [安全性](#安全性-1)
10. [扩展性](#扩展性-1)

## 系统概述-1

### 高层架构

*(同英文版架构图)*

### 关键设计原则

1. **隔离** - 每个故事在独立的 git 分支中执行
2. **并行性** - 当依赖允许时，故事并发执行
3. **专业化** - 每个代理有单一、专注的职责
4. **故障安全** - 不确定时保守升级
5. **幂等性** - 中断后可安全重新运行

## 核心组件-1

*(详细的中文翻译和解释...)*

## 可扩展性-1

### 添加自定义代理

1. 创建代理指令：
```bash
mkdir -p ~/.claude/agents
cat > ~/.claude/agents/my-custom-agent.md <<EOF
# 我的自定义代理

你是...的专家

你的职责：
1. ...
2. ...
EOF
```

2. 在工作流中引用：
```yaml
name: my-custom-workflow
phases:
  - planner
  - my-custom-agent
  - coder
  - reviewer
  - tester
```

3. 验证：
```bash
./lib/workflow-parser.sh validate my-custom-workflow
```

---

**Ralph Parallel** - 架构深度解析
