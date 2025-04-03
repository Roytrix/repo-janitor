#!/bin/bash
set -e

# Load test utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/utils/mock-env.sh"
source "$SCRIPT_DIR/utils/mock-gh-cli.sh"

# Set global git default branch to suppress warnings
git config --global init.defaultBranch main

# Create test repo
TEST_REPO_DIR=$(mktemp -d)
source "$SCRIPT_DIR/utils/mock-repo.sh"
setup_test_repo "$TEST_REPO_DIR/repo"
cd "$TEST_REPO_DIR/repo"

# Token handling - use actual token in GitHub Actions, mock token in local dev
if [[ -n "${GITHUB_ACTIONS}" ]]; then
  # In GitHub Actions workflow, GITHUB_TOKEN is already available
  echo "Using GitHub-provided token"
else
  # For local testing, use a mock token
  export GITHUB_TOKEN="mock-token"
  echo "Using mock token for local testing"
fi

# Set up environment variables following GitHub Actions conventions
export INPUT_DRY_RUN="true"
export INPUT_WEEKS_THRESHOLD="2"
export INPUT_DEFAULT_BRANCH="main"
export INPUT_GITHUB_TOKEN="${GITHUB_TOKEN}"

# Export the variables in the format expected by delete-stale-branches.sh
export DRY_RUN="${INPUT_DRY_RUN}"
export WEEKS_THRESHOLD="${INPUT_WEEKS_THRESHOLD}"
export DEFAULT_BRANCH="${INPUT_DEFAULT_BRANCH}"

# Source the GITHUB_ENV to get the variables
# shellcheck source=/dev/null
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
