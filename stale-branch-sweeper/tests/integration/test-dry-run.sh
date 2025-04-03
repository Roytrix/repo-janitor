#!/bin/bash
set -e

# Load test utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/utils/mock-env.sh"
source "$SCRIPT_DIR/utils/mock-gh-cli.sh"

# Create test repo
TEST_REPO_DIR=$(mktemp -d)
source "$SCRIPT_DIR/utils/mock-repo.sh"
setup_test_repo "$TEST_REPO_DIR/repo"
cd "$TEST_REPO_DIR/repo"

# Run the scripts in dry-run mode
export INPUTS_DRY_RUN="true"
export INPUTS_WEEKS_THRESHOLD="2"
export INPUTS_DEFAULT_BRANCH="main"
export GITHUB_TOKEN="mock-token"

# Source the GITHUB_ENV to get the variables
source "$GITHUB_ENV"

# Run the delete script
"$GITHUB_ACTION_PATH/scripts/execute.sh"

# Verify branches still exist (since it's a dry run)
# Check if stale-branch still exists
if ! git ls-remote --exit-code --heads origin stale-branch >/dev/null; then
  echo "ERROR: stale-branch should still exist in dry run mode"
  exit 1
fi

# Check if old-branch still exists
if ! git ls-remote --exit-code --heads origin old-branch >/dev/null; then
  echo "ERROR: old-branch should still exist in dry run mode"
  exit 1
fi

echo "Dry run test passed - no branches were deleted"

# Clean up
cd /tmp
rm -rf "$TEST_REPO_DIR"
exit 0
