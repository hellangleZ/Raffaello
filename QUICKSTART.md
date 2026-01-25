# Ralph Parallel - Quick Start Guide

> **English** | [中文](#中文版本)

Get Ralph Parallel up and running in 5 minutes!

## Prerequisites

- **macOS** or **Linux**
- **Bash** 3.2+
- **git** 2.0+
- **Claude Code** or **Codex** CLI installed
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
# Detected CLI: claude-code (or codex)
# Multi-agents support: ✓ Enabled
```

If you don't have Claude Code or Codex installed:
- **Claude Code**: Download from https://claude.ai/code
- **Codex**: Follow instructions at your Codex provider

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
- 已安装 **Claude Code** 或 **Codex** CLI
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
# Detected CLI: claude-code (或 codex)
# Multi-agents support: ✓ Enabled
```

*(继续中文翻译...)*

---

**Ralph Parallel** - 5 分钟快速开始 🚀
