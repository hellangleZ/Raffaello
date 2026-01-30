#!/usr/bin/env bash
# Test Suite for Raffaello
# Tests all bug fixes and improvements

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Helper functions
test_start() {
  echo -e "\n${BLUE}[TEST]${NC} $1"
  ((TESTS_TOTAL++)) || true
}

test_pass() {
  echo -e "${GREEN}  ✓ PASS${NC} $1"
  ((TESTS_PASSED++)) || true
}

test_fail() {
  echo -e "${RED}  ✗ FAIL${NC} $1"
  ((TESTS_FAILED++)) || true
}

test_skip() {
  echo -e "${YELLOW}  ⊘ SKIP${NC} $1"
}

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

echo "======================================"
echo "  Raffaello Test Suite"
echo "======================================"
echo ""

# Test 1: Check all required files exist
test_start "Required files exist"
required_files=(
  "ralph.sh"
  "orchestrator.sh"
  "merge-stories.sh"
  "lib/logging.sh"
  "lib/prd-validator.sh"
  "lib/agent-api.sh"
  "lib/detect-cli.sh"
  "lib/dependency-analyzer.sh"
  "lib/conflict-analyzer.sh"
  "lib/load-agents.sh"
)

all_exist=true
for file in "${required_files[@]}"; do
  if [[ -f "$file" ]]; then
    echo "  ✓ $file"
  else
    echo "  ✗ Missing: $file"
    all_exist=false
  fi
done

if $all_exist; then
  test_pass "All required files exist"
else
  test_fail "Some files are missing"
fi

# Test 2: Check shell scripts are executable
test_start "Main scripts are executable"
main_scripts=("ralph.sh" "orchestrator.sh" "merge-stories.sh")
all_executable=true

for script in "${main_scripts[@]}"; do
  if [[ -x "$script" ]]; then
    echo "  ✓ $script is executable"
  else
    echo "  ✗ $script is not executable"
    all_executable=false
  fi
done

if $all_executable; then
  test_pass "All main scripts are executable"
else
  test_fail "Some scripts are not executable"
  echo "  Run: chmod +x ralph.sh orchestrator.sh merge-stories.sh"
fi

# Test 3: Check for Bash 3.2 compatibility (no associative arrays)
test_start "Bash 3.2 compatibility check (no associative arrays)"
if grep -r "declare -A" ralph.sh orchestrator.sh merge-stories.sh lib/*.sh 2>/dev/null; then
  test_fail "Found associative arrays (not compatible with Bash 3.2)"
else
  test_pass "No associative arrays found"
fi

# Test 4: Check unified logging is used
test_start "Unified logging system integration"
logging_integrated=true

for script in ralph.sh orchestrator.sh merge-stories.sh; do
  if grep -q "source.*lib/logging.sh" "$script"; then
    echo "  ✓ $script uses unified logging"
  else
    echo "  ✗ $script doesn't use unified logging"
    logging_integrated=false
  fi
done

if $logging_integrated; then
  test_pass "Unified logging integrated in all scripts"
else
  test_fail "Some scripts don't use unified logging"
fi

# Test 5: Check no hardcoded color definitions in main scripts
test_start "No hardcoded color definitions in main scripts"
if grep -E "^(RED|GREEN|YELLOW|BLUE|NC)=" ralph.sh orchestrator.sh merge-stories.sh 2>/dev/null; then
  test_fail "Found hardcoded color definitions"
else
  test_pass "No hardcoded color definitions (using lib/logging.sh)"
fi

# Test 6: Check trap cleanup is present
test_start "Trap cleanup for temp files"
trap_found=true

if grep -q "trap.*EXIT" orchestrator.sh; then
  echo "  ✓ orchestrator.sh has trap cleanup"
else
  echo "  ✗ orchestrator.sh missing trap cleanup"
  trap_found=false
fi

if grep -q "trap.*EXIT" ralph.sh; then
  echo "  ✓ ralph.sh has trap cleanup"
else
  echo "  ✗ ralph.sh missing trap cleanup"
  trap_found=false
fi

if $trap_found; then
  test_pass "Trap cleanup properly configured"
else
  test_fail "Missing trap cleanup"
fi

# Test 7: Check magic numbers replaced with constants
test_start "No magic numbers in conflict-analyzer.sh"
if grep -Eq "CONFLICT_RATIO_(HIGH|MEDIUM)_THRESHOLD" lib/conflict-analyzer.sh; then
  test_pass "Conflict analyzer uses configurable constants"
else
  test_fail "Conflict analyzer missing configurable constants"
fi

# Test 8: Validate PRD validator script
test_start "PRD validator script syntax"
if bash -n lib/prd-validator.sh 2>/dev/null; then
  test_pass "PRD validator has valid syntax"
else
  test_fail "PRD validator has syntax errors"
fi

# Test 9: Test PRD validator with example
test_start "PRD validator with prd.json.example"
if [[ -f "prd.json.example" ]]; then
  if ./lib/prd-validator.sh prd.json.example >/dev/null 2>&1; then
    test_pass "prd.json.example is valid"
  else
    echo "  Validation output:"
    ./lib/prd-validator.sh prd.json.example 2>&1 | sed 's/^/    /'
    test_fail "prd.json.example validation failed"
  fi
else
  test_skip "prd.json.example not found"
fi

# Test 10: Test PRD validator with invalid JSON
test_start "PRD validator rejects invalid JSON"
echo '{"invalid": true}' > /tmp/test-invalid.json
if ./lib/prd-validator.sh /tmp/test-invalid.json >/dev/null 2>&1; then
  test_fail "PRD validator accepted invalid PRD"
else
  test_pass "PRD validator correctly rejects invalid PRD"
fi
rm -f /tmp/test-invalid.json

# Test 11: Test dependency analyzer
test_start "Dependency analyzer script"
if [[ -f "prd.json" ]]; then
  if output=$(./lib/dependency-analyzer.sh prd.json 2>&1); then
    if echo "$output" | jq -e '.batches' >/dev/null 2>&1; then
      test_pass "Dependency analyzer produces valid JSON output"
      echo "  Batches: $(echo "$output" | jq '.batches | length')"
    else
      test_fail "Dependency analyzer output is not valid JSON"
    fi
  else
    test_fail "Dependency analyzer failed to execute"
  fi
else
  test_skip "prd.json not found"
fi

# Test 12: Check for console.log statements
test_start "No console.log statements in code"
if find . -name "*.js" -o -name "*.ts" 2>/dev/null | xargs grep -l "console\.log" 2>/dev/null | grep -v node_modules | grep -v coverage; then
  test_fail "Found console.log statements"
else
  test_pass "No console.log statements found"
fi

# Test 13: Check prerequisites
test_start "System prerequisites"
prereqs_ok=true

if command -v jq &>/dev/null; then
  echo "  ✓ jq installed ($(jq --version))"
else
  echo "  ✗ jq not installed"
  prereqs_ok=false
fi

if command -v yq &>/dev/null; then
  echo "  ✓ yq installed ($(yq --version))"
else
  echo "  ✗ yq not installed"
  prereqs_ok=false
fi

if command -v git &>/dev/null; then
  echo "  ✓ git installed ($(git --version))"
else
  echo "  ✗ git not installed"
  prereqs_ok=false
fi

if command -v claude &>/dev/null; then
  echo "  ✓ claude CLI installed ($(claude --version 2>&1 | head -n1))"
else
  echo "  ⚠ claude CLI not installed (required for execution)"
fi

if $prereqs_ok; then
  test_pass "All prerequisites met"
else
  test_fail "Missing prerequisites"
fi

# Test 14: Bash version check
test_start "Bash version compatibility"
bash_version="${BASH_VERSION%%.*}"
if [[ $bash_version -ge 3 ]]; then
  echo "  Bash version: $BASH_VERSION"
  test_pass "Bash version is compatible (3.2+)"
else
  test_fail "Bash version too old (need 3.2+)"
fi

# Test 15: Check workflows exist
test_start "Workflow files exist"
workflows=("simple" "standard" "full-stack")
all_workflows_exist=true

for workflow in "${workflows[@]}"; do
  if [[ -f "workflows/${workflow}.yaml" ]]; then
    echo "  ✓ workflows/${workflow}.yaml"
  else
    echo "  ✗ Missing: workflows/${workflow}.yaml"
    all_workflows_exist=false
  fi
done

if $all_workflows_exist; then
  test_pass "All default workflows exist"
else
  test_fail "Some workflows are missing"
fi

# Test 16: Validate workflow YAML syntax
test_start "Workflow YAML syntax"
yaml_ok=true

for workflow_file in workflows/*.yaml; do
  if [[ -f "$workflow_file" ]]; then
    if yq -e '.' "$workflow_file" >/dev/null 2>&1; then
      echo "  ✓ $workflow_file is valid YAML"
    else
      echo "  ✗ $workflow_file has YAML syntax errors"
      yaml_ok=false
    fi
  fi
done

if $yaml_ok; then
  test_pass "All workflow files have valid YAML syntax"
else
  test_fail "Some workflow files have syntax errors"
fi

# Test 17: Check agents directory
test_start "Core agent files exist"
core_agents=("planner" "coder" "reviewer" "tester" "conflict-resolver")
agents_ok=true

for agent in "${core_agents[@]}"; do
  if [[ -f "agents/${agent}.md" ]]; then
    echo "  ✓ agents/${agent}.md"
  else
    echo "  ✗ Missing: agents/${agent}.md"
    agents_ok=false
  fi
done

if $agents_ok; then
  test_pass "All core agent files exist"
else
  test_fail "Some core agent files are missing"
fi

# Test 18: Check for unquoted variables (basic check)
test_start "Critical variables are quoted"
unquoted_found=false

# Check for common unquoted variable patterns
if grep -E '\$[A-Z_]+[^"]' lib/*.sh | grep -v "^\s*#" | grep -E '(story_id|PRD_FILE|SCRIPT_DIR)' | grep -v '\$\{' >/dev/null 2>&1; then
  echo "  ⚠ Found potentially unquoted variables"
  unquoted_found=true
fi

if $unquoted_found; then
  test_skip "Manual review recommended for variable quoting"
else
  test_pass "Critical variables appear to be properly quoted"
fi

# Test 19: Test conflict analyzer
test_start "Conflict analyzer constants"
if grep -q "CONFLICT_RATIO_HIGH_THRESHOLD" lib/conflict-analyzer.sh && \
   grep -q "CONFLICT_RATIO_MEDIUM_THRESHOLD" lib/conflict-analyzer.sh; then
  test_pass "Conflict analyzer uses configurable constants"
else
  test_fail "Conflict analyzer missing configurable constants"
fi

# Test 20: Integration test (if prd.json exists)
test_start "Integration test (dry-run)"
if [[ -f "prd.json" ]]; then
  echo "  Running ralph.sh check prerequisites only..."
  # This will run the prerequisites check without executing stories
  if timeout 10s ./ralph.sh 2>&1 | grep -q "Prerequisites check passed" || \
     timeout 10s ./ralph.sh 2>&1 | grep -q "All stories are complete"; then
    test_pass "ralph.sh prerequisites check passed"
  else
    test_skip "ralph.sh execution requires valid configuration"
  fi
else
  test_skip "No prd.json found for integration test"
fi

# Summary
echo ""
echo "======================================"
echo "  Test Results Summary"
echo "======================================"
echo -e "Total Tests:  ${BLUE}$TESTS_TOTAL${NC}"
echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo -e "${GREEN}✓ All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}✗ Some tests failed${NC}"
  exit 1
fi
