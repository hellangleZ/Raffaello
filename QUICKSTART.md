# Ralph Parallel - Quick Start Guide

> **English** | [中文](#中文版本)

Get Ralph Parallel up and running in 5 minutes!

## Prerequisites

- **macOS** or **Linux**
- **Bash** 3.2+
- **git** 2.0+
- Basic understanding of git and bash

## Installation

### Step 1: Clone Repository

```bash
git clone https://github.com/yourusername/ralph-parallel
cd ralph-parallel
```

### Step 2: Install Dependencies

```bash
# macOS
brew install jq yq

# Linux (Ubuntu/Debian)
sudo apt-get install jq
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# Verify installation
jq --version    # Should show jq-1.x
yq --version    # Should show yq (https://github.com/mikefarah/yq/) version 4.x
```

### Step 3: Verify CLI

```bash
# Check which CLI you have
./lib/detect-cli.sh

# Output should be:
# Detected CLI: claude-code
# Multi-agents support: ✓ Enabled
```

If you don't have Claude Code installed:
- **Claude Code**: Download from https://claude.ai/code

### Step 4: Test System

```bash
# Run automated tests
./test-workflows.sh

# Should see:
# ✓ List workflows
# ✓ Validate workflows
# ✓ Parse workflows
# ... (8 tests total)
# === All Tests Passed! ===
```

## Your First PRD

### Option 1: Use Example PRD

```bash
# Copy example PRD
cp prd.json.example prd.json

# View the example
cat prd.json
```

### Option 2: Create Simple PRD

Create `prd.json`:
```json
{
  "projectName": "Todo App",
  "branchName": "main",
  "userStories": [
    {
      "id": "US001",
      "title": "Add task creation",
      "description": "Users should be able to create new tasks with a title and description",
      "workflow": "simple",
      "dependencies": [],
      "passes": false
    },
    {
      "id": "US002",
      "title": "Add task deletion",
      "description": "Users should be able to delete tasks",
      "workflow": "simple",
      "dependencies": ["US001"],
      "passes": false
    }
  ]
}
```

## Running Ralph Parallel

### Basic Execution

```bash
# Analyze dependencies first (optional)
./lib/dependency-analyzer.sh prd.json

# Run Ralph Parallel
./ralph.sh
```

You'll see output like:
```
[RALPH] Starting Ralph Parallel execution...
[RALPH] Found 2 stories to implement
[RALPH] Analyzing dependencies...
[RALPH] Created 2 batches:
[RALPH]   Batch 1: US001
[RALPH]   Batch 2: US002 (depends on US001)

[RALPH] Executing Batch 1 (1 stories in parallel)...
[STORY] Executing story US001: Add task creation
[STORY]   Using workflow: simple
[ORCH] Phase 1: coder
  ... (agent working) ...
[ORCH] Phase 2: tester
  ... (agent working) ...
[STORY] ✓ Story US001 complete

[RALPH] Executing Batch 2 (1 stories in parallel)...
[STORY] Executing story US002: Add task deletion
  ... (same flow) ...
[STORY] ✓ Story US002 complete

[MERGE] Merging 2 story branches...
[MERGE] ✓ story-US001 merged (fast-forward)
[MERGE] ✓ story-US002 merged (fast-forward)

[RALPH] === All Stories Complete! ===
```

### Monitor Progress

While Ralph is running, you can monitor in another terminal:
```bash
# Watch progress log
tail -f progress.txt

# Check agent communication
ls -la /tmp/ralph-parallel/

# Check git branches
git branch
# Output:
#   * main
#   story-US001
#   story-US002

# Check PRD status
jq '.userStories[] | {id, passes}' prd.json
```

## Understanding Workflows

Ralph Parallel has 3 built-in workflows:

### Simple Workflow (Fastest)
```yaml
name: simple
phases:
  - coder
  - tester
```
**Use for**: Bug fixes, simple features, low-risk changes
**Time**: ~15-20 min per story

### Standard Workflow (Recommended)
```yaml
name: standard
phases:
  - planner
  - coder
  - reviewer
  - tester
```
**Use for**: Most user stories, new features
**Time**: ~25-30 min per story

### Full-Stack Workflow (Complete)
```yaml
name: full-stack
phases:
  - planner
  - architect
  - coder
  - reviewer
  - tester
```
**Use for**: Complex features, critical paths
**Time**: ~40-50 min per story

To use a specific workflow, set it in your PRD:
```json
{
  "id": "US001",
  "workflow": "standard",
  ...
}
```

## Handling Conflicts

If merge conflicts occur, Ralph will:

1. **Analyze severity** (LOW/MEDIUM/HIGH)
2. **Auto-merge** if LOW severity
3. **Use AI resolver** if MEDIUM severity
4. **Escalate to you** if HIGH severity

### Manual Conflict Resolution

If Ralph can't auto-resolve:
```bash
# View conflict analysis
./lib/conflict-analyzer.sh analyze

# Output shows severity and recommendations
# [LOW] file1.js → auto-merge
# [MEDIUM] file2.js → ai-resolver
# [HIGH] file3.js → manual-review

# Resolve manually if needed
git checkout main
git merge story-US001

# Fix conflicts in editor
vim file3.js

# Stage and commit
git add file3.js
git commit -m "Resolve conflicts from story-US001"
```

## Configuration

### Environment Variables

Create `.env` file (optional):
```bash
# Maximum parallel stories
MAX_PARALLEL_STORIES=3

# Communication directory
AGENT_COMM_DIR=/tmp/ralph-parallel

# Main branch
MAIN_BRANCH=main
```

Load before running:
```bash
source .env
./ralph.sh
```

### Custom Workflow

Create `workflows/my-workflow.yaml`:
```yaml
name: my-workflow
description: My custom workflow
phases:
  - planner
  - coder
  - tester

retry_policy:
  coder:
    max_attempts: 2
```

Validate:
```bash
./lib/workflow-parser.sh validate my-workflow
```

Use in PRD:
```json
{
  "id": "US001",
  "workflow": "my-workflow",
  ...
}
```

## Common Commands

```bash
# List available workflows
./lib/workflow-parser.sh list

# Validate PRD format
jq . prd.json

# Analyze dependencies
./lib/dependency-analyzer.sh prd.json

# Check agent availability
./lib/load-agents.sh

# View conflict severity
./lib/conflict-analyzer.sh severity src/app.js

# Merge branches manually
./merge-stories.sh

# Clean up branches
git branch | grep 'story-' | xargs git branch -d
```

## Troubleshooting

### Issue: Stories Not Executing

**Symptom**: Ralph starts but no stories execute

**Solution**:
```bash
# Check PRD format
jq . prd.json

# Ensure stories have passes=false
jq '.userStories[] | {id, passes}' prd.json

# Check dependencies are valid
jq '.userStories[] | {id, dependencies}' prd.json
```

### Issue: Agents Not Found

**Symptom**: `ERROR: Agent 'planner' not found`

**Solution**:
```bash
# Check agent directory
ls -la agents/

# Should see: planner.md, coder.md, reviewer.md, tester.md

# Check agent discovery
./lib/load-agents.sh
```

### Issue: Merge Conflicts

**Symptom**: `[MERGE] ✗ Manual review required`

**Solution**:
```bash
# View conflict details
./lib/conflict-analyzer.sh analyze

# Resolve manually
git checkout main
git merge story-US001
# ... fix conflicts ...
git add .
git commit
```

### Issue: Workflow Not Found

**Symptom**: `ERROR: Workflow 'standard' not found`

**Solution**:
```bash
# List available workflows
./lib/workflow-parser.sh list

# Check workflow files exist
ls -la workflows/
```

## Next Steps

Now that you have Ralph Parallel running:

1. **Read the full documentation**:
   - [DESIGN.md](docs/DESIGN.md) - Complete design
   - [WORKFLOWS.md](docs/WORKFLOWS.md) - Workflow guide
   - [ARCHITECTURE.md](docs/ARCHITECTURE.md) - Architecture
   - [COMPARISON.md](docs/COMPARISON.md) - vs Original Ralph

2. **Create your own PRD**:
   - Start with 2-3 simple stories
   - Add dependencies between them
   - Try different workflows

3. **Customize workflows**:
   - Create custom workflows for your project
   - Add optional agents from ~/.claude/agents/

4. **Optimize for your project**:
   - Adjust MAX_PARALLEL_STORIES
   - Configure retry policies
   - Add project-specific agents

## Getting Help

- **Documentation**: Read the docs/ directory
- **GitHub Issues**: Report bugs at github.com/yourusername/ralph-parallel/issues
- **Discussions**: Ask questions at github.com/yourusername/ralph-parallel/discussions

## Example Session

Here's a complete example session:

```bash
# 1. Setup
cd ~/projects/my-app
git clone https://github.com/yourusername/ralph-parallel
cd ralph-parallel

# 2. Create PRD
cat > prd.json <<EOF
{
  "projectName": "My App",
  "branchName": "main",
  "userStories": [
    {
      "id": "US001",
      "title": "Add user login",
      "description": "Implement login form with email/password",
      "workflow": "standard",
      "dependencies": [],
      "passes": false
    },
    {
      "id": "US002",
      "title": "Add user profile",
      "description": "Show user profile page",
      "workflow": "simple",
      "dependencies": ["US001"],
      "passes": false
    }
  ]
}
EOF

# 3. Run Ralph
./ralph.sh

# 4. Monitor (in another terminal)
tail -f progress.txt

# 5. When done, check results
git log --oneline
# Should see commits for US001 and US002

# 6. Verify PRD updated
jq '.userStories[] | {id, passes}' prd.json
# Should show passes=true for both
```

Congratulations! You've successfully run Ralph Parallel!

---

# 中文版本

> [English](#ralph-parallel---quick-start-guide) | **中文**

在 5 分钟内让 Ralph Parallel 运行起来！

## 先决条件

- **macOS** 或 **Linux**
- **Bash** 3.2+
- **git** 2.0+
- 基本了解 git 和 bash

## 安装

### 步骤 1：克隆仓库

```bash
git clone https://github.com/yourusername/ralph-parallel
cd ralph-parallel
```

### 步骤 2：安装依赖

```bash
# macOS
brew install jq yq

# Linux (Ubuntu/Debian)
sudo apt-get install jq
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq

# 验证安装
jq --version    # 应显示 jq-1.x
yq --version    # 应显示 yq (https://github.com/mikefarah/yq/) version 4.x
```

### 步骤 3：验证 CLI

```bash
# 检查你有哪个 CLI
./lib/detect-cli.sh

# 输出应为：
# Detected CLI: claude-code
# Multi-agents support: ✓ Enabled
```

如果你还没有安装 Claude Code:
- **Claude Code**: 从 https://claude.ai/code 下载

### 步骤 4: 测试系统

```bash
# 运行自动化测试
./test-workflows.sh

# 应该看到:
# ✓ List workflows
# ✓ Validate workflows
# ✓ Parse workflows
# ... (共8个测试)
# === All Tests Passed! ===
```

## 你的第一个 PRD

### 选项 1: 使用示例 PRD

```bash
# 复制示例 PRD
cp prd.json.example prd.json

# 查看示例
cat prd.json
```

### 选项 2: 创建简单 PRD

创建 `prd.json`:
```json
{
  "projectName": "Todo App",
  "branchName": "main",
  "userStories": [
    {
      "id": "US001",
      "title": "添加任务创建功能",
      "description": "用户应该能够使用标题和描述创建新任务",
      "workflow": "simple",
      "dependencies": [],
      "passes": false
    },
    {
      "id": "US002",
      "title": "添加任务删除功能",
      "description": "用户应该能够删除任务",
      "workflow": "simple",
      "dependencies": ["US001"],
      "passes": false
    }
  ]
}
```

## 运行 Ralph Parallel

### 基本执行

```bash
# 首先分析依赖关系（可选）
./lib/dependency-analyzer.sh prd.json

# 运行 Ralph Parallel
./ralph.sh
```

你会看到类似这样的输出:
```
[RALPH] 开始 Ralph Parallel 执行...
[RALPH] 找到 2 个待实现的 stories
[RALPH] 分析依赖关系...
[RALPH] 创建了 2 个批次:
[RALPH]   Batch 1: US001
[RALPH]   Batch 2: US002 (依赖 US001)

[RALPH] 执行 Batch 1 (1 个stories并行)...
[STORY] 执行 story US001: 添加任务创建功能
[STORY]   使用工作流: simple
[ORCH] Phase 1: coder
  ... (agent 工作中) ...
[ORCH] Phase 2: tester
  ... (agent 工作中) ...
[STORY] ✓ Story US001 完成

[RALPH] 执行 Batch 2 (1 个stories并行)...
[STORY] 执行 story US002: 添加任务删除功能
  ... (相同流程) ...
[STORY] ✓ Story US002 完成

[MERGE] 合并 2 个story分支...
[MERGE] ✓ story-US001 合并完成 (fast-forward)
[MERGE] ✓ story-US002 合并完成 (fast-forward)

[RALPH] === 所有 Stories 完成! ===
```

### 监控进度

在 Ralph 运行时,你可以在另一个终端中监控:
```bash
# 查看进度日志
tail -f progress.txt

# 检查 agent 通信
ls -la /tmp/ralph-parallel/

# 检查 git 分支
git branch
# 输出:
#   * main
#   story-US001
#   story-US002

# 检查 PRD 状态
jq '.userStories[] | {id, passes}' prd.json
```

## 理解工作流

Ralph Parallel 有 3 个内置工作流:

### Simple Workflow (最快)
```yaml
name: simple
phases:
  - coder
  - tester
```
**适用于**: Bug 修复, 简单功能, 低风险变更
**时间**: 每个story约15-20分钟

### Standard Workflow (推荐)
```yaml
name: standard
phases:
  - planner
  - coder
  - reviewer
  - tester
```
**适用于**: 大多数用户故事, 新功能
**时间**: 每个story约25-30分钟

### Full-Stack Workflow (完整)
```yaml
name: full-stack
phases:
  - planner
  - architect
  - coder
  - reviewer
  - tester
```
**适用于**: 复杂功能, 关键路径
**时间**: 每个story约40-50分钟

要使用特定工作流,在 PRD 中设置:
```json
{
  "id": "US001",
  "workflow": "standard",
  ...
}
```

## 处理冲突

如果发生合并冲突, Ralph 会:

1. **分析严重程度** (LOW/MEDIUM/HIGH)
2. **自动合并** 如果是 LOW 严重性
3. **使用 AI 解决器** 如果是 MEDIUM 严重性
4. **升级给你处理** 如果是 HIGH 严重性

### 手动冲突解决

如果 Ralph 无法自动解决:
```bash
# 查看冲突分析
./lib/conflict-analyzer.sh analyze

# 输出显示严重性和建议
# [LOW] file1.js → auto-merge
# [MEDIUM] file2.js → ai-resolver
# [HIGH] file3.js → manual-review

# 如果需要手动解决
git checkout main
git merge story-US001

# 在编辑器中修复冲突
vim file3.js

# 暂存并提交
git add file3.js
git commit -m "解决 story-US001 的冲突"
```

## 配置

### 环境变量

创建 `.env` 文件（可选）:
```bash
# 最大并行 stories 数
MAX_PARALLEL_STORIES=3

# 通信目录
AGENT_COMM_DIR=/tmp/ralph-parallel

# 主分支
MAIN_BRANCH=main
```

使用前加载:
```bash
source .env
./ralph.sh
```

### 自定义工作流

创建 `workflows/my-workflow.yaml`:
```yaml
name: my-workflow
description: 我的自定义工作流
phases:
  - planner
  - coder
  - tester

retry_policy:
  coder:
    max_attempts: 2
```

验证:
```bash
./lib/workflow-parser.sh validate my-workflow
```

在 PRD 中使用:
```json
{
  "id": "US001",
  "workflow": "my-workflow",
  ...
}
```

## 常用命令

```bash
# 列出可用的工作流
./lib/workflow-parser.sh list

# 验证 PRD 格式
jq . prd.json

# 分析依赖关系
./lib/dependency-analyzer.sh prd.json

# 检查 agent 可用性
./lib/load-agents.sh

# 查看冲突严重性
./lib/conflict-analyzer.sh severity src/app.js

# 手动合并分支
./merge-stories.sh

# 清理分支
git branch | grep 'story-' | xargs git branch -d
```

## 故障排除

### 问题: Stories 未执行

**症状**: Ralph 启动但没有 stories 执行

**解决方案**:
```bash
# 检查 PRD 格式
jq . prd.json

# 确保 stories 有 passes=false
jq '.userStories[] | {id, passes}' prd.json

# 检查依赖关系是否有效
jq '.userStories[] | {id, dependencies}' prd.json
```

### 问题: Agents 未找到

**症状**: `ERROR: Agent 'planner' not found`

**解决方案**:
```bash
# 检查 agent 目录
ls -la agents/

# 应该看到: planner.md, coder.md, reviewer.md, tester.md

# 检查 agent 发现
./lib/load-agents.sh
```

### 问题: 合并冲突

**症状**: `[MERGE] ✗ 需要手动审查`

**解决方案**:
```bash
# 查看冲突详情
./lib/conflict-analyzer.sh analyze

# 手动解决
git checkout main
git merge story-US001
# ... 修复冲突 ...
git add .
git commit
```

### 问题: 工作流未找到

**症状**: `ERROR: Workflow 'standard' not found`

**解决方案**:
```bash
# 列出可用的工作流
./lib/workflow-parser.sh list

# 检查工作流文件是否存在
ls -la workflows/
```

## 下一步

现在你已经让 Ralph Parallel 运行起来了:

1. **阅读完整文档**:
   - [DESIGN.md](docs/DESIGN.md) - 完整设计
   - [WORKFLOWS.md](docs/WORKFLOWS.md) - 工作流指南
   - [ARCHITECTURE.md](docs/ARCHITECTURE.md) - 架构
   - [COMPARISON.md](docs/COMPARISON.md) - vs 原始 Ralph

2. **创建你自己的 PRD**:
   - 从 2-3 个简单的 stories 开始
   - 在它们之间添加依赖关系
   - 尝试不同的工作流

3. **自定义工作流**:
   - 为你的项目创建自定义工作流
   - 从 ~/.claude/agents/ 添加可选 agents

4. **为你的项目优化**:
   - 调整 MAX_PARALLEL_STORIES
   - 配置重试策略
   - 添加项目特定的 agents

## 获取帮助

- **文档**: 阅读 docs/ 目录
- **GitHub Issues**: 在 github.com/yourusername/ralph-parallel/issues 报告 bug
- **讨论**: 在 github.com/yourusername/ralph-parallel/discussions 提问

## 完整示例会话

这是一个完整的示例会话:

```bash
# 1. 设置
cd ~/projects/my-app
git clone https://github.com/yourusername/ralph-parallel
cd ralph-parallel

# 2. 创建 PRD
cat > prd.json <<EOF
{
  "projectName": "我的应用",
  "branchName": "main",
  "userStories": [
    {
      "id": "US001",
      "title": "添加用户登录",
      "description": "使用邮箱/密码实现登录表单",
      "workflow": "standard",
      "dependencies": [],
      "passes": false
    },
    {
      "id": "US002",
      "title": "添加用户资料",
      "description": "显示用户资料页面",
      "workflow": "simple",
      "dependencies": ["US001"],
      "passes": false
    }
  ]
}
EOF

# 3. 运行 Ralph
./ralph.sh

# 4. 监控（在另一个终端）
tail -f progress.txt

# 5. 完成后检查结果
git log --oneline
# 应该看到 US001 和 US002 的提交

# 6. 验证 PRD 已更新
jq '.userStories[] | {id, passes}' prd.json
# 应该显示两者都是 passes=true
```

恭喜! 你已成功运行 Ralph Parallel!

---

**Ralph Parallel** - 5 分钟快速开始 🚀
