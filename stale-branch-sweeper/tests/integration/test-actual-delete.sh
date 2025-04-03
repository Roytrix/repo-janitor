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

# Run the scripts in actual deletion mode
export INPUTS_DRY_RUN="false"
export INPUTS_WEEKS_THRESHOLD="2"
export INPUTS_DEFAULT_BRANCH="main"
export GITHUB_TOKEN="mock-token"

# Export the variables in the format expected by delete-stale-branches.sh
export DRY_RUN="${INPUTS_DRY_RUN}"
export WEEKS_THRESHOLD="${INPUTS_WEEKS_THRESHOLD}"
export DEFAULT_BRANCH="${INPUTS_DEFAULT_BRANCH}"

# Source the GITHUB_ENV to get the variables
# shellcheck source=/dev/null
source "$GITHUB_ENV"

# Run the delete script
"$GITHUB_ACTION_PATH/scripts/execute.sh"

# Verify stale-branch and old-branch don't exist anymore
if git ls-remote --exit-code --heads origin stale-branch >/dev/null 2>&1; then
  echo "ERROR: stale-branch should have been deleted"
  exit 1
fi

if git ls-remote --exit-code --heads origin old-branch >/dev/null 2>&1; then
  echo "ERROR: old-branch should have been deleted"
  exit 1
fi

# Verify that recent-branch still exists
if ! git ls-remote --exit-code --heads origin recent-branch >/dev/null; then
  echo "ERROR: recent-branch should NOT have been deleted"
  exit 1
fi

# Verify that protected-branch still exists
if ! git ls-remote --exit-code --heads origin protected-branch >/dev/null; then
  echo "ERROR: protected-branch should NOT have been deleted"
  exit 1
fi

echo "Actual deletion test passed - stale branches were deleted correctly"

# Clean up
cd /tmp
rm -rf "$TEST_REPO_DIR"
exit 0
