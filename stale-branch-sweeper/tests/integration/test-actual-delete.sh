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

# Set up GitHub Actions environment variables
export GITHUB_WORKSPACE="$TEST_REPO_DIR/repo"
export GITHUB_REPOSITORY="owner/repo"
# Ensure we get the absolute path to the action directory
ACTION_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GITHUB_ACTION_PATH="$ACTION_PATH"
export GITHUB_ENV="$TEST_REPO_DIR/github_env"
export GITHUB_OUTPUT="$TEST_REPO_DIR/github_output"

# Debug output to verify paths
echo "GITHUB_ACTION_PATH: $GITHUB_ACTION_PATH"
echo "Execute script path: $GITHUB_ACTION_PATH/scripts/execute.sh"

# Create GitHub env file
touch "$GITHUB_ENV"
touch "$GITHUB_OUTPUT"

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
export INPUT_DRY_RUN="false"
export INPUT_WEEKS_THRESHOLD="2"
export INPUT_DEFAULT_BRANCH="main"
export INPUT_GITHUB_TOKEN="${GITHUB_TOKEN}"

# Source the GITHUB_ENV to get the variables if it exists
if [[ -f "$GITHUB_ENV" ]]; then
  source "$GITHUB_ENV"
fi

# Verify the script exists before running
if [ ! -f "$GITHUB_ACTION_PATH/scripts/execute.sh" ]; then
  echo "ERROR: Execute script not found at $GITHUB_ACTION_PATH/scripts/execute.sh"
  echo "Current directory: $(pwd)"
  echo "Contents of $GITHUB_ACTION_PATH/scripts/:"
  ls -la "$GITHUB_ACTION_PATH/scripts/" || echo "Directory not found"
  exit 1
fi

# Make sure the script is executable
chmod +x "$GITHUB_ACTION_PATH/scripts/execute.sh"

# Run the execute script with correct path
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
