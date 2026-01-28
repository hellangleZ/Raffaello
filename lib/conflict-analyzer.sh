#!/usr/bin/env bash
# Conflict Analyzer - Analyze merge conflict severity and recommend resolution strategy
# Part of the smart merge system

set -euo pipefail

# Severity thresholds (configurable)
CONFLICT_RATIO_HIGH_THRESHOLD=${CONFLICT_RATIO_HIGH_THRESHOLD:-20}    # >20% of file = HIGH
CONFLICT_RATIO_MEDIUM_THRESHOLD=${CONFLICT_RATIO_MEDIUM_THRESHOLD:-5} # >5% of file = MEDIUM
AVG_CONFLICT_SIZE_HIGH_THRESHOLD=${AVG_CONFLICT_SIZE_HIGH_THRESHOLD:-50} # >50 lines per conflict = HIGH
MULTIPLE_CONFLICTS_THRESHOLD=${MULTIPLE_CONFLICTS_THRESHOLD:-3}       # >3 conflicts = MEDIUM

# Severity levels
SEVERITY_LOW="LOW"
SEVERITY_MEDIUM="MEDIUM"
SEVERITY_HIGH="HIGH"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Analyze a single conflicted file
analyze_conflict_severity() {
  local file=$1

  if [[ ! -f "$file" ]]; then
    echo "ERROR: File not found: $file" >&2
    return 1
  fi

  # Count conflict markers
  local conflict_sections=$(grep -c "^<<<<<<< " "$file" 2>/dev/null || echo 0)

  if [[ $conflict_sections -eq 0 ]]; then
    echo "NONE"
    return 0
  fi

  # Get file size (lines)
  local file_size=$(wc -l < "$file" | tr -d ' ')

  # Avoid division by zero
  if [[ $file_size -eq 0 ]]; then
    echo "$SEVERITY_HIGH"
    return 0
  fi

  # Calculate conflict ratio (percentage)
  local conflict_ratio=$((conflict_sections * 100 / file_size))

  # Check for logic conflicts (function/class definitions in conflict sections)
  local has_logic_conflict=$(grep -B2 "^<<<<<<< " "$file" | grep -c -E "(function|class|def |const |let |var |interface|type |struct |impl )" 2>/dev/null || echo 0)

  # Check conflict content complexity
  local conflict_lines=$(awk '/^<<<<<<< /,/^>>>>>>> /' "$file" | wc -l | tr -d ' ')

  # Severity determination logic

  # HIGH: Logic conflicts (function/class definitions)
  if [[ $has_logic_conflict -gt 0 ]]; then
    echo "$SEVERITY_HIGH"
    return 0
  fi

  # HIGH: Too many conflicts (>threshold% of file)
  if [[ $conflict_ratio -gt $CONFLICT_RATIO_HIGH_THRESHOLD ]]; then
    echo "$SEVERITY_HIGH"
    return 0
  fi

  # HIGH: Large conflict sections (>threshold lines per conflict)
  local avg_conflict_size=$((conflict_lines / conflict_sections))
  if [[ $avg_conflict_size -gt $AVG_CONFLICT_SIZE_HIGH_THRESHOLD ]]; then
    echo "$SEVERITY_HIGH"
    return 0
  fi

  # MEDIUM: Moderate conflicts (threshold-20% of file)
  if [[ $conflict_ratio -gt $CONFLICT_RATIO_MEDIUM_THRESHOLD ]]; then
    echo "$SEVERITY_MEDIUM"
    return 0
  fi

  # MEDIUM: Multiple small conflicts
  if [[ $conflict_sections -gt $MULTIPLE_CONFLICTS_THRESHOLD ]]; then
    echo "$SEVERITY_MEDIUM"
    return 0
  fi

  # LOW: Simple conflicts
  echo "$SEVERITY_LOW"
}

# Get conflict details for a file
get_conflict_details() {
  local file=$1
  local severity=$2

  local conflict_count=$(grep -c "^<<<<<<< " "$file" 2>/dev/null || echo 0)
  local file_size=$(wc -l < "$file" | tr -d ' ')
  local conflict_ratio=$((conflict_count * 100 / (file_size + 1)))

  cat <<EOF
File: $file
Severity: $severity
Conflicts: $conflict_count
File size: $file_size lines
Conflict ratio: ${conflict_ratio}%
EOF
}

# Recommend resolution strategy
recommend_strategy() {
  local severity=$1

  case "$severity" in
    "$SEVERITY_LOW")
      echo "auto-merge"
      ;;
    "$SEVERITY_MEDIUM")
      echo "ai-resolver"
      ;;
    "$SEVERITY_HIGH")
      echo "manual-review"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

# Analyze all conflicted files in current git state
analyze_all_conflicts() {
  # Check if we're in a merge state
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: Not in a git repository" >&2
    return 1
  fi

  if [[ ! -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]]; then
    echo "No merge in progress"
    return 0
  fi

  # Get all conflicted files
  local conflicted_files
  conflicted_files=$(git diff --name-only --diff-filter=U 2>/dev/null)

  if [[ -z "$conflicted_files" ]]; then
    echo "No conflicted files"
    return 0
  fi

  # Analyze each file
  local total=0
  local low=0
  local medium=0
  local high=0

  echo "Conflict Analysis:"
  echo ""

  while IFS= read -r file; do
    if [[ -z "$file" ]]; then
      continue
    fi

    ((total++))
    local severity=$(analyze_conflict_severity "$file")
    local strategy=$(recommend_strategy "$severity")

    # Color code by severity
    local color=$GREEN
    case "$severity" in
      "$SEVERITY_MEDIUM") color=$YELLOW; ((medium++)) ;;
      "$SEVERITY_HIGH") color=$RED; ((high++)) ;;
      "$SEVERITY_LOW") ((low++)) ;;
    esac

    echo -e "${color}[$severity]${NC} $file → $strategy"
  done <<< "$conflicted_files"

  echo ""
  echo "Summary:"
  echo "  Total: $total"
  echo -e "  ${GREEN}Low:${NC} $low (auto-merge)"
  echo -e "  ${YELLOW}Medium:${NC} $medium (AI resolver)"
  echo -e "  ${RED}High:${NC} $high (manual review)"

  # Return overall recommendation
  if [[ $high -gt 0 ]]; then
    return 2  # Manual review needed
  elif [[ $medium -gt 0 ]]; then
    return 1  # AI resolver recommended
  else
    return 0  # Can auto-merge
  fi
}

# Extract conflict section for AI analysis
extract_conflict_section() {
  local file=$1
  local conflict_num=${2:-1}

  # Extract the Nth conflict section
  awk -v n="$conflict_num" '
    /^<<<<<<< / { in_conflict=1; count++; if (count==n) print }
    in_conflict && count==n { print }
    /^>>>>>>> / { if (count==n) { print; exit } in_conflict=0 }
  ' "$file"
}

# Main CLI
main() {
  local command=${1:-analyze}
  shift || true

  case "$command" in
    analyze)
      if [[ $# -eq 0 ]]; then
        # Analyze all conflicts
        analyze_all_conflicts
      else
        # Analyze specific file
        local file=$1
        local severity=$(analyze_conflict_severity "$file")
        get_conflict_details "$file" "$severity"
        echo "Recommended: $(recommend_strategy "$severity")"
      fi
      ;;
    severity)
      if [[ $# -eq 0 ]]; then
        echo "Usage: $0 severity <file>"
        exit 1
      fi
      analyze_conflict_severity "$1"
      ;;
    extract)
      if [[ $# -eq 0 ]]; then
        echo "Usage: $0 extract <file> [conflict_num]"
        exit 1
      fi
      extract_conflict_section "$@"
      ;;
    *)
      echo "Usage: $0 <command> [args]"
      echo ""
      echo "Commands:"
      echo "  analyze [file]       Analyze conflict severity (all files or specific)"
      echo "  severity <file>      Get severity level for a file"
      echo "  extract <file> [n]   Extract conflict section from file"
      exit 1
      ;;
  esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
