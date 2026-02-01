# Raffaello CLI Reference / 命令行参考手册

> **English** | [中文](#中文版本)

This document provides a complete reference for all Raffaello scripts, their usage, parameters, and expected outputs.

---

## Script Categories

### User-Facing Scripts (Direct Use)

| Script | Purpose | Typical Usage |
|--------|---------|---------------|
| `bin/raffaello-start.sh` | **Recommended entry point** - One-click start with auto-monitoring | `./bin/raffaello-start.sh --project-dir /path/to/project` |
| `raffaello.sh` | Main execution script (called internally by start.sh) | `./raffaello.sh --max-parallel 3 --auto-kill` |
| `bin/raffaello-finish.sh` | Stop all processes and optionally merge | `./bin/raffaello-finish.sh --project-dir /path --clean --merge-pass` |
| `bin/raffaello-merge.sh` | Manual merge for specific branches | `./bin/raffaello-merge.sh --project-dir /path merge-pass` |
| `raffaello/kill-all.sh` | Emergency stop all processes | `./raffaello/kill-all.sh --project-dir /path --clean-all` |
| `run-tests.sh` | Run test suites | `./run-tests.sh workflows` |

### Internal Scripts (Generally Not Called Directly)

| Script | Purpose | Called By |
|--------|---------|-----------|
| `orchestrator.sh` | Single story phase orchestration | `raffaello.sh` |
| `merge-stories.sh` | Smart conflict resolution merge (supports AI mode) | `raffaello.sh` (automatic) or manual |
| `raffaello/monitor.sh` | Progress monitoring | `raffaello-start.sh` or manual |
| `raffaello/monitor-kill.sh` | Watchdog monitor with kill capability | `raffaello.sh` (when AUTO_MONITOR_KILL=true) |
| `lib/*.sh` | Library functions | Sourced by other scripts |

---

## Detailed Script Reference

### bin/raffaello-start.sh

**Purpose**: Recommended entry point for running Raffaello. Starts monitor in background and runs raffaello.sh with safe defaults.

**Usage**:
```bash
./bin/raffaello-start.sh [OPTIONS]
```

**Options**:
| Option | Description | Default |
|--------|-------------|---------|
| `--project-dir DIR` | Target project directory | Current directory |
| `--profile PROFILE` | Timing profile: `fast`, `safe`, `very-safe` | `safe` |
| `--iters N` | Maximum global iterations | 30 |
| `--stall-secs S` | No-output threshold (seconds) | From profile |
| `--interval-secs S` | Monitor polling interval | 10 |

**Profiles**:
- `fast`: stall=300s (faster recovery, may kill long silent steps)
- `safe`: stall=600s (recommended default)
- `very-safe`: stall=900s (least likely to kill, slower recovery)

**Example**:
```bash
# Basic usage
./bin/raffaello-start.sh --project-dir ~/my-project

# With custom settings
./bin/raffaello-start.sh --project-dir ~/my-project --profile fast --iters 20

# Override stall threshold
./bin/raffaello-start.sh --project-dir ~/my-project --stall-secs 450
```

**Expected Output**:
```
[raffaello-start] project=/path/to/project
[raffaello-start] project=/path/to/project profile=safe iters=30 stall=600 interval=10
[raffaello-start] monitor pid=12345 (log: .raffaello-logs/monitor.nohup.log)

Second terminal (recommended):
  tail -f .raffaello-logs/monitor.nohup.log
  tail -f .raffaello-logs/STORY-XXX.log
```

---

### raffaello.sh

**Purpose**: Main parallel execution engine. Analyzes dependencies, creates batches, and orchestrates story execution.

**Usage**:
```bash
./raffaello.sh
```

**Environment Variables**:
| Variable | Description | Default |
|----------|-------------|---------|
| `GLOBAL_MAX_ITERATIONS` | Max global iterations | 30 |
| `RAFFAELLO_ASSUME_YES` | Skip interactive prompts | false |
| `AUTO_MONITOR_KILL` | Enable watchdog monitor | false |
| `MONITOR_STALL_SECS` | Stall threshold | 600 |
| `MONITOR_INTERVAL_SECS` | Monitor interval | 10 |
| `MAX_PARALLEL_STORIES` | Max concurrent stories | 3 |

**Example**:
```bash
# Basic usage (interactive)
./raffaello.sh

# Non-interactive with auto-kill
RAFFAELLO_ASSUME_YES=true AUTO_MONITOR_KILL=true ./raffaello.sh

# With custom iterations
GLOBAL_MAX_ITERATIONS=50 ./raffaello.sh
```

**Expected Output**:
```
[INFO] === Raffaello - Starting Execution ===
[INFO] Found 4 incomplete stories
[INFO] Analyzing dependencies...
[INFO] Execution plan: 2 batches

[INFO] === Batch 1 / 2 ===
[INFO] Starting story: US001 - Add Header Component
...
[SUCCESS] All stories complete!
```

---

### bin/raffaello-finish.sh

**Purpose**: Gracefully stop all Raffaello processes and optionally merge completed stories.

**Usage**:
```bash
./bin/raffaello-finish.sh [OPTIONS]
```

**Options**:
| Option | Description |
|--------|-------------|
| `--project-dir DIR` | Target project directory |
| `--merge-pass` | Merge all `passes=true` stories |
| `--clean` | Also clean comm dir + git worktrees |
| `--dry-run` | Print actions without executing |

**Example**:
```bash
# Just stop processes
./bin/raffaello-finish.sh --project-dir ~/my-project

# Stop + clean + merge
./bin/raffaello-finish.sh --project-dir ~/my-project --clean --merge-pass

# Preview what would happen
./bin/raffaello-finish.sh --project-dir ~/my-project --clean --merge-pass --dry-run
```

**Expected Output**:
```
[raffaello-finish] project=/path/to/project
[raffaello-finish] stopping agents/monitors...
[kill-all] sending TERM...
[kill-all] done
[raffaello-finish] ensuring repo hygiene...
[raffaello-finish] merging passes=true stories...
[raffaello-finish] done
```

---

### bin/raffaello-merge.sh

**Purpose**: Manual merge utility for story branches.

**Usage**:
```bash
./bin/raffaello-merge.sh [OPTIONS] COMMAND [STORY_IDS...]
```

**Commands**:
| Command | Description |
|---------|-------------|
| `list` | List stories with `passes=true` |
| `merge-pass` | Merge all `passes=true` stories in order |
| `merge STORY-XXX ...` | Merge specific stories |

**Options**:
| Option | Description |
|--------|-------------|
| `--project-dir DIR` | Target project directory |

**Example**:
```bash
# List completed stories
./bin/raffaello-merge.sh --project-dir ~/my-project list

# Merge all completed
./bin/raffaello-merge.sh --project-dir ~/my-project merge-pass

# Merge specific stories
./bin/raffaello-merge.sh --project-dir ~/my-project merge STORY-011 STORY-012
```

---

### raffaello/kill-all.sh

**Purpose**: Stop all Raffaello processes and optionally clean temporary directories.

**Usage**:
```bash
./raffaello/kill-all.sh [OPTIONS]
```

**Options**:
| Option | Description |
|--------|-------------|
| `--project-dir DIR` | Project directory |
| `--clean-comm` | Remove agent communication state |
| `--clean-worktrees` | Remove git worktrees |
| `--clean-logs` | Remove log files |
| `--clean-all` | All of the above |
| `--dry-run` | Print actions without executing |

**Example**:
```bash
# Just kill processes
./raffaello/kill-all.sh --project-dir ~/my-project

# Kill + full cleanup
./raffaello/kill-all.sh --project-dir ~/my-project --clean-all

# Preview what would be killed
./raffaello/kill-all.sh --project-dir ~/my-project --clean-all --dry-run
```

**Expected Output**:
```
[kill-all] repo=/path/to/raffaello
[kill-all] project=/path/to/project
[kill-all] agent_comm_dir=/tmp/raffaello
[kill-all] matching processes:
12345 bash ./raffaello.sh
12346 claude ...
[kill-all] sending TERM...
[kill-all] done
```

---

### run-tests.sh

**Purpose**: Run Raffaello test suites.

**Usage**:
```bash
./run-tests.sh [MODE]
```

**Modes**:
| Mode | Description |
|------|-------------|
| `quick` | Fast static checks (default) |
| `workflows` | Workflow/agent/dependency tests |
| `e2e` | End-to-end repo checks |
| `suite` | Full improvement suite |
| `unit` | Legacy unit/regression tests |
| `all` | Run all test modes |

**Example**:
```bash
# Quick syntax checks
./run-tests.sh

# Workflow tests only
./run-tests.sh workflows

# Full test suite
./run-tests.sh all
```

**Expected Output**:
```
=== Raffaello Test Runner ===

[1/8] Checking files...
✓ New files created
[2/8] Checking Bash 3.2 compatibility...
✓ Bash 3.2 compatible
...
=== ✓ Quick Checks Passed ===
```

---

### merge-stories.sh

**Purpose**: Merge story branches into main with intelligent conflict resolution. Supports AI-powered merge using Claude Code.

**Usage**:
```bash
./merge-stories.sh [OPTIONS]
```

**Options**:
| Option | Description | Default |
|--------|-------------|---------|
| `--ai` | Use Claude Code to resolve conflicts | false |
| `--report FILE` | Output merge report to FILE | merge-report.md |
| `--help, -h` | Show help message | - |

**Environment Variables**:
| Variable | Description | Default |
|----------|-------------|---------|
| `USE_AI_MERGE` | Enable AI merge (same as --ai) | false |
| `MAIN_BRANCH` | Target branch to merge into | auto-detect (main/master) |
| `AGENT_COMM_DIR` | Communication directory | /tmp/raffaello |

**Example**:
```bash
# Standard merge (manual conflict resolution)
./merge-stories.sh

# AI-powered merge (recommended for complex conflicts)
./merge-stories.sh --ai

# AI merge with custom report file
./merge-stories.sh --ai --report my-merge-report.md
```

**Expected Output (AI mode)**:
```
[MERGE] Starting intelligent merge process...
[MERGE] AI merge mode enabled (--ai)
[MERGE] Found 3 story branches to merge

[MERGE] Merging branch: story-STORY-007
[MERGE] Fast-forward not possible, attempting regular merge...
[MERGE] Merge conflict detected in story-STORY-007
Conflict Analysis:
[HIGH] src/App.css → manual-review
[HIGH] src/App.test.tsx → manual-review
[LOW] src/App.tsx → auto-merge
[MERGE] Using Claude Code to resolve HIGH severity conflicts...
[MERGE] Spawning Claude Code to resolve conflicts (timeout: 600s)...
[MERGE] Claude Code finished processing
[MERGE] All conflicts resolved by Claude Code
[master f13b144] Merge story-STORY-007 into master
Deleted branch story-STORY-007 (was f2daef7).

[MERGE] === Merge Summary ===
[MERGE] Successfully merged: 3
[MERGE] All branches merged successfully!
```

**Conflict Severity Levels**:
- **LOW**: Simple conflicts (<5% of file) - auto-merged
- **MEDIUM**: Moderate conflicts (imports, config) - AI resolver
- **HIGH**: Complex conflicts (logic changes) - AI resolver with --ai, otherwise manual

**Notes**:
- Without `--ai`, HIGH severity conflicts require manual resolution
- With `--ai`, Claude Code attempts to resolve ALL conflicts intelligently
- Timeout is 600 seconds per merge operation
- Successfully merged branches are automatically deleted
- A merge report is generated at the end

---

### raffaello/monitor.sh

**Purpose**: Monitor story/agent progress in real-time (observe-only mode).

**Usage**:
```bash
./raffaello/monitor.sh [PROJECT_DIR] [--stdout]
```

**Environment Variables**:
| Variable | Description | Default |
|----------|-------------|---------|
| `INTERVAL_SECS` | Polling interval | 10 |
| `STALL_SECS` | Stall detection threshold | 600 |
| `SHOW_STALE_STORIES` | Show historical stories | true |
| `SHOW_INACTIVE` | Show inactive phases | true |

**Example**:
```bash
# Background with nohup (recommended)
nohup ./raffaello/monitor.sh ~/my-project > .raffaello-logs/monitor.nohup.log 2>&1 &

# Foreground to terminal
SHOW_STALE_STORIES=false ./raffaello/monitor.sh ~/my-project --stdout
```

---

## Common Workflows

### 1. Standard Run (Recommended)

```bash
cd ~/my-project
./bin/raffaello-start.sh --project-dir .

# In another terminal:
tail -f .raffaello-logs/monitor.nohup.log
```

### 2. Manual Control

```bash
cd ~/my-project

# Start manually
./raffaello.sh

# Monitor in another terminal
tail -f .raffaello-logs/STORY-XXX.log

# When done, stop and merge
./bin/raffaello-finish.sh --project-dir . --merge-pass
```

### 3. Emergency Stop

```bash
# Kill everything immediately
./raffaello/kill-all.sh --project-dir ~/my-project --clean-all
```

### 4. Resume After Failure

```bash
# Check what's left
jq '.userStories[] | select(.passes == false) | .id' prd.json

# Clean stale state
./raffaello/kill-all.sh --project-dir . --clean-comm

# Resume
./bin/raffaello-start.sh --project-dir .
```

---

# 中文版本

## 脚本分类

### 用户直接使用的脚本

| 脚本 | 用途 | 典型用法 |
|------|------|----------|
| `bin/raffaello-start.sh` | **推荐入口** - 一键启动，自动监控 | `./bin/raffaello-start.sh --project-dir /path/to/project` |
| `raffaello.sh` | 主执行脚本（start.sh 内部调用） | `./raffaello.sh --max-parallel 3 --auto-kill` |
| `bin/raffaello-finish.sh` | 停止所有进程并可选合并 | `./bin/raffaello-finish.sh --project-dir /path --clean --merge-pass` |
| `bin/raffaello-merge.sh` | 手动合并指定分支 | `./bin/raffaello-merge.sh --project-dir /path merge-pass` |
| `raffaello/kill-all.sh` | 紧急停止所有进程 | `./raffaello/kill-all.sh --project-dir /path --clean-all` |
| `run-tests.sh` | 运行测试 | `./run-tests.sh workflows` |

### 内部使用的脚本（用户一般不直接调用）

| 脚本 | 用途 | 调用者 |
|------|------|--------|
| `orchestrator.sh` | 单 story 的 phase 编排 | `raffaello.sh` |
| `merge-stories.sh` | 智能冲突解决合并（支持 AI 模式） | `raffaello.sh` 自动调用或手动 |
| `raffaello/monitor.sh` | 监控进度 | `raffaello-start.sh` 或手动 |
| `raffaello/monitor-kill.sh` | 带杀进程能力的监控 | `raffaello.sh`（当 AUTO_MONITOR_KILL=true） |
| `lib/*.sh` | 库函数 | 被其他脚本 source |

---

## 详细脚本参考

### bin/raffaello-start.sh

**用途**：推荐的 Raffaello 启动入口。后台启动监控，用安全默认参数运行 raffaello.sh。

**用法**：
```bash
./bin/raffaello-start.sh [OPTIONS]
```

**参数**：
| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--project-dir DIR` | 目标项目目录 | 当前目录 |
| `--profile PROFILE` | 时间配置：`fast`, `safe`, `very-safe` | `safe` |
| `--iters N` | 最大全局迭代次数 | 30 |
| `--stall-secs S` | 无输出阈值（秒） | 来自 profile |
| `--interval-secs S` | 监控轮询间隔 | 10 |

**Profile 说明**：
- `fast`：stall=300s（快速恢复，可能误杀长时间无输出的步骤）
- `safe`：stall=600s（推荐默认）
- `very-safe`：stall=900s（最不容易误杀，恢复较慢）

**示例**：
```bash
# 基本用法
./bin/raffaello-start.sh --project-dir ~/my-project

# 自定义设置
./bin/raffaello-start.sh --project-dir ~/my-project --profile fast --iters 20
```

---

### bin/raffaello-finish.sh

**用途**：优雅停止所有 Raffaello 进程，可选合并完成的 story。

**用法**：
```bash
./bin/raffaello-finish.sh [OPTIONS]
```

**参数**：
| 参数 | 说明 |
|------|------|
| `--project-dir DIR` | 目标项目目录 |
| `--merge-pass` | 合并所有 `passes=true` 的 story |
| `--clean` | 同时清理通信目录 + git worktrees |
| `--dry-run` | 只打印操作，不执行 |

**示例**：
```bash
# 只停进程
./bin/raffaello-finish.sh --project-dir ~/my-project

# 停 + 清理 + 合并
./bin/raffaello-finish.sh --project-dir ~/my-project --clean --merge-pass

# 预览会做什么
./bin/raffaello-finish.sh --project-dir ~/my-project --clean --merge-pass --dry-run
```

---

### raffaello/kill-all.sh

**用途**：停止所有 Raffaello 进程，可选清理临时目录。

**用法**：
```bash
./raffaello/kill-all.sh [OPTIONS]
```

**参数**：
| 参数 | 说明 |
|------|------|
| `--project-dir DIR` | 项目目录 |
| `--clean-comm` | 删除 agent 通信状态 |
| `--clean-worktrees` | 删除 git worktrees |
| `--clean-logs` | 删除日志文件 |
| `--clean-all` | 以上全部 |
| `--dry-run` | 只打印操作，不执行 |

**示例**：
```bash
# 只杀进程
./raffaello/kill-all.sh --project-dir ~/my-project

# 杀进程 + 全部清理
./raffaello/kill-all.sh --project-dir ~/my-project --clean-all
```

---

### merge-stories.sh

**用途**：将 story 分支合并到 main，支持智能冲突解决。可使用 Claude Code 进行 AI 合并。

**用法**：
```bash
./merge-stories.sh [OPTIONS]
```

**参数**：
| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--ai` | 使用 Claude Code 解决冲突 | false |
| `--report FILE` | 输出合并报告到 FILE | merge-report.md |
| `--help, -h` | 显示帮助信息 | - |

**环境变量**：
| 变量 | 说明 | 默认值 |
|------|------|--------|
| `USE_AI_MERGE` | 启用 AI 合并（同 --ai） | false |
| `MAIN_BRANCH` | 合并目标分支 | 自动检测 (main/master) |
| `AGENT_COMM_DIR` | 通信目录 | /tmp/raffaello |

**示例**：
```bash
# 标准合并（手动解决冲突）
./merge-stories.sh

# AI 智能合并（推荐用于复杂冲突）
./merge-stories.sh --ai

# AI 合并 + 自定义报告文件
./merge-stories.sh --ai --report my-merge-report.md
```

**输出示例（AI 模式）**：
```
[MERGE] Starting intelligent merge process...
[MERGE] AI merge mode enabled (--ai)
[MERGE] Found 3 story branches to merge

[MERGE] Merging branch: story-STORY-007
Conflict Analysis:
[HIGH] src/App.css → manual-review
[HIGH] src/App.test.tsx → manual-review
[LOW] src/App.tsx → auto-merge
[MERGE] Using Claude Code to resolve HIGH severity conflicts...
[MERGE] Spawning Claude Code to resolve conflicts (timeout: 600s)...
[MERGE] Claude Code finished processing
[MERGE] All conflicts resolved by Claude Code
[master f13b144] Merge story-STORY-007 into master
Deleted branch story-STORY-007 (was f2daef7).

[MERGE] === Merge Summary ===
[MERGE] Successfully merged: 3
[MERGE] All branches merged successfully!
```

**冲突严重程度**：
- **LOW**：简单冲突（<5% 文件）- 自动合并
- **MEDIUM**：中等冲突（imports, config）- AI 解决
- **HIGH**：复杂冲突（逻辑修改）- 使用 --ai 时 AI 解决，否则手动

**注意事项**：
- 不带 `--ai` 时，HIGH 严重性冲突需要手动解决
- 带 `--ai` 时，Claude Code 尝试智能解决所有冲突
- 每次合并操作超时时间 600 秒
- 成功合并的分支会自动删除
- 最后会生成合并报告

---

## 常见工作流

### 1. 标准运行（推荐）

```bash
cd ~/my-project
./bin/raffaello-start.sh --project-dir .

# 在另一个终端：
tail -f .raffaello-logs/monitor.nohup.log
```

### 2. 手动控制

```bash
cd ~/my-project

# 手动启动
./raffaello.sh

# 在另一个终端监控
tail -f .raffaello-logs/STORY-XXX.log

# 完成后停止并合并
./bin/raffaello-finish.sh --project-dir . --merge-pass
```

### 3. 紧急停止

```bash
# 立即杀掉所有进程
./raffaello/kill-all.sh --project-dir ~/my-project --clean-all
```

### 4. 失败后恢复

```bash
# 检查剩余未完成的 story
jq '.userStories[] | select(.passes == false) | .id' prd.json

# 清理残留状态
./raffaello/kill-all.sh --project-dir . --clean-comm

# 继续运行
./bin/raffaello-start.sh --project-dir .
```

### 5. AI 智能合并（解决冲突）

```bash
cd ~/my-project

# 确保在 main/master 分支
git checkout main

# 使用 AI 合并所有 story 分支
./merge-stories.sh --ai

# 合并完成后运行测试
npm test
```

---

**See also**: [RAFFAELLO-RUNBOOK.md](RAFFAELLO-RUNBOOK.md) for step-by-step operational guide.
