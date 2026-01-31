# Raffaello vs Original Ralph - Detailed Comparison

> **English** | [中文](#中文版本)

This document provides a comprehensive comparison between Raffaello and the original Ralph autonomous agent system.

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Comparison](#architecture-comparison)
3. [Execution Model](#execution-model)
4. [Performance Analysis](#performance-analysis)
5. [Use Cases](#use-cases)
6. [Migration Guide](#migration-guide)
7. [Trade-offs](#trade-offs)

## Executive Summary

| Aspect | Original Ralph | Raffaello | Winner |
|--------|---------------|----------------|---------|
| **Execution Speed** | Sequential (N × time) | Parallel (N/3 × time) | Raffaello (3x faster) |
| **Complexity** | Low (single agent loop) | Medium (orchestration) | Original Ralph (simpler) |
| **Agent Utilization** | Single agent reused | Multi-agent specialized | Raffaello (better architecture) |
| **Conflict Handling** | None needed (sequential) | Smart 3-tier system | Tie (different needs) |
| **Setup Time** | Minutes | Hours | Original Ralph (faster start) |
| **Scalability** | Poor (linear scaling) | Good (sub-linear scaling) | Raffaello (better for large projects) |
| **Best For** | 1-5 stories, simple PRDs | 10+ stories, complex PRDs | Context-dependent |

## Architecture Comparison

### Original Ralph

```
┌─────────────────────────────────┐
│          raffaello.sh               │
│  (Single-agent loop)            │
└────────────┬────────────────────┘
             │
             │ Iteration 1
             ▼
    ┌────────────────┐
    │  Claude Agent  │
    │  Story 1       │
    │  main branch   │
    └────────┬───────┘
             │
             │ passes=true
             │
             │ Iteration 2
             ▼
    ┌────────────────┐
    │  Claude Agent  │
    │  Story 2       │
    │  main branch   │
    └────────┬───────┘
             │
             │ passes=true
             │
             │ Iteration 3
             ▼
    ┌────────────────┐
    │  Claude Agent  │
    │  Story 3       │
    │  main branch   │
    └────────┬───────┘
             │
             ▼
         Complete!
```

**Key Characteristics**:
- Single agent handles everything
- Works directly on main branch
- Sequential execution (one story at a time)
- No role specialization
- No merge conflicts (serial commits)
- Simple loop: `while has_pending_stories; do execute_next_story; done`

### Raffaello

```
┌─────────────────────────────────────────┐
│            raffaello.sh                     │
│  (Parallel orchestrator)                │
└───────┬─────────────────────────────────┘
        │
        ├─ Batch 1 (parallel) ─────────────┐
        │                                   │
        ▼                    ▼              ▼
 ┌──────────────┐    ┌──────────────┐  ┌──────────────┐
 │ orchestrator │    │ orchestrator │  │ orchestrator │
 │   Story 1    │    │   Story 2    │  │   Story 3    │
 │ story-US001  │    │ story-US002  │  │ story-US003  │
 └──────┬───────┘    └──────┬───────┘  └──────┬───────┘
        │                   │                  │
        │ 4 agents          │ 4 agents         │ 4 agents
        ▼                   ▼                  ▼
  planner               planner            planner
  coder                 coder              coder
  reviewer              reviewer           reviewer
  tester                tester             tester
        │                   │                  │
        └───────────────────┴──────────────────┘
                            │
                            ▼
                   ┌────────────────────┐
                   │  merge-stories.sh  │
                   │  (Smart merger)    │
                   └─────────┬──────────┘
                             │
                             ▼
                         Complete!
```

**Key Characteristics**:
- Multiple orchestrators manage stories in parallel
- Each story in isolated git branch
- 4 specialized agents per story (planner, coder, reviewer, tester)
- Smart merge system with conflict resolution
- Complex coordination: `dependency analysis → parallel execution → intelligent merging`

## Execution Model

### Original Ralph

**Workflow**:
1. Read PRD
2. Find first story where `passes=false`
3. Agent implements story on main branch
4. Agent runs tests
5. If tests pass, agent commits and sets `passes=true`
6. Repeat from step 2

**Example (3 stories)**:
```bash
# Iteration 1
claude < CLAUDE.md
# User story US001
# ... 30 minutes later ...
# ✓ Committed, passes=true

# Iteration 2
claude < CLAUDE.md
# User story US002
# ... 30 minutes later ...
# ✓ Committed, passes=true

# Iteration 3
claude < CLAUDE.md
# User story US003
# ... 30 minutes later ...
# ✓ Committed, passes=true

# Total: 90 minutes
```

**Pros**:
- Simple to understand
- No merge conflicts
- Easy to debug (single thread)
- Linear git history

**Cons**:
- Slow (N × time per story)
- No parallelism
- Single agent does everything (no specialization)
- Can't utilize multiple agents simultaneously

### Raffaello

**Workflow**:
1. Read PRD
2. Analyze dependencies (build DAG)
3. Group stories into batches
4. For each batch:
   - Execute stories in parallel (max 3)
   - Each story: create branch → orchestrate 4 agents → commit
5. Merge all branches with smart conflict resolution

**Example (3 stories, no dependencies)**:
```bash
# All 3 stories execute concurrently
./raffaello.sh

# Batch 1: US001, US002, US003 (parallel)
├─ Story US001 (branch: story-US001)
│  ├─ planner: create plan
│  ├─ coder: implement + tests
│  ├─ reviewer: code review
│  └─ tester: E2E tests
│  └─ ✓ Committed (30 min)
│
├─ Story US002 (branch: story-US002)
│  ├─ planner: create plan
│  ├─ coder: implement + tests
│  ├─ reviewer: code review
│  └─ tester: E2E tests
│  └─ ✓ Committed (30 min)
│
└─ Story US003 (branch: story-US003)
   ├─ planner: create plan
   ├─ coder: implement + tests
   ├─ reviewer: code review
   └─ tester: E2E tests
   └─ ✓ Committed (30 min)

# Merge phase (5 min)
./merge-stories.sh
# ✓ All branches merged to main

# Total: 35 minutes (2.6x faster!)
```

**Pros**:
- Fast (parallel execution)
- Specialized agents (planner, coder, reviewer, tester)
- Better code quality (mandatory review)
- Scalable (sub-linear time growth)

**Cons**:
- More complex setup
- Merge conflicts possible
- More moving parts (debugging harder)
- Branching git history

## Performance Analysis

### Time Complexity

**Original Ralph**: O(N) where N = number of stories
- Each story takes T minutes
- Total time = N × T

**Raffaello**: O(N/P + M) where:
- N = number of stories
- P = max parallel stories (3)
- M = merge time
- Total time ≈ (N/3) × T + M

### Real-World Scenarios

#### Scenario 1: 10 Independent Stories

| System | Time | Calculation |
|--------|------|-------------|
| Original Ralph | 300 min (5 hours) | 10 × 30 min |
| Raffaello | 105 min (1.75 hours) | (10/3) × 30 min + 5 min = 105 min |
| **Speedup** | **2.9x** | |

#### Scenario 2: 20 Stories with Dependencies

PRD structure:
```
Batch 1: 5 stories (independent)
Batch 2: 8 stories (depend on Batch 1)
Batch 3: 4 stories (depend on Batch 2)
Batch 4: 3 stories (depend on Batch 3)
```

| System | Time | Calculation |
|--------|------|-------------|
| Original Ralph | 600 min (10 hours) | 20 × 30 min |
| Raffaello | 245 min (4 hours) | 4 batches, each ≈60 min + merge overhead |
| **Speedup** | **2.4x** | |

#### Scenario 3: 3 Stories (Small PRD)

| System | Time | Calculation |
|--------|------|-------------|
| Original Ralph | 90 min | 3 × 30 min |
| Raffaello | 35 min | 1 batch × 30 min + 5 min merge |
| **Speedup** | **2.6x** | |

**Note**: Raffaello has overhead (dependency analysis, branch management, merging), so speedup is slightly less than theoretical 3x.

### Token Cost Comparison

Assuming:
- Each story uses 100K tokens
- 10 stories total

**Original Ralph**:
```
Total tokens: 10 × 100K = 1M tokens
Cost (Opus 4): 1M tokens
```

**Raffaello**:
```
Total tokens per story:
  - planner: 20K tokens (Haiku)
  - coder: 50K tokens (Sonnet)
  - reviewer: 20K tokens (Haiku)
  - tester: 30K tokens (Sonnet)
  Total: 120K tokens per story

Total tokens: 10 × 120K = 1.2M tokens
Cost: 1.2M tokens (20% more)
```

**Trade-off**: Raffaello uses 20% more tokens but completes 2.5x faster.

## Use Cases

### When to Use Original Ralph

✅ **Best For**:
1. **Small PRDs** (1-5 stories)
   - Overhead of parallel system not worth it
   - Fast enough with sequential execution

2. **Simple Projects** (no complex dependencies)
   - Single agent can handle everything
   - No need for specialized roles

3. **Learning/Experimentation**
   - Easier to understand and debug
   - Simpler setup

4. **Budget-Constrained**
   - Uses fewer tokens (20% less)
   - Single CLI session

5. **Sequential Dependencies** (each story depends on previous)
   - No parallelism possible anyway
   - Example: `US002 → US003 → US004 → ...`

**Example PRD**:
```json
{
  "userStories": [
    {"id": "US001", "title": "Add logout button"},
    {"id": "US002", "title": "Fix typo in README"},
    {"id": "US003", "title": "Update dependency versions"}
  ]
}
```

### When to Use Raffaello

✅ **Best For**:
1. **Large PRDs** (10+ stories)
   - Significant time savings from parallelism
   - Worth the setup complexity

2. **Independent Stories** (few dependencies)
   - Maximum parallelism possible
   - Example: 15 stories, all independent → 5x speedup

3. **Quality-Critical Projects**
   - Mandatory code review phase
   - Specialized agents for each role
   - Better test coverage

4. **Complex Features** (need planning)
   - Planner agent creates detailed plan
   - Coder follows plan
   - Less trial-and-error

5. **Team Collaboration** (multiple developers)
   - Parallel branches avoid conflicts
   - Each developer can work on different stories

**Example PRD**:
```json
{
  "userStories": [
    {"id": "US001", "title": "User authentication", "dependencies": []},
    {"id": "US002", "title": "Product catalog", "dependencies": []},
    {"id": "US003", "title": "Shopping cart", "dependencies": []},
    {"id": "US004", "title": "Checkout", "dependencies": ["US001", "US003"]},
    {"id": "US005", "title": "Admin dashboard", "dependencies": ["US001"]},
    ...
  ]
}
```

## Migration Guide

### From Original Ralph to Raffaello

**Step 1: Install Dependencies**
```bash
brew install jq yq  # JSON and YAML parsing
```

**Step 2: Update PRD Format**
Add `workflow` and `dependencies` fields:
```json
{
  "userStories": [
    {
      "id": "US001",
      "title": "User Authentication",
      "description": "...",
      "workflow": "standard",     // NEW
      "dependencies": [],         // NEW
      "passes": false
    }
  ]
}
```

**Step 3: Choose Workflows**
- **simple**: Fast (coder + tester only)
- **standard**: Balanced (all 4 agents)
- **full-stack**: Complete (optional agents)

**Step 4: Analyze Dependencies**
```bash
# Manually add dependencies
# OR use AI to analyze (future feature)
./lib/dependency-analyzer.sh prd.json
```

**Step 5: Run Raffaello**
```bash
./raffaello.sh
```

**Step 6: Handle Conflicts**
If merge conflicts occur:
```bash
# View conflict analysis
./lib/conflict-analyzer.sh analyze

# Manual resolution if needed
git checkout main
git merge story-US001
# Resolve conflicts
git add .
git commit
```

### From Raffaello Back to Original Ralph

**Use Case**: Small PRD, not worth parallel overhead

**Step 1: Merge All Branches**
```bash
./merge-stories.sh
```

**Step 2: Clean Up PRD**
Remove `workflow` and `dependencies` fields:
```json
{
  "userStories": [
    {
      "id": "US001",
      "title": "...",
      "description": "...",
      "passes": false
    }
  ]
}
```

**Step 3: Use Original Ralph**
```bash
cd path/to/original-ralph
cp path/to/raffaello/prd.json .
./raffaello.sh
```

## Trade-offs

### Complexity vs Speed

**Original Ralph**:
- ✅ Simple (single script)
- ✅ Easy to debug
- ❌ Slow (sequential)
- ❌ No specialization

**Raffaello**:
- ❌ Complex (8+ scripts, 5 agents)
- ❌ Harder to debug
- ✅ Fast (parallel)
- ✅ Specialized agents

**Recommendation**: Use Raffaello for ≥10 stories, Original Ralph for <10 stories.

### Token Cost vs Quality

**Original Ralph**:
- ✅ Fewer tokens (single agent)
- ❌ No mandatory review
- ❌ Possible lower quality

**Raffaello**:
- ❌ More tokens (4 agents per story)
- ✅ Mandatory review phase
- ✅ Better code quality

**Recommendation**: Use Raffaello for production code, Original Ralph for experiments.

### Setup Time vs Execution Time

**Original Ralph**:
- ✅ Minutes to setup
- ❌ Hours to execute large PRD

**Raffaello**:
- ❌ Hours to setup initially
- ✅ Minutes to execute large PRD

**Recommendation**: Upfront investment in Raffaello pays off for repeated use.

## Feature Comparison Table

| Feature | Original Ralph | Raffaello |
|---------|---------------|----------------|
| **Core Features** | | |
| PRD execution | ✅ | ✅ |
| Autonomous agents | ✅ | ✅ |
| Progress tracking | ✅ | ✅ |
| Git integration | ✅ | ✅ |
| **Execution** | | |
| Parallel execution | ❌ | ✅ |
| Dependency analysis | ❌ | ✅ |
| Batch processing | ❌ | ✅ |
| Sequential execution | ✅ | ✅ (for dependent stories) |
| **Agents** | | |
| Single agent | ✅ | ❌ |
| Planner agent | ❌ | ✅ |
| Coder agent | ✅ (all-in-one) | ✅ (specialized) |
| Reviewer agent | ❌ | ✅ |
| Tester agent | ✅ (part of main) | ✅ (dedicated) |
| Custom agents | ❌ | ✅ |
| **Workflows** | | |
| Fixed workflow | ✅ | ❌ |
| Configurable workflows | ❌ | ✅ |
| Workflow validation | ❌ | ✅ |
| **Conflict Handling** | | |
| Auto-merge | N/A | ✅ |
| AI conflict resolver | N/A | ✅ |
| Manual escalation | N/A | ✅ |
| **Quality** | | |
| Mandatory code review | ❌ | ✅ |
| E2E testing | ✅ | ✅ |
| TDD enforcement | Optional | ✅ (coder agent) |
| **Configuration** | | |
| CLI detection | ❌ | ✅ |
| Environment variables | Limited | Extensive |
| Custom workflows | ❌ | ✅ |
| **Documentation** | | |
| README | ✅ | ✅ |
| Architecture docs | ❌ | ✅ |
| Workflow guide | ❌ | ✅ |
| Comparison guide | ❌ | ✅ (this doc) |
| **Testing** | | |
| Unit tests | ❌ | ✅ |
| Integration tests | ❌ | ✅ (run-tests.sh workflows) |
| **Complexity** | | |
| Lines of code | ~300 | ~2500 |
| Number of files | 3 | 20+ |
| Setup time | 5 min | 1-2 hours |
| Learning curve | Low | Medium |

## Conclusion

### When to Use Each System

**Use Original Ralph** if:
- PRD has <10 stories
- Stories are simple
- Budget is tight
- Learning/experimenting
- Don't need code review

**Use Raffaello** if:
- PRD has ≥10 stories
- Stories are independent
- Quality is critical
- Time is valuable
- Need specialized agents

### The Future

Raffaello is designed for scalability. As projects grow larger (50+ stories, 100+ stories), the benefits of parallel execution and specialized agents become increasingly significant.

Original Ralph remains excellent for small projects and learning, but Raffaello is the recommended choice for production workloads.

---

# 中文版本

> [English](#raffaello-vs-original-ralph---detailed-comparison) | **中文**

本文档提供 Raffaello 和原始 Ralph 自主代理系统之间的全面比较。

## 目录

*(中文目录...)*

## 执行摘要

*(中文翻译的表格和内容...)*

## 结论

### 何时使用每个系统

**使用原始 Ralph** 如果：
- PRD 少于 10 个故事
- 故事简单
- 预算紧张
- 学习/实验
- 不需要代码审查

**使用 Raffaello** 如果：
- PRD 有 ≥10 个故事
- 故事独立
- 质量关键
- 时间宝贵
- 需要专业化代理

### 未来展望

Raffaello 为可扩展性而设计。随着项目规模增大（50+ 故事，100+ 故事），并行执行和专业化代理的优势变得越来越显著。

原始 Ralph 对于小型项目和学习仍然很好，但 Raffaello 是生产工作负载的推荐选择。

---

**Raffaello** - 详细对比分析
