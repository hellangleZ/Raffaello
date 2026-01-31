# Baseline Contract

## Rules for Non-Baseline Stories

STORY-001 (or the first story with priority=1) is the baseline story responsible for setting up the project environment.
All other stories MUST follow these rules:

### Dependency Management Rules
1. **PREFER using existing dependencies** from the baseline
2. **IF you must add new dependencies**:
   - Document the reason in your `implementation-summary.md`
   - Explain why existing dependencies cannot fulfill the need
   - Ensure compatibility with existing toolchain

### High-Conflict Files (Modify with Caution)
These files are managed by the baseline story. Avoid modifying unless absolutely necessary:
- workflows/**
- prd.json
- package.json, package-lock.json, pnpm-lock.yaml, yarn.lock
- requirements.txt, pyproject.toml, poetry.lock
- go.mod, go.sum
- Cargo.toml, Cargo.lock
- Gemfile, Gemfile.lock
- composer.json, composer.lock
