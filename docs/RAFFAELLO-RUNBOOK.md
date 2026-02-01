# Raffaello Runbook (Start → Monitor → Finish)

This directory is a Raffaello project workspace.

Raffaello runs each user story on its own git branch (`story-<STORY-ID>`) inside a git worktree under `.raffaello-worktrees/`. The main project directory will **not** automatically contain story code until you merge those branches.

---

# Raffaello 运行手册（开始 → 监控 → 收尾）

这个目录是 Raffaello 的项目工作区。

Raffaello 会把每个用户故事放到独立的 git 分支（`story-<STORY-ID>`）里运行，并且把代码放到 `.raffaello-worktrees/` 下的 git worktree 目录中。主目录在你 **merge 分支回主分支之前**，通常不会出现故事代码，这是正常现象。


## 0) Prerequisites

- Be in the project directory: `cd <YOUR_PROJECT_DIR>`
- Ensure your PRD exists: `prd.json`

## 0) 前置条件

- 进入项目目录：`cd <YOUR_PROJECT_DIR>`
- 确保 PRD 文件存在：`prd.json`


## 1) Start a run

Use the one-button starter:

```bash
cd <YOUR_PROJECT_DIR>
./bin/raffaello-start.sh --project-dir .
```

Optional flags:

```bash
./bin/raffaello-start.sh --project-dir . --iters 30 --stall-secs 300 --interval-secs 10
```

What it does:

- Starts the monitor in the background (nohup) and writes to `.raffaello-logs/monitor.nohup.log`.
- Runs `./raffaello.sh` in the foreground with safe defaults (`RAFFAELLO_ASSUME_YES=true`, auto monitor-kill enabled).

## 1) 开始一轮

一键启动：

```bash
cd <YOUR_PROJECT_DIR>
./bin/raffaello-start.sh --project-dir .
```

可选参数：

```bash
./bin/raffaello-start.sh --project-dir . --iters 30 --stall-secs 300 --interval-secs 10
```

它做的事情：

- 后台启动 monitor（nohup），日志写入 `.raffaello-logs/monitor.nohup.log`
- 前台运行 `./raffaello.sh`（带默认参数，跳过交互确认 + 自动 watch-dog）

### Parameters / 参数说明

`raffaello-start.sh` flags:

- `--iters N`
  - EN: Same as `GLOBAL_MAX_ITERATIONS=N`. Max global iterations Raffaello will run before stopping.
  - CN: 等价于 `GLOBAL_MAX_ITERATIONS=N`。Raffaello 全局最多迭代次数（跑完一轮如果还有未完成故事，会继续下一轮；到 N 次就停止）。
- `--stall-secs S`
  - EN: Same as `MONITOR_STALL_SECS=S`. No-output threshold for a phase (seconds).
  - CN: 等价于 `MONITOR_STALL_SECS=S`。某个 phase 多久没有新输出算“卡死”（秒）。
- `--interval-secs S`
  - EN: Same as `MONITOR_INTERVAL_SECS=S`. Monitor polling interval in seconds.
  - CN: 等价于 `MONITOR_INTERVAL_SECS=S`。monitor 检查间隔（秒）。

Environment variables used by the starter:

- `RAFFAELLO_ASSUME_YES=true`
  - EN: Skip interactive confirmations.
  - CN: 跳过交互确认（适合一键启动/非交互环境）。
- `AUTO_MONITOR_KILL=true`
  - EN: Enables a watchdog that terminates stalled agents.
  - CN: 启用看门狗：当 agent 卡死（长期无输出）时自动结束它，避免整轮挂死。


## 2) Monitor progress

Open a second terminal and run:

```bash
cd <YOUR_PROJECT_DIR>
tail -f .raffaello-logs/monitor.nohup.log
```

To follow a specific story:

```bash
tail -f .raffaello-logs/STORY-XXX.log
```

Useful low-level debugging (per story):

```bash
ls -la /tmp/raffaello/STORY-XXX/
tail -n 80 /tmp/raffaello/STORY-XXX/coder-output.txt
cat /tmp/raffaello/STORY-XXX/coder.pid
```

## 2) 监控进度

建议打开第二个终端：

```bash
cd <YOUR_PROJECT_DIR>
tail -f .raffaello-logs/monitor.nohup.log
```

关注单个故事：

```bash
tail -f .raffaello-logs/STORY-XXX.log
```

更底层的排查（每个 story）：

```bash
ls -la /tmp/raffaello/STORY-XXX/
tail -n 80 /tmp/raffaello/STORY-XXX/coder-output.txt
cat /tmp/raffaello/STORY-XXX/coder.pid
```

### Monitor knobs / Monitor 常用参数

- `SHOW_STALE_STORIES=false`
  - EN: Hide stale historical story directories under `/tmp/raffaello`.
  - CN: 隐藏历史残留 story 目录，避免输出“看起来很乱”。
- `SHOW_INACTIVE=false`
  - EN: Hide inactive per-phase lines.
  - CN: 隐藏 inactive 的 phase 行，减少噪音。


## 3) Inspect the generated code (without merging)

Story outputs live in worktrees:

```bash
cd .raffaello-worktrees/STORY-011
git log --oneline -n 10
ls
```

Run tests in a worktree (if the story created/updated them):

```bash
cd .raffaello-worktrees/STORY-011
npm test
```

## 3) 查看产物代码（不 merge 也能验收）

每个 story 的代码在 worktree 目录：

```bash
cd .raffaello-worktrees/STORY-011
git log --oneline -n 10
ls
```

在该 worktree 里跑测试（如果项目里有）：

```bash
cd .raffaello-worktrees/STORY-011
npm test
```


## 4) Finish a run (stop processes and optionally merge)

When you want to stop everything cleanly:

```bash
cd <YOUR_PROJECT_DIR>
./bin/raffaello-finish.sh --project-dir .
```

If you also want to clean comm/worktrees state:

```bash
./bin/raffaello-finish.sh --project-dir . --clean
```

If you want to automatically merge only `passes=true` stories into the current branch (recommended: your main branch (e.g. `main`)):

```bash
./bin/raffaello-finish.sh --project-dir . --clean --merge-pass
```

Dry-run (prints actions without doing destructive steps):

```bash
./bin/raffaello-finish.sh --project-dir . --clean --merge-pass --dry-run
```

## 4) 收尾一轮（停进程 + 可选 merge）

只停干净（不 merge）：

```bash
cd <YOUR_PROJECT_DIR>
./bin/raffaello-finish.sh --project-dir .
```

停干净 + 清理 comm/worktrees：

```bash
./bin/raffaello-finish.sh --project-dir . --clean
```

停干净 + 清理 + 自动把 `passes=true` 的 story 合并回当前分支（推荐在你的主分支（例如 `main`）上执行：

```bash
./bin/raffaello-finish.sh --project-dir . --clean --merge-pass
```

演练模式（只打印要做的事情，不执行破坏性操作）：

```bash
./bin/raffaello-finish.sh --project-dir . --clean --merge-pass --dry-run
```

### raffaello-finish.sh 参数说明

- `--clean`
  - EN: Also clean agent comm directory and git worktrees.
  - CN: 同时清理 `/tmp/raffaello` 和 git worktrees（避免历史残留）。
- `--merge-pass`
  - EN: Merge only stories marked `passes=true` in `prd.json`.
  - CN: 只合并 `prd.json` 里标记为 `passes=true` 的故事分支。
- `--dry-run`
  - EN: Print actions without executing destructive steps.
  - CN: 只演练不执行（更安全）。


## 5) Merge stories manually (optional)

List stories that are marked `passes=true` in `prd.json`:

```bash
cd <YOUR_PROJECT_DIR>
./bin/raffaello-merge.sh --project-dir . list
```

Merge all `passes=true` stories in order:

```bash
./bin/raffaello-merge.sh --project-dir . merge-pass
```

Merge specific stories:

```bash
./bin/raffaello-merge.sh --project-dir . merge STORY-011 STORY-010
```

## 5) 手动/半自动合并（可选）

列出 `passes=true` 的故事：

```bash
cd <YOUR_PROJECT_DIR>
./bin/raffaello-merge.sh --project-dir . list
```

自动合并所有 `passes=true`（按编号顺序）：

```bash
./bin/raffaello-merge.sh --project-dir . merge-pass
```

指定合并：

```bash
./bin/raffaello-merge.sh --project-dir . merge STORY-011 STORY-010
```


## 6) AI-Powered Merge (Recommended for Conflicts)

When you have multiple story branches with conflicts, use AI merge mode:

```bash
cd <YOUR_PROJECT_DIR>
./merge-stories.sh --ai
```

This will:
1. Find all `story-*` branches
2. Attempt to merge each branch into master/main
3. When conflicts occur, analyze severity (LOW/MEDIUM/HIGH)
4. Use Claude Code to intelligently resolve conflicts
5. Automatically commit successful merges
6. Delete merged branches

**Example output**:
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
[MERGE] Claude Code finished processing
[MERGE] All conflicts resolved by Claude Code
[master f13b144] Merge story-STORY-007 into master

[MERGE] === Merge Summary ===
[MERGE] Successfully merged: 3
[MERGE] All branches merged successfully!
```

## 6) AI 智能合并（推荐用于解决冲突）

当多个 story 分支有冲突时，使用 AI 合并模式：

```bash
cd <YOUR_PROJECT_DIR>
./merge-stories.sh --ai
```

它会：
1. 找到所有 `story-*` 分支
2. 尝试将每个分支合并到 master/main
3. 遇到冲突时，分析严重程度（LOW/MEDIUM/HIGH）
4. 使用 Claude Code 智能解决冲突
5. 自动提交成功的合并
6. 删除已合并的分支

**输出示例**：
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
[MERGE] Claude Code finished processing
[MERGE] All conflicts resolved by Claude Code
[master f13b144] Merge story-STORY-007 into master

[MERGE] === Merge Summary ===
[MERGE] Successfully merged: 3
[MERGE] All branches merged successfully!
```

### Tips for AI Merge / AI 合并技巧

- **Timeout**: Default is 600 seconds (10 minutes) per merge. Complex merges may need this time.
- **Clean state**: Ensure you're on master/main branch before running
- **Check results**: After merge, run tests to verify: `npm test`
- **Logs**: Check `/tmp/raffaello/merge/` for Claude Code logs

- **超时时间**：默认每次合并 600 秒（10 分钟）。复杂合并可能需要这么长时间。
- **干净状态**：运行前确保在 master/main 分支
- **检查结果**：合并后运行测试验证：`npm test`
- **日志**：查看 `/tmp/raffaello/merge/` 获取 Claude Code 日志


## Notes / Expectations

- If your project directory still looks "empty" after a run, that is expected until you merge story branches.
- If you see a story with `passes=false`, check its story log and `/tmp/raffaello/STORY-XXX/*-output.txt`.
- Repo hygiene:
  - `.gitignore` excludes `.raffaello-logs/`, `.raffaello-worktrees/`, `node_modules/`, `dist/`, `coverage/`, and Playwright outputs.
  - The orchestrator also filters these paths out before committing story work.

## 说明 / 注意事项

- 如果 run 结束后你在项目目录看不到代码，这是正常的：代码在 `.raffaello-worktrees/STORY-XXX`，需要合并分支后才会回到主目录。
- 如果某个故事 `passes=false`：优先看 `.raffaello-logs/STORY-XXX.log`，再看 `/tmp/raffaello/STORY-XXX/*-output.txt` 的最后输出。
- 仓库洁净策略：
  - `.gitignore` 会把 `.raffaello-logs/`、`.raffaello-worktrees/`、`node_modules/`、`dist/`、`coverage/`、Playwright 产物排除掉。
  - orchestrator 在提交前也会强制把这些目录从暂存区/工作区移除，避免出现"分支里塞满 node_modules/coverage"的灾难提交。


## Troubleshooting / 常见问题排查

### 1) Monitor looks noisy (old stories, inactive_for=xxx)

- EN: Usually historical residue under `/tmp/raffaello`. Hide stale/inactive output.
- CN: 一般是 `/tmp/raffaello` 的历史残留导致。可以隐藏 stale/inactive：

```bash
SHOW_STALE_STORIES=false SHOW_INACTIVE=false \
  ./raffaello/monitor.sh . --stdout
```

### 2) Worktree conflicts (branch already used by worktree)

- EN: Stale git worktree bookkeeping can cause this.
- CN: git worktree 记录残留会导致这个错误。

Fix:

```bash
cd <YOUR_PROJECT_DIR>
./bin/raffaello-finish.sh --project-dir . --clean
```

### 3) "success=yes" but pid still alive

- EN: Claude CLI can hang after success (pre-flight, etc.). Orchestrator force-kills lingering pids after completion.
- CN: Claude CLI 可能在成功后卡住（pre-flight 等）。现在 orchestrator 会在 story 完成后强制清理残留 pid。


## Advanced / 高级参数（raffaello.sh / monitor / 仓库机制）

## Recommended Defaults / 推荐默认值（以及什么时候调整）

### Suggested starting point / 建议起步配置

- EN: If you frequently hit false-positive stalls during installs/tests, start with a larger stall threshold.
- CN: 如果你经常遇到“其实在跑，只是长时间没输出”的误杀，建议把 stall 阈值调大。

Recommended:

```bash
# Recommended default
./bin/raffaello-start.sh --project-dir . --profile safe

# Fast feedback (may kill long silent steps)
./bin/raffaello-start.sh --project-dir . --profile fast

# Very safe (less likely to kill; slower to recover from real hangs)
./bin/raffaello-start.sh --project-dir . --profile very-safe

# You can still override numbers explicitly
./bin/raffaello-start.sh --project-dir . --iters 30 --stall-secs 600 --interval-secs 10
```

### How to choose `stall-secs` / 如何选择 stall 阈值

- EN: Increase `stall-secs` when:
  - installs/tests/builds can be silent for minutes
  - network is slow or package manager is chatty only at start/end
- CN: 这些情况建议调大 `stall-secs`：
  - `npm install`/`pnpm install`、E2E、coverage 等阶段可能几分钟不输出
  - 网络慢、镜像慢导致长耗时

- EN: Decrease `stall-secs` when:
  - you want faster recovery from hangs
  - the repo is small and phases should always produce output
- CN: 这些情况可以调小 `stall-secs`：
  - 你更希望“挂了就快点重试/重启”
  - 仓库很小、每个 phase 正常都应该持续输出

### How to choose `interval-secs` / 如何选择 interval

- EN: Keep `interval-secs=10` unless you have many stories and want less monitor noise.
- CN: 一般保持 `interval-secs=10` 就行；如果 story 很多想减少 monitor 频率，可以调到 20/30。

### raffaello.sh core environment variables / raffaello.sh 核心环境变量

- `GLOBAL_MAX_ITERATIONS`
  - EN: Max global iterations to attempt.
  - CN: 全局最多迭代次数。
- `RAFFAELLO_ASSUME_YES`
  - EN: Skip interactive prompts.
  - CN: 跳过交互确认。
- `AUTO_MONITOR_KILL`
  - EN: Starts the kill-capable monitor (watchdog) automatically.
  - CN: 自动启动“可杀进程”的 watchdog monitor。
- `MONITOR_STALL_SECS`
  - EN: Stall threshold (no output) in seconds.
  - CN: 无输出算卡死的阈值（秒）。
- `MONITOR_INTERVAL_SECS`
  - EN: Monitor polling interval in seconds.
  - CN: monitor 检查间隔（秒）。

### Locking / 锁机制

- EN: Raffaello uses a pidfile lock to prevent running multiple top-level instances in the same project.
- CN: Raffaello 会在项目内写 pidfile 锁，防止同一项目重复启动多个顶层 raffaello。

Where to look:

- Lock file: `.raffaello-logs/raffaello.pid`

### Communication directory / 通信目录

- EN: By default agents communicate via `/tmp/raffaello/<STORY-ID>/`.
- CN: agent 默认通过 `/tmp/raffaello/<STORY-ID>/` 目录通信。

Common files:

- `<phase>.pid`: last spawned pid for that phase
- `<phase>-output.txt`: captured stdout/stderr for that phase
- `.<phase>-success`: success marker file
- `.<phase>-abort`: abort marker file (written by monitor-kill when terminating stalled agents)

### Worktrees / 分支与 worktree 机制

- EN: Each story runs on branch `story-<STORY-ID>` in worktree `.raffaello-worktrees/<STORY-ID>`.
- CN: 每个 story 在分支 `story-<STORY-ID>` 上运行，worktree 在 `.raffaello-worktrees/<STORY-ID>`。

Implication:

- EN: Your project directory stays on your main branch (e.g. `main`) and will look "empty" until you merge story branches.
- CN: 项目目录默认停留在你的主分支（例如 `main`），所以在 merge 之前看起来像"没代码"。

### Orchestrator cleanup after completion / 完成后清理残留进程

- `FORCE_KILL_DONE_PIDS_SECS`
  - EN: Seconds to wait after story completion before force-killing lingering phase pids.
  - CN: story 完成后等待多少秒再强制清理残留 phase pid。
