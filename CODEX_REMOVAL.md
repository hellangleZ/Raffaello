# Codex Support Removal

## Summary

Removed all Codex-related code and documentation from Ralph Parallel.

**Reason**: Current Codex CLI does not support multi-agents feature, making the Codex integration untestable and potentially misleading.

## Files Modified

### Code Files
1. **lib/detect-cli.sh** - Removed Codex detection, now only supports Claude Code
2. **lib/agent-api.sh** - Removed Codex spawn_agent/wait/close APIs
3. **lib/load-agents.sh** - Removed Codex agent directory logic

### Documentation Files
1. **README.md** - Removed Codex references
2. **QUICKSTART.md** - Removed Codex setup instructions
3. **docs/ARCHITECTURE.md** - Removed Codex API documentation
4. **docs/WORKFLOWS.md** - Removed Codex examples
5. **docs/DESIGN.md** - Removed Codex design considerations
6. **TESTING_RESULTS.md** - Updated to reflect Claude Code-only testing
7. **NEXT_STEPS.md** - Removed Codex option
8. **PROGRESS.md** - Updated to reflect single-CLI support

## What's Left

Ralph Parallel now exclusively supports **Claude Code CLI** with:
- Task-based agent execution
- Automatic background task management
- Agent success marker detection
- Communication via `/tmp/ralph-parallel/`

## Migration Path

If Codex adds multi-agent support in the future, the architecture is still compatible:
1. Re-add Codex detection in `lib/detect-cli.sh`
2. Re-add Codex API calls in `lib/agent-api.sh`
3. Test with Codex's `spawn_agent` API

The core multi-agent architecture remains CLI-agnostic.
