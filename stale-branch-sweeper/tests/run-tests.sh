#!/bin/bash
set -e

# Change to the tests directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Create test results directory
mkdir -p results

echo "Running integration tests for stale-branch-sweeper"
echo "=================================================="

# Run individual test suites
for test_script in integration/*.sh; do
  if [[ -x "$test_script" ]]; then
    echo "Running test: $(basename "$test_script")"
    if "$test_script" > "results/$(basename "$test_script").log" 2>&1; then
      echo "✓ PASSED: $(basename "$test_script")"
    else
      echo "✗ FAILED: $(basename "$test_script")"
      cat "results/$(basename "$test_script").log"
      exit 1
    fi
  fi
done

echo "All tests passed!"
exit 0
