#!/usr/bin/env bash
# CLI Detection and Validation
# Validates that Claude Code CLI is available

set -euo pipefail

# Detect if Claude Code CLI is available
detect_cli() {
  if command -v claude &> /dev/null; then
    echo "claude-code"
  else
    echo "ERROR: Claude Code CLI not found" >&2
    echo "Please install Claude Code: https://claude.com/claude-code" >&2
    exit 1
  fi
}

# Check if multi-agents support is enabled
# Claude Code always supports Task tool for background execution
check_multiagents_support() {
  # Claude Code has built-in Task tool support
  return 0
}

# Get agent directory for Claude Code
get_agent_dir() {
  echo "$HOME/.claude/agents"
}

# Main execution if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  CLI=$(detect_cli)
  echo "Detected CLI: $CLI"

  if check_multiagents_support; then
    echo "Multi-agents support: ✓ Enabled (Task tool)"
    echo "Agent directory: $(get_agent_dir)"
  else
    echo "Multi-agents support: ✗ Disabled"
    exit 1
  fi
fi
