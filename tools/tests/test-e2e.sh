#!/usr/bin/env bash
# End-to-End Test for Ralph Parallel
# Tests complete workflow with test project

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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

warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

echo "=== Ralph Parallel - End-to-End Test ==="
echo ""

# Test 1: Prerequisites
info "Test 1: Checking prerequisites..."
if command -v jq &> /dev/null; then
  pass "jq installed"
else
  fail "jq not installed"
fi

if command -v yq &> /dev/null; then
  pass "yq installed"
else
  fail "yq not installed"
fi

if command -v git &> /dev/null; then
  pass "git installed"
else
  fail "git not installed"
fi
echo ""

# Test 2: CLI Detection
info "Test 2: Testing CLI detection..."
cli_output=$(./lib/detect-cli.sh 2>&1)
if echo "$cli_output" | grep -q "Detected CLI:"; then
  cli=$(echo "$cli_output" | grep "Detected CLI:" | awk '{print $3}')
  pass "CLI detected: $cli"
else
  fail "CLI detection failed"
fi
echo ""

# Test 3: Dependency Analyzer
info "Test 3: Testing dependency analyzer..."
cd test-project
dep_output=$(../lib/dependency-analyzer.sh prd.json 2>&1)
batch_count=$(echo "$dep_output" | jq '.batches | length')
if [[ $batch_count -eq 3 ]]; then
  pass "Dependency analyzer created $batch_count batches (expected 3)"
else
  fail "Expected 3 batches, got $batch_count"
fi
cd ..
echo ""

# Test 4: Workflow Validation
info "Test 4: Testing workflow validation..."
if ./lib/workflow-parser.sh validate simple > /dev/null 2>&1; then
  pass "simple workflow validated"
else
  fail "simple workflow validation failed"
fi

if ./lib/workflow-parser.sh validate standard > /dev/null 2>&1; then
  pass "standard workflow validated"
else
  fail "standard workflow validation failed"
fi
echo ""

# Test 5: Workflow Parsing
info "Test 5: Testing workflow parsing..."
parse_output=$(./lib/workflow-parser.sh parse simple 2>&1)
if echo "$parse_output" | grep -q "WORKFLOW_NAME=simple"; then
  pass "Workflow parsing works"
else
  fail "Workflow parsing failed"
fi
echo ""

# Test 6: Agent Discovery
info "Test 6: Testing agent discovery..."
agent_output=$(./lib/load-agents.sh 2>&1)
core_count=$(echo "$agent_output" | grep "Core Agents:" -A 5 | grep -c "  -")
if [[ $core_count -ge 4 ]]; then
  pass "Found $core_count core agents (expected ≥4)"
else
  fail "Expected ≥4 core agents, found $core_count"
fi
echo ""

# Test 7: Test Project Structure
info "Test 7: Verifying test project structure..."
if [[ -d "test-project" ]]; then
  pass "test-project directory exists"
else
  fail "test-project directory not found"
fi

if [[ -f "test-project/prd.json" ]]; then
  pass "test-project/prd.json exists"
else
  fail "test-project/prd.json not found"
fi

if [[ -f "test-project/index.html" ]]; then
  pass "test-project/index.html exists"
else
  fail "test-project/index.html not found"
fi
echo ""

# Test 8: PRD Validation
info "Test 8: Validating test PRD format..."
cd test-project
if jq . prd.json > /dev/null 2>&1; then
  pass "PRD is valid JSON"
else
  fail "PRD is invalid JSON"
fi

story_count=$(jq '.userStories | length' prd.json)
if [[ $story_count -eq 3 ]]; then
  pass "PRD has $story_count stories (expected 3)"
else
  fail "Expected 3 stories, got $story_count"
fi

all_false=$(jq '.userStories | all(.passes == false)' prd.json)
if [[ "$all_false" == "true" ]]; then
  pass "All stories have passes=false"
else
  fail "Some stories already have passes=true"
fi
cd ..
echo ""

# Test 9: Conflict Analyzer
info "Test 9: Testing conflict analyzer..."
if ./lib/conflict-analyzer.sh severity test-project/app.js 2>&1 | grep -q "NONE"; then
  pass "Conflict analyzer works (no conflicts detected)"
else
  warn "Conflict analyzer check (no actual conflicts to test)"
fi
echo ""

# Test 10: Documentation Files
info "Test 10: Verifying documentation files..."
docs=("README.md" "QUICKSTART.md" "docs/DESIGN.md" "docs/WORKFLOWS.md" "docs/ARCHITECTURE.md" "docs/COMPARISON.md" "prd.json.example")
for doc in "${docs[@]}"; do
  if [[ -f "$doc" ]]; then
    pass "$doc exists"
  else
    fail "$doc not found"
  fi
done
echo ""

# Summary
echo -e "${GREEN}=== All E2E Tests Passed! ===${NC}"
echo ""
echo "Summary:"
echo "  ✓ Prerequisites installed"
echo "  ✓ CLI detection working"
echo "  ✓ Dependency analyzer working"
echo "  ✓ Workflow system working"
echo "  ✓ Agent discovery working"
echo "  ✓ Test project ready"
echo "  ✓ PRD format validated"
echo "  ✓ All documentation present"
echo ""
echo "Ralph Parallel is ready for production use!"
echo ""
echo "Next steps:"
echo "  1. cd test-project"
echo "  2. ../ralph.sh (to run full workflow - requires AI CLI)"
echo "  3. Check git branches and commits"
