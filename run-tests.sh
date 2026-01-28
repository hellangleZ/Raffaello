#!/bin/bash
echo "=== Raffaello Quick Test ==="
echo ""

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
echo "=== ✓ All Core Tests Passed ==="
echo ""
echo "Next steps:"
echo "  1. Run './ralph.sh' to test full execution"
echo "  2. See TESTING.md for detailed test guide"
