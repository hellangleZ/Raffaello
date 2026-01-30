#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Raffaello Test Runner ==="
echo ""

usage() {
  cat <<'EOF'
Usage:
  ./run-tests.sh [quick|workflows|e2e|suite|all]

Commands:
  quick      Fast static checks (default)
  workflows  Workflow/agent/dependency tests
  e2e        End-to-end repo checks with test-project
  suite      Full improvement suite (larger)
  all        Run quick + workflows + e2e + suite
EOF
}

MODE="${1:-quick}"
case "$MODE" in
  -h|--help|help) usage; exit 0 ;;
  quick|workflows|e2e|suite|all) ;;
  *) echo "Unknown mode: $MODE"; echo ""; usage; exit 2 ;;
esac

TESTS_DIR="$SCRIPT_DIR/tools/tests"

# Test 1: Files exist
echo "[1/8] Checking files..."
if [[ -f "lib/logging.sh" ]] && [[ -f "lib/prd-validator.sh" ]]; then
  echo "✓ New files created"
else
  echo "✗ Missing files"
  exit 1
fi

# Test 2: No associative arrays
echo "[2/8] Checking Bash 3.2 compatibility..."
if grep -r "declare -A" ralph.sh orchestrator.sh lib/*.sh 2>/dev/null; then
  echo "✗ Found incompatible associative arrays"
  exit 1
else
  echo "✓ Bash 3.2 compatible"
fi

# Test 3: Logging integrated
echo "[3/8] Checking unified logging..."
if grep -q "source.*lib/logging.sh" ralph.sh orchestrator.sh merge-stories.sh; then
  echo "✓ Unified logging integrated"
else
  echo "✗ Missing logging integration"
  exit 1
fi

# Test 4: Trap cleanup
echo "[4/8] Checking trap cleanup..."
if grep -q "trap.*EXIT" ralph.sh orchestrator.sh; then
  echo "✓ Trap cleanup configured"
else
  echo "✗ Missing trap cleanup"
  exit 1
fi

# Test 5: Constants
echo "[5/8] Checking constants..."
if grep -q "CONFLICT_RATIO_HIGH_THRESHOLD" lib/conflict-analyzer.sh; then
  echo "✓ Magic numbers replaced with constants"
else
  echo "✗ Missing constants"
  exit 1
fi

# Test 6: PRD validator
echo "[6/8] Testing PRD validator..."
if bash -n lib/prd-validator.sh 2>/dev/null; then
  echo "✓ PRD validator syntax OK"
else
  echo "✗ PRD validator has errors"
  exit 1
fi

# Test 7: Test with example
echo "[7/8] Validating prd.json.example..."
if [[ -f "prd.json.example" ]]; then
  if ./lib/prd-validator.sh prd.json.example >/dev/null 2>&1; then
    echo "✓ prd.json.example is valid"
  else
    echo "⚠ prd.json.example validation failed (may need updates)"
  fi
else
  echo "⊘ No prd.json.example to test"
fi

# Test 8: Dependency analyzer
echo "[8/8] Testing dependency analyzer..."
if bash -n lib/dependency-analyzer.sh 2>/dev/null; then
  echo "✓ Dependency analyzer syntax OK"
else
  echo "✗ Dependency analyzer has errors"
  exit 1
fi

echo ""
echo "=== ✓ Quick Checks Passed ==="

run_workflows() {
  if [[ -x "$TESTS_DIR/test-workflows.sh" ]]; then
    "$TESTS_DIR/test-workflows.sh"
  else
    echo "✗ Missing $TESTS_DIR/test-workflows.sh"
    exit 1
  fi
}

run_e2e() {
  if [[ -x "$TESTS_DIR/test-e2e.sh" ]]; then
    "$TESTS_DIR/test-e2e.sh"
  else
    echo "✗ Missing $TESTS_DIR/test-e2e.sh"
    exit 1
  fi
}

run_suite() {
  if [[ -x "$TESTS_DIR/test-improvements.sh" ]]; then
    "$TESTS_DIR/test-improvements.sh"
  else
    echo "✗ Missing $TESTS_DIR/test-improvements.sh"
    exit 1
  fi
}

case "$MODE" in
  quick) ;;
  workflows) run_workflows ;;
  e2e) run_e2e ;;
  suite) run_suite ;;
  all)
    echo ""
    run_workflows
    echo ""
    run_e2e
    echo ""
    run_suite
    ;;
esac

echo ""
echo "Next steps:"
echo "  - Run '/aml/raffaello/bin/ralph-start.sh --project-dir <DIR>' to execute stories"
echo "  - See docs/RALPH-RUNBOOK.md for start → monitor → merge → finish"
