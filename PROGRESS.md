# Ralph Parallel - Development Progress

## Phase 1: Project Skeleton and CLI Adaptation ✅

**Date**: 2026-01-25
**Status**: Complete

### What Was Implemented

1. **Project Structure**
   - Created `/Users/chilikevin/aml/ralph-parallel/` with organized directories
   - `lib/` - Core library functions
   - `agents/` - Agent instruction files
   - `workflows/`, `docs/` - Prepared for future phases

2. **CLI Detection Layer** (`lib/detect-cli.sh`)
   - Auto-detects Claude Code or Codex CLI
   - Validates multi-agent support configuration
   - Returns CLI-specific agent directories
   - **Tested**: ✅ Successfully detects Claude Code

3. **Unified Agent API** (`lib/agent-api.sh`)
   - `spawn_agent()` - Consistent interface for both CLIs
   - `wait_for_agents()` - Wait for completion
   - `close_agent()` - Cleanup resources
   - File-based communication in `/tmp/ralph-parallel/`
   - Success marker system (`.{agent}-success` files)

4. **Dynamic Agent Loading** (`lib/load-agents.sh`)
   - Core agents: planner, coder, reviewer, tester
   - Optional agent discovery from `~/.claude/agents/` or `~/.codex/agents/`
   - Workflow validation against available agents
   - **Tested**: ✅ Discovered 12 total agents (4 core + 8 optional)

5. **Core Agent Instructions**
   - `agents/planner.md` - Planning specialist (creates plan.md)
   - `agents/coder.md` - TDD implementation specialist (80% coverage requirement)
   - `agents/reviewer.md` - Code review with severity levels (CRITICAL/HIGH/MEDIUM/LOW)
   - `agents/tester.md` - E2E testing with comprehensive report format

### Files Created

```
ralph-parallel/
├── README.md                    # Bilingual project documentation
├── PROGRESS.md                  # This file
├── lib/
│   ├── detect-cli.sh           # 1962 bytes, executable
│   ├── agent-api.sh            # 4090 bytes, executable
│   └── load-agents.sh          # 3713 bytes, executable
└── agents/
    ├── planner.md              # 1891 bytes
    ├── coder.md                # 2423 bytes
    ├── reviewer.md             # 3811 bytes
    └── tester.md               # 4099 bytes
```

### Testing Results

**CLI Detection**:
```
Detected CLI: claude-code
Multi-agents support: ✓ Enabled
Agent directory: /Users/chilikevin/.claude/agents
```

**Agent Discovery**:
```
Core Agents: 4 (planner, coder, reviewer, tester)
Optional Agents: 8 (code-reviewer, security-reviewer, architect, etc.)
Total Available: 12
```

### Design Patterns Established

1. **Bash Library Pattern**: All shared functions in `lib/`, sourced by other scripts
2. **CLI Abstraction**: Single API works with multiple CLI implementations
3. **File-Based IPC**: Agents communicate via files in `$AGENT_COMM_DIR`
4. **Success Markers**: `.{agent}-success` files signal completion
5. **Bilingual Docs**: All user-facing documentation in English + Chinese

### Learnings for Future Phases

1. **Agent Communication Directory**: Using `/tmp/ralph-parallel/{story_id}/` keeps story-specific data isolated
2. **PID as Agent ID**: For Claude Code, we use process PID as agent identifier
3. **Optional Agent Discovery**: `find` with `-maxdepth 1` ensures we don't recurse into subdirectories
4. **Workflow Validation**: Must check agent existence before starting orchestration
5. **Error Handling**: All scripts use `set -euo pipefail` for safety

### Next Phase Requirements

Phase 2 will need:
1. **ralph.sh** - Main parallel loop
   - Read prd.json
   - Analyze dependencies
   - Spawn orchestrators for each story (max 3 concurrent)
   - Wait for completion
   - Call merge-stories.sh

2. **orchestrator.sh** - Per-story manager
   - Load workflow configuration
   - Execute phases sequentially
   - Handle retry logic
   - Update prd.json on success

3. **dependency-analyzer.sh** - DAG builder
   - Parse story dependencies from prd.json
   - Identify parallelizable stories
   - Return execution order

### Time Spent

Estimated: 1.5 hours (within 1-2 hour estimate for Phase 1)

---

## Phase 2: Core Parallel Engine ✅

**Date**: 2026-01-25
**Status**: Complete

### What Was Implemented

1. **Main Parallel Loop** (`ralph.sh`)
   - Reads PRD and identifies incomplete stories
   - Calls dependency analyzer to create execution plan
   - Executes stories in batches (max 3 concurrent per batch)
   - Tracks background processes for each story
   - Calls merge-stories.sh after all stories complete
   - Colorized logging for better UX
   - **Prerequisites**: Checks for jq, yq, and CLI availability

2. **Story Orchestrator** (`orchestrator.sh`)
   - Manages execution phases for a single story
   - Loads workflow configuration from YAML files
   - Executes each phase sequentially with retry logic
   - Spawns agents for each phase using unified API
   - Updates PRD with story status (passes: true/false)
   - Creates git commits for completed stories
   - **Phase validation**: Checks agent existence before execution

3. **Dependency Analyzer** (`lib/dependency-analyzer.sh`)
   - Builds DAG from story dependencies in prd.json
   - Identifies parallelizable stories (independent batches)
   - Returns execution plan as JSON: `{batches:[[...],[...]], unassigned:[]}`
   - Detects circular dependencies
   - **Bash 3.2 compatible**: Uses temp files instead of associative arrays
   - **Tested**: ✅ Correctly analyzes test PRD with 3 stories

4. **Branch Merge Manager** (`merge-stories.sh`)
   - Merges all story-* branches back to main
   - Attempts fast-forward merge first (cleanest)
   - Falls back to regular merge if fast-forward fails
   - Detects merge conflicts and reports them
   - Deletes successfully merged branches
   - **Phase 2 limitation**: Manual conflict resolution (Phase 4 will add AI resolver)

5. **Workflow Configurations** (3 YAML files)
   - `workflows/simple.yaml` - Coder + Tester only (2 phases)
   - `workflows/standard.yaml` - All 4 core agents (4 phases)
   - `workflows/full-stack.yaml` - Core + 4 optional agents (8 phases)
   - Each includes retry_policy with max_attempts per phase

### Files Created

```
ralph-parallel/
├── ralph.sh                         # Main parallel loop (180 lines)
├── orchestrator.sh                  # Story phase manager (210 lines)
├── merge-stories.sh                 # Branch merge manager (150 lines)
├── prd.json                         # Test PRD with 3 stories
├── lib/
│   └── dependency-analyzer.sh       # DAG builder (182 lines, bash 3.2 compatible)
└── workflows/
    ├── simple.yaml                  # 2-phase workflow
    ├── standard.yaml                # 4-phase workflow
    └── full-stack.yaml              # 8-phase workflow
```

### Testing Results

**Dependency Analyzer** (with test PRD):
```json
{
  "batches": [
    ["US001", "US002"],  // Batch 1: Can run in parallel
    ["US003"]            // Batch 2: Depends on US001 and US002
  ],
  "unassigned": []
}
```

**Workflow Validation**:
- ✅ simple.yaml - 2 phases (coder, tester)
- ✅ standard.yaml - 4 phases (planner, coder, reviewer, tester)
- ✅ full-stack.yaml - 8 phases (includes optional agents)

### Design Patterns Established

1. **Batch Execution**: Stories grouped by dependency levels, executed in waves
2. **Background Process Tracking**: Uses bash job control (`&`, `wait -n`, PID arrays)
3. **Colorized Logging**: BLUE (info), GREEN (success), YELLOW (warn), RED (error)
4. **Git Branch Isolation**: Each story gets `story-{ID}` branch
5. **YAML-Driven Workflows**: Phase order and retry policies in configuration files
6. **Temp File State Management**: Bash 3.2 compatibility using temp files instead of associative arrays

### Learnings for Future Phases

1. **Bash 3.2 Limitations**: macOS ships with bash 3.2, avoid associative arrays (`declare -A`)
2. **Process Substitution**: Use `< <(command)` for reading command output line-by-line
3. **Concurrent Limits**: MAX_PARALLEL_STORIES=3 to avoid API rate limits
4. **Merge Conflicts**: Phase 2 detects but doesn't resolve - Phase 4 will add AI resolver
5. **Story Branch Naming**: `story-{ID}` convention makes them easy to identify and filter
6. **PRD Updates**: `jq` can modify JSON in-place (create temp file, then `mv`)

### Known Limitations (To Address in Future Phases)

1. **No Conflict Resolution**: merge-stories.sh aborts on conflicts (Phase 4 will add AI resolver)
2. **No Workflow Parser**: orchestrator.sh uses yq directly (Phase 3 will add dedicated parser)
3. **Limited Error Recovery**: Failed stories don't automatically retry at orchestrator level
4. **No Progress Persistence**: If ralph.sh crashes, must restart from beginning

### Time Spent

Estimated: 2.5 hours (within 2-3 hour estimate for Phase 2)

---

*Next: Phase 3 - Workflow System (add workflow-parser.sh)*
