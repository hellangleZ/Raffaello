# Ralph Parallel - Multi-Agent PRD Execution System

> **English** | [中文](#中文版本)

A next-generation autonomous agent system that executes PRD user stories in parallel, with proper multi-agent orchestration.

## Status: Phase 1 Complete ✅

**Current Version**: Development (Phase 1 of 6)

### Completed
- ✅ Project directory structure
- ✅ CLI detection and abstraction layer (Claude Code + Codex support)
- ✅ Unified agent API for spawning and managing agents
- ✅ Dynamic agent loading (core + optional agents)
- ✅ 4 core agent instruction files (planner, coder, reviewer, tester)

### Next Phase
Phase 2: Core parallel execution engine

## Key Features

### 🚀 Parallel Execution
Execute multiple user stories concurrently (vs sequential in original Ralph):
```
           ┌→ Agent A → Story 1 → ✓
ralph.sh ──┼→ Agent B → Story 2 → ✓  ⇒ Auto-merge
           └→ Agent C → Story 3 → ✓
```

### 🤖 Multi-Agent Orchestration
Each story goes through specialized phases:
```
Story → planner → coder → reviewer → tester → ✓
```

### 🔄 Dual CLI Support
Works with both Claude Code and Codex:
- **Claude Code**: Uses Task system (~/.claude/tasks/)
- **Codex**: Uses Multi-agents API (spawn_agent, wait, close_agent)

### 🎯 Dynamic Agent System
- **Core agents** (built-in): planner, coder, reviewer, tester
- **Optional agents** (from ~/.claude/agents/ or ~/.codex/agents/):
  - frontend-coder, backend-coder, architect, security-reviewer, etc.
  - Auto-discovered and loaded when referenced in workflows

## Project Structure

```
ralph-parallel/
├── lib/
│   ├── detect-cli.sh          # CLI detection (Claude Code/Codex)
│   ├── agent-api.sh           # Unified agent spawning API
│   └── load-agents.sh         # Dynamic agent discovery
├── agents/
│   ├── planner.md             # Planning specialist
│   ├── coder.md               # Implementation specialist (TDD)
│   ├── reviewer.md            # Code review specialist
│   └── tester.md              # E2E testing specialist
├── workflows/                 # (Phase 3)
│   ├── simple.yaml
│   ├── standard.yaml
│   └── full-stack.yaml
├── ralph.sh                   # (Phase 2) Main parallel loop
├── orchestrator.sh            # (Phase 2) Per-story phase manager
└── docs/                      # (Phase 5)
    ├── ARCHITECTURE.md
    └── WORKFLOWS.md
```

## Testing

### CLI Detection
```bash
./lib/detect-cli.sh
# Output:
# Detected CLI: claude-code
# Multi-agents support: ✓ Enabled
# Agent directory: /Users/xxx/.claude/agents
```

### Agent Discovery
```bash
./lib/load-agents.sh
# Output:
# Core Agents:
#   - planner
#   - coder
#   - reviewer
#   - tester
# Optional Agents:
#   - code-reviewer
#   - security-reviewer
#   - architect
#   ...
# Total Available: 12
```

## Design Highlights

### 1. CLI Abstraction
Single interface works with both Claude Code and Codex:
```bash
spawn_agent "planner" "Plan story US001"
# ⇒ Internally calls either:
#   - Claude Code: echo "$prompt" | claude --print
#   - Codex: codex with spawn_agent API
```

### 2. File-Based Communication
Agents communicate via files in `$AGENT_COMM_DIR`:
- `plan.md` - Planner → Coder
- `review-approved.md` - Reviewer → Orchestrator
- `.planner-success` - Success markers

### 3. Three-Tier Conflict Resolution
- **LOW**: Auto-merge (different files)
- **MEDIUM**: AI resolver (simple conflicts)
- **HIGH**: Manual review (complex logic conflicts)

## Comparison: Original Ralph vs Ralph Parallel

| Feature | Original Ralph | Ralph Parallel |
|---------|---------------|----------------|
| Execution | Sequential (1 story at a time) | Parallel (max 3 concurrent) |
| Agents | Single agent repeated N times | Multi-agent orchestration |
| Phases | None (direct implementation) | 4 phases (plan→code→review→test) |
| Subagents | Not used | Fully utilized |
| Conflicts | None (sequential) | Smart 3-tier resolution |
| Speed | Slow (serial) | Fast (parallel) |
| Complexity | Low | Medium-High |

## Next Steps (Development Roadmap)

- **Phase 2**: Implement ralph.sh (parallel loop) and orchestrator.sh
- **Phase 3**: Implement workflow system with YAML parsing
- **Phase 4**: Implement merge strategy and conflict resolution
- **Phase 5**: Complete documentation
- **Phase 6**: End-to-end testing with real PRD

---

# 中文版本

> [English](#ralph-parallel---multi-agent-prd-execution-system) | **中文**

新一代自主代理系统，支持并行执行 PRD 用户故事，具备完整的多代理编排能力。

## 状态：Phase 1 完成 ✅

**当前版本**：开发中（6 个阶段中的第 1 阶段）

### 已完成
- ✅ 项目目录结构
- ✅ CLI 检测和抽象层（支持 Claude Code 和 Codex）
- ✅ 统一的代理 API，用于生成和管理代理
- ✅ 动态代理加载（核心代理 + 可选代理）
- ✅ 4 个核心代理指令文件（planner、coder、reviewer、tester）

### 下一阶段
Phase 2：核心并行执行引擎

## 核心特性

### 🚀 并行执行
同时执行多个用户故事（而非原 Ralph 的串行）：
```
           ┌→ 代理 A → 故事 1 → ✓
ralph.sh ──┼→ 代理 B → 故事 2 → ✓  ⇒ 自动合并
           └→ 代理 C → 故事 3 → ✓
```

### 🤖 多代理编排
每个故事经过专门的阶段：
```
故事 → planner → coder → reviewer → tester → ✓
```

### 🔄 双 CLI 支持
同时支持 Claude Code 和 Codex：
- **Claude Code**：使用 Task 系统（~/.claude/tasks/）
- **Codex**：使用 Multi-agents API（spawn_agent、wait、close_agent）

### 🎯 动态代理系统
- **核心代理**（内置）：planner、coder、reviewer、tester
- **可选代理**（从 ~/.claude/agents/ 或 ~/.codex/agents/ 加载）：
  - frontend-coder、backend-coder、architect、security-reviewer 等
  - 当在工作流中引用时自动发现和加载

## 项目结构

```
ralph-parallel/
├── lib/
│   ├── detect-cli.sh          # CLI 检测（Claude Code/Codex）
│   ├── agent-api.sh           # 统一代理生成 API
│   └── load-agents.sh         # 动态代理发现
├── agents/
│   ├── planner.md             # 规划专家
│   ├── coder.md               # 实现专家（TDD）
│   ├── reviewer.md            # 代码审查专家
│   └── tester.md              # E2E 测试专家
├── workflows/                 # （Phase 3）
│   ├── simple.yaml
│   ├── standard.yaml
│   └── full-stack.yaml
├── ralph.sh                   # （Phase 2）主并行循环
├── orchestrator.sh            # （Phase 2）单故事阶段管理器
└── docs/                      # （Phase 5）
    ├── ARCHITECTURE.md
    └── WORKFLOWS.md
```

## 测试

### CLI 检测
```bash
./lib/detect-cli.sh
# 输出：
# Detected CLI: claude-code
# Multi-agents support: ✓ Enabled
# Agent directory: /Users/xxx/.claude/agents
```

### 代理发现
```bash
./lib/load-agents.sh
# 输出：
# Core Agents:
#   - planner
#   - coder
#   - reviewer
#   - tester
# Optional Agents:
#   - code-reviewer
#   - security-reviewer
#   - architect
#   ...
# Total Available: 12
```

## 设计亮点

### 1. CLI 抽象
单一接口同时支持 Claude Code 和 Codex：
```bash
spawn_agent "planner" "Plan story US001"
# ⇒ 内部调用：
#   - Claude Code: echo "$prompt" | claude --print
#   - Codex: codex with spawn_agent API
```

### 2. 基于文件的通信
代理通过 `$AGENT_COMM_DIR` 中的文件通信：
- `plan.md` - Planner → Coder
- `review-approved.md` - Reviewer → Orchestrator
- `.planner-success` - 成功标记

### 3. 三层冲突解决
- **LOW**：自动合并（不同文件）
- **MEDIUM**：AI 解决器（简单冲突）
- **HIGH**：人工审查（复杂逻辑冲突）

## 对比：原 Ralph vs Ralph Parallel

| 特性 | 原 Ralph | Ralph Parallel |
|------|---------|----------------|
| 执行方式 | 串行（一次一个故事） | 并行（最多 3 个并发） |
| 代理 | 单代理重复 N 次 | 多代理编排 |
| 阶段 | 无（直接实现） | 4 个阶段（plan→code→review→test） |
| 子代理 | 未使用 | 充分利用 |
| 冲突 | 无（串行） | 智能 3 层解决 |
| 速度 | 慢（串行） | 快（并行） |
| 复杂度 | 低 | 中-高 |

## 下一步（开发路线图）

- **Phase 2**：实现 ralph.sh（并行循环）和 orchestrator.sh
- **Phase 3**：实现带 YAML 解析的工作流系统
- **Phase 4**：实现合并策略和冲突解决
- **Phase 5**：完成文档
- **Phase 6**：使用真实 PRD 进行端到端测试
