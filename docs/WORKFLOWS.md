# Workflow System

> **English** | [中文](#中文版本)

Raffaello uses YAML-based workflow configurations to define how user stories are executed. Each workflow specifies a sequence of phases (agents) and retry policies.

## Available Workflows

### simple.yaml - Simple Workflow
**Use for**: Straightforward tasks, bug fixes, minor updates

**Phases**: 2
1. `coder` - Implementation (max 2 attempts)
2. `tester` - Testing (max 1 attempt)

**When to use**:
- Simple bug fixes
- Documentation updates
- Minor feature additions
- Low-risk changes

**Example story**:
```json
{
  "id": "US001",
  "title": "Fix typo in README",
  "workflow": "simple"
}
```

### standard.yaml - Standard Workflow (Recommended)
**Use for**: Most user stories requiring full lifecycle

**Phases**: 4
1. `planner` - Create implementation plan (max 1 attempt)
2. `coder` - TDD implementation (max 2 attempts)
3. `reviewer` - Code review (max 2 attempts)
4. `tester` - E2E testing (max 1 attempt)

**When to use**:
- New features
- Refactoring tasks
- API changes
- Database migrations
- Any story requiring planning and review

**Example story**:
```json
{
  "id": "US002",
  "title": "Add user authentication",
  "workflow": "standard"
}
```

### full-stack.yaml - Full-Stack Workflow
**Use for**: Complex features requiring specialist agents

**Phases**: 8
1. `planner` - Planning
2. `architect` - Architecture design
3. `frontend-coder` - Frontend implementation
4. `backend-coder` - Backend implementation
5. `reviewer` - Code review
6. `security-reviewer` - Security audit
7. `ui-tester` - UI testing
8. `integration-tester` - Integration testing

**Requirements**: Requires optional agents in `~/.claude/agents/`:
- `architect`
- `frontend-coder`
- `backend-coder`
- `security-reviewer`
- `ui-tester`
- `integration-tester`

**When to use**:
- Large features spanning frontend and backend
- Security-critical features
- Complex UI work
- Multi-service integration

**Example story**:
```json
{
  "id": "US003",
  "title": "Build admin dashboard with analytics",
  "workflow": "full-stack"
}
```

## Workflow Configuration Format

### Basic Structure

```yaml
name: workflow-name
description: Brief description of when to use this workflow

phases:
  - phase1
  - phase2
  - phase3

retry_policy:
  phase1:
    max_attempts: 1
  phase2:
    max_attempts: 2
  phase3:
    max_attempts: 1
```

### Fields

#### name (required)
Unique identifier for the workflow. Used in PRD to specify which workflow a story should use.

#### description (optional)
Human-readable description explaining when to use this workflow.

#### phases (required)
Array of agent names to execute in sequence. Each phase must have a corresponding agent file in:
- `agents/{phase}.md` (core agents)
- `~/.claude/agents/{phase}.md` (optional agents)

#### retry_policy (optional)
Object mapping phase names to retry configuration:
- `max_attempts`: Number of times to retry if phase fails (default: 1)

### Validation Rules

1. **name** must be present and non-empty
2. **phases** must be an array with at least one element
3. All agents referenced in **phases** must exist
4. **retry_policy.{phase}.max_attempts** must be positive integers
5. YAML syntax must be valid

## Creating Custom Workflows

### Step 1: Create YAML File

Create `workflows/my-workflow.yaml`:

```yaml
name: my-workflow
description: Custom workflow for X type of stories

phases:
  - planner
  - coder
  - custom-agent  # Your custom agent
  - tester

retry_policy:
  planner:
    max_attempts: 1
  coder:
    max_attempts: 3  # Allow more retries
  custom-agent:
    max_attempts: 1
  tester:
    max_attempts: 2
```

### Step 2: Create Custom Agent (if needed)

If using a custom agent, create `~/.claude/agents/custom-agent.md`:

```markdown
# Custom Agent

You are a [specialist type]. Your job:

1. [Responsibility 1]
2. [Responsibility 2]
3. Create success marker when done

## Success Signal

```bash
touch "$COMMUNICATION_DIR/.custom-agent-success"
```
```

### Step 3: Validate Workflow

```bash
./lib/workflow-parser.sh validate my-workflow
```

### Step 4: Use in PRD

```json
{
  "userStories": [
    {
      "id": "US001",
      "title": "My Story",
      "workflow": "my-workflow"
    }
  ]
}
```

## Workflow Parser CLI

### List all workflows
```bash
./lib/workflow-parser.sh list
```

Output:
```
simple
standard
full-stack
my-workflow
```

### Show workflow details
```bash
./lib/workflow-parser.sh show standard
```

Output:
```
Workflow: standard
Description: Standard workflow with all core phases - recommended for most stories

Phases:
  1. planner (max attempts: 1)
  2. coder (max attempts: 2)
  3. reviewer (max attempts: 2)
  4. tester (max attempts: 1)
```

### Validate workflow(s)
```bash
# Validate single workflow
./lib/workflow-parser.sh validate standard

# Validate all workflows
./lib/workflow-parser.sh validate
```

### Parse workflow to environment
```bash
./lib/workflow-parser.sh parse standard
```

Output:
```
WORKFLOW_NAME=standard
WORKFLOW_DESCRIPTION=Standard workflow with all core phases - recommended for most stories
WORKFLOW_PHASES=(planner coder reviewer tester)
RETRY_POLICY_planner=1
RETRY_POLICY_coder=2
RETRY_POLICY_reviewer=2
RETRY_POLICY_tester=1
```

## Best Practices

### 1. Start Simple
Begin with `simple` or `standard` workflows. Add complexity only when needed.

### 2. Set Reasonable Retry Limits
- **Planning phases**: 1 attempt (planning should be deterministic)
- **Implementation phases**: 2-3 attempts (allow for fixing review feedback)
- **Review phases**: 2 attempts (give coder a chance to fix issues)
- **Testing phases**: 1-2 attempts (tests should be reliable)

### 3. Keep Phases Focused
Each phase should have a single responsibility. Don't create monolithic agents that do everything.

### 4. Document Custom Workflows
Add clear descriptions to help others understand when to use each workflow.

### 5. Validate Before Use
Always run validation after creating or modifying workflows:
```bash
./lib/workflow-parser.sh validate
```

## Troubleshooting

### "Agent not found for phase: X"
**Problem**: Workflow references an agent that doesn't exist.

**Solution**: Either:
1. Remove the phase from the workflow
2. Create the agent file in `agents/` or `~/.claude/agents/`

### "Workflow 'phases' must be an array"
**Problem**: Invalid YAML syntax for phases field.

**Solution**: Ensure phases is formatted as:
```yaml
phases:
  - phase1
  - phase2
```

Not:
```yaml
phases: phase1, phase2  # Wrong!
```

### "Invalid max_attempts: X"
**Problem**: Retry attempts must be positive integers.

**Solution**: Change to valid value:
```yaml
retry_policy:
  coder:
    max_attempts: 2  # Must be >= 1
```

---

# 中文版本

> [English](#workflow-system) | **中文**

Raffaello 使用基于 YAML 的工作流配置来定义用户故事的执行方式。每个工作流指定一系列阶段（agents）和重试策略。

## 可用工作流

### simple.yaml - 简单工作流
**适用于**：简单任务、Bug 修复、小更新

**阶段**：2 个
1. `coder` - 实现（最多 2 次尝试）
2. `tester` - 测试（最多 1 次尝试）

**何时使用**：
- 简单的 Bug 修复
- 文档更新
- 小功能添加
- 低风险变更

### standard.yaml - 标准工作流（推荐）
**适用于**：大多数需要完整生命周期的用户故事

**阶段**：4 个
1. `planner` - 创建实现计划（最多 1 次尝试）
2. `coder` - TDD 实现（最多 2 次尝试）
3. `reviewer` - 代码审查（最多 2 次尝试）
4. `tester` - E2E 测试（最多 1 次尝试）

**何时使用**：
- 新功能
- 重构任务
- API 变更
- 数据库迁移
- 任何需要规划和审查的故事

### full-stack.yaml - 全栈工作流
**适用于**：需要专业 agents 的复杂功能

**阶段**：8 个
1. `planner` - 规划
2. `architect` - 架构设计
3. `frontend-coder` - 前端实现
4. `backend-coder` - 后端实现
5. `reviewer` - 代码审查
6. `security-reviewer` - 安全审计
7. `ui-tester` - UI 测试
8. `integration-tester` - 集成测试

**要求**：需要在 `~/.claude/agents/` 中有可选 agents

## 工作流配置格式

### 基本结构

```yaml
name: workflow-name
description: 何时使用此工作流的简要说明

phases:
  - phase1
  - phase2
  - phase3

retry_policy:
  phase1:
    max_attempts: 1
  phase2:
    max_attempts: 2
  phase3:
    max_attempts: 1
```

[其余中文文档内容与英文版对应...]

## 最佳实践

### 1. 从简单开始
从 `simple` 或 `standard` 工作流开始。只在需要时添加复杂性。

### 2. 设置合理的重试限制
- **规划阶段**：1 次尝试（规划应该是确定性的）
- **实现阶段**：2-3 次尝试（允许修复审查反馈）
- **审查阶段**：2 次尝试（给 coder 修复问题的机会）
- **测试阶段**：1-2 次尝试（测试应该是可靠的）

### 3. 保持阶段专注
每个阶段应该只有单一职责。不要创建包揽一切的巨型 agents。

### 4. 文档化自定义工作流
添加清晰的描述，帮助他人理解何时使用每个工作流。

### 5. 使用前验证
创建或修改工作流后始终运行验证：
```bash
./lib/workflow-parser.sh validate
```
