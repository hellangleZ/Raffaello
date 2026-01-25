#!/usr/bin/env bash
# CLI Detection and Validation
# Detects whether Claude Code or Codex is available and validates multi-agent support

set -euo pipefail

# Detect which CLI is available
detect_cli() {
  if command -v claude &> /dev/null; then
    echo "claude-code"
  elif command -v codex &> /dev/null; then
    echo "codex"
  else
    echo "ERROR: Neither Claude Code nor Codex CLI found" >&2
    echo "Please install one of:" >&2
    echo "  - Claude Code: https://claude.com/claude-code" >&2
    echo "  - Codex: https://github.com/anthropics/codex" >&2
    exit 1
  fi
}

# Check if multi-agents support is enabled
check_multiagents_support() {
  local cli=$1

  if [[ "$cli" == "claude-code" ]]; then
    # Claude Code always supports Task tool (multi-agents)
    return 0
  elif [[ "$cli" == "codex" ]]; then
    # Check Codex config.toml for multi-agents feature
    local config_file="$HOME/.codex/config.toml"

    if [[ ! -f "$config_file" ]]; then
      echo "ERROR: Codex config not found at $config_file" >&2
      echo "Please run 'codex init' first" >&2
      exit 1
    fi

    if grep -q "multi-agents = true" "$config_file" 2>/dev/null; then
      return 0
    else
      echo "ERROR: Codex multi-agents not enabled" >&2
      echo "" >&2
      echo "Add to $config_file:" >&2
      echo "[features]" >&2
      echo "multi-agents = true" >&2
      exit 1
    fi
  fi

  return 1
}

# Get CLI-specific agent directory
get_agent_dir() {
  local cli=$1

  if [[ "$cli" == "claude-code" ]]; then
    echo "$HOME/.claude/agents"
  elif [[ "$cli" == "codex" ]]; then
    echo "$HOME/.codex/agents"
  fi
}

# Main execution if run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  CLI=$(detect_cli)
  echo "Detected CLI: $CLI"

  if check_multiagents_support "$CLI"; then
    echo "Multi-agents support: ✓ Enabled"
    echo "Agent directory: $(get_agent_dir "$CLI")"
  else
    echo "Multi-agents support: ✗ Disabled"
    exit 1
  fi
fi
