# Ralph Parallel

**Multi-Agent Ralph** - A next-generation autonomous agent system for parallel PRD execution.

> **English** | [中文](#中文版本)

Ralph Parallel solves two fundamental problems of the original Ralph:
1. **Parallel Execution** - Execute multiple user stories simultaneously instead of sequentially
2. **Subagent Utilization** - Properly leverage specialized agents (planner, coder, reviewer, tester)

## Status: Phase 4 Complete ✅

**Current Version**: Development (Phase 4 of 6 - 67% complete)

### Completed
- ✅ Phase 1: Project skeleton and CLI adaptation
- ✅ Phase 2: Core parallel execution engine
- ✅ Phase 3: Workflow system with YAML parsing
- ✅ Phase 4: Smart merge strategy and conflict resolution

### Next Phase
Phase 5: Documentation and Examples

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/ralph-parallel
cd ralph-parallel

# 2. Ensure dependencies are installed
brew install jq yq  # JSON and YAML parsing

# 3. Create your PRD
cp prd.json.example prd.json
# Edit prd.json with your user stories

# 4. Run Ralph Parallel
./ralph.sh
```

See [QUICKSTART.md](QUICKSTART.md) for detailed setup instructions.

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

## Key Features

### 🚀 Parallel Execution
- Execute up to 3 stories simultaneously
- Smart dependency analysis (DAG-based)
- Independent git branches per story
- Automatic merging on completion

### 🤖 Multi-Agent Orchestration
Each story is managed by an orchestrator with 4 specialized agents:
- **Planner** - Creates implementation plans
- **Coder** - Implements code following TDD
- **Reviewer** - Reviews code for quality and security
- **Tester** - Runs E2E tests and validates

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

### Simple Workflow (Fastest)
```yaml
name: simple
phases:
  - coder
  - tester
```
Use for: Bug fixes, simple features, low-risk changes

### Standard Workflow (Recommended)
```yaml
name: standard
phases:
  - planner
  - coder
  - reviewer
  - tester
```
Use for: Most user stories, new features, refactoring

### Full-Stack Workflow (Complete)
```yaml
name: full-stack
phases:
  - planner
  - architect           # Optional
  - frontend-coder      # Optional
  - backend-coder       # Optional
  - reviewer
  - security-reviewer   # Optional
  - ui-tester          # Optional
  - integration-tester # Optional
```
Use for: Complex features, multi-layer changes, critical paths

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

Ralph automatically detects your CLI:
```bash
# Claude Code
claude --version
# → Uses Task tool

# Codex
codex --version
# → Uses Multi-agents API
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
- **Claude Code** or **Codex**: AI CLI

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

## Troubleshooting

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
- Codex's Multi-agents API
- Modern CI/CD parallel execution patterns
- Git's merge strategies

## Support

- GitHub Issues: [Report bugs](https://github.com/yourusername/ralph-parallel/issues)
- Discussions: [Ask questions](https://github.com/yourusername/ralph-parallel/discussions)
- Documentation: [Read the docs](docs/)

---

# 中文版本

> [English](#ralph-parallel) | **中文**

**Multi-Agent Ralph** - 新一代并行执行 PRD 的自主代理系统

Ralph Parallel 解决了原始 Ralph 的两个根本问题：
1. **并行执行** - 同时执行多个用户故事而非串行
2. **子代理利用** - 正确利用专业化代理（planner、coder、reviewer、tester）

## 状态：Phase 4 完成 ✅

**当前版本**：开发中（6 个阶段的第 4 阶段 - 67% 完成）

### 已完成
- ✅ Phase 1：项目骨架和 CLI 适配
- ✅ Phase 2：核心并行执行引擎
- ✅ Phase 3：带 YAML 解析的工作流系统
- ✅ Phase 4：智能合并策略和冲突解决

### 下一阶段
Phase 5：文档和示例

## 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/yourusername/ralph-parallel
cd ralph-parallel

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

## 核心特性

### 🚀 并行执行
- 同时执行最多 3 个故事
- 智能依赖分析（基于 DAG）
- 每个故事独立的 git 分支
- 完成后自动合并

### 🤖 多代理编排
每个故事由编排器管理 4 个专业代理：
- **Planner** - 创建实现计划
- **Coder** - 遵循 TDD 实现代码
- **Reviewer** - 审查代码质量和安全性
- **Tester** - 运行 E2E 测试和验证

### 🔀 智能冲突解决
三层解决策略：
- **LOW** 严重性 → 自动合并（简单冲突）
- **MEDIUM** 严重性 → AI 解决器（导入冲突、格式化）
- **HIGH** 严重性 → 人工审查（逻辑冲突）

### 📋 灵活的工作流
三个内置工作流 + 自定义工作流支持：
- **simple** - 快速（仅 coder + tester）
- **standard** - 平衡（所有 4 个代理）
- **full-stack** - 完整（包含可选专家）

### 🔧 CLI 兼容性
同时支持：
- Claude Code（通过 Task 工具）
- Codex（通过 Multi-agents API）

## 文档

- [QUICKSTART.md](QUICKSTART.md) - 5 分钟快速开始
- [DESIGN.md](docs/DESIGN.md) - 完整设计文档
- [WORKFLOWS.md](docs/WORKFLOWS.md) - 工作流系统指南
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - 架构深度解析
- [COMPARISON.md](docs/COMPARISON.md) - 与原始 Ralph 对比

## 许可证

MIT License - 查看 [LICENSE](LICENSE) 了解详情

---

**Ralph Parallel** - 自主代理，并行执行 🚀
