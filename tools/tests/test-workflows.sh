#!/usr/bin/env bash
# Test workflow system end-to-end

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() {
  echo -e "${GREEN}✓${NC} $1"
}

fail() {
  echo -e "${RED}✗${NC} $1"
  exit 1
}

info() {
  echo -e "${BLUE}→${NC} $1"
}

echo "=== Ralph Parallel - Workflow System Test ==="
echo ""

# Test 1: List workflows
info "Test 1: List workflows"
workflows=$(./lib/workflow-parser.sh list)
if [[ $(echo "$workflows" | wc -l) -ge 2 ]]; then
  pass "Found workflows: $(echo $workflows | tr '\n' ', ')"
else
  fail "Expected at least 2 workflows"
fi
echo ""

# Test 2: Validate workflows
info "Test 2: Validate simple workflow"
if ./lib/workflow-parser.sh validate simple > /dev/null 2>&1; then
  pass "simple workflow is valid"
else
  fail "simple workflow validation failed"
fi

info "Test 3: Validate standard workflow"
if ./lib/workflow-parser.sh validate standard > /dev/null 2>&1; then
  pass "standard workflow is valid"
else
  fail "standard workflow validation failed"
fi
echo ""

# Test 4: Show workflow
info "Test 4: Show workflow details"
output=$(./lib/workflow-parser.sh show simple 2>&1)
if echo "$output" | grep -q "coder"; then
  pass "Workflow show command works"
else
  fail "Workflow show command failed"
fi
echo ""

# Test 5: Parse workflow
info "Test 5: Parse workflow to environment"
output=$(./lib/workflow-parser.sh parse simple 2>&1)
if echo "$output" | grep -q "WORKFLOW_NAME=simple"; then
  pass "Workflow parsing works"
else
  fail "Workflow parsing failed"
fi
echo ""

# Test 6: Dependency analyzer
info "Test 6: Dependency analyzer"
if [[ -f "prd.json" ]]; then
  dep_output=$(./lib/dependency-analyzer.sh prd.json)
  if echo "$dep_output" | jq -e '.batches | length >= 1' > /dev/null 2>&1; then
    batch_count=$(echo "$dep_output" | jq '.batches | length')
    pass "Dependency analyzer created $batch_count batches"
  else
    fail "Dependency analyzer failed"
  fi
else
  info "Skipping dependency test (no prd.json)"
fi
echo ""

# Test 7: CLI detection
info "Test 7: CLI detection"
if ./lib/detect-cli.sh > /dev/null 2>&1; then
  cli=$(./lib/detect-cli.sh 2>&1 | grep "Detected CLI" | awk '{print $3}')
  pass "CLI detected: $cli"
else
  fail "CLI detection failed"
fi
echo ""

# Test 8: Agent loading
info "Test 8: Agent discovery"
agent_output=$(./lib/load-agents.sh 2>&1)
core_count=$(echo "$agent_output" | grep "Core Agents:" -A 5 | grep -c "  -")
optional_count=$(echo "$agent_output" | grep "Optional Agents:" -A 20 | grep -c "  -" || echo 0)
total=$((core_count + optional_count))
if [[ $total -ge 4 ]]; then
  pass "Found $total agents ($core_count core + $optional_count optional)"
else
  fail "Expected at least 4 agents"
fi
echo ""

echo -e "${GREEN}=== All Tests Passed! ===${NC}"
echo ""
echo "Summary:"
echo "  - Workflow system: OK"
echo "  - Dependency analyzer: OK"
echo "  - CLI detection: OK"
echo "  - Agent discovery: OK"
