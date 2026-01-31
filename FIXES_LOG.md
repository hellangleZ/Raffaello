# Fixes Log

- 2026-01-30: Baseline scheduling now produces >1 batch
  - Symptom: runner executed only `STORY-001` then exited even when other stories were incomplete.
  - Root cause: baseline-first gating was implemented inside `lib/dependency-analyzer.sh`, overwriting the computed DAG batches to `[[STORY-001]]` when baseline was incomplete.
  - Fix: remove baseline gating from `lib/dependency-analyzer.sh`; keep gating decisions in the runner (`ralph.sh`) after computing the real execution plan.

- 2026-01-30: Orchestrator phase success is artifact-based (reduces marker brittleness)
  - Added phase artifact checks in `orchestrator.sh` so phases can be marked successful when expected artifacts exist:
    - planner: `plan.md`
    - coder: `implementation-summary.md`
    - reviewer: `review-changes.md` or `review-approved.md`
    - tester: `e2e-report.md` or `test-results.json`
  - Updated `agents/coder.md` to require writing `implementation-summary.md` instead of a hidden `.coder-success` marker.

- 2026-01-30: Claude-only runner (no Codex)
  - Removed Codex references and Codex-specific execution paths.

- 2026-01-30: Remaining blocker (not solved yet)
  - Claude Code `--print` can hang with 0 bytes output when stdin contains large Markdown prompts (especially prompts with many list items).
  - This currently prevents even the planner phase from producing output in `/aml/test2`.
  - Next intended fix: replace the agent prompt templates with a minimal, non-Markdown, tool-instruction format (or drive Claude via `--input-format=stream-json` with tool wiring), so CLI reliably exits and writes artifacts.
