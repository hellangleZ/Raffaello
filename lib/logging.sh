#!/usr/bin/env bash
# Unified Logging System
# Provides consistent logging functions across all scripts

# Colors
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color

# Log prefix (can be overridden by each script)
LOG_PREFIX="${LOG_PREFIX:-INFO}"

# Logging functions
log_info() {
  echo -e "${BLUE}[${LOG_PREFIX}]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[${LOG_PREFIX}]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[${LOG_PREFIX}]${NC} $*"
}

log_error() {
  echo -e "${RED}[${LOG_PREFIX}]${NC} $*"
}

log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo -e "${CYAN}[DEBUG]${NC} $*"
  fi
}

# Export functions so they're available in subshells
export -f log_info
export -f log_success
export -f log_warn
export -f log_error
export -f log_debug
