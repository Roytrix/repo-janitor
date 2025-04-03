#!/bin/bash
set -e

# Get the absolute path to the test script itself, regardless of where it's called from
TEST_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
TEST_SCRIPT_DIR="$(dirname "$TEST_SCRIPT_PATH")"
TESTS_DIR="$(dirname "$TEST_SCRIPT_DIR")"
ACTION_ROOT="$(dirname "$TESTS_DIR")"

# Load test utilities
source "$TESTS_DIR/utils/mock-env.sh"
source "$TESTS_DIR/utils/mock-gh-cli.sh"

# Set global git default branch to suppress warnings
git config --global init.defaultBranch main

# Create test repo
TEST_REPO_DIR=$(mktemp -d)
source "$TESTS_DIR/utils/mock-repo.sh"
setup_test_repo "$TEST_REPO_DIR/repo"
cd "$TEST_REPO_DIR/repo"

# Set up GitHub Actions environment variables
export GITHUB_WORKSPACE="$TEST_REPO_DIR/repo"
export GITHUB_REPOSITORY="owner/repo"
export GITHUB_ACTION_PATH="$ACTION_ROOT"
export GITHUB_ENV="$TEST_REPO_DIR/github_env"
export GITHUB_OUTPUT="$TEST_REPO_DIR/github_output"

# Create GitHub env and output files
touch "$GITHUB_ENV"
touch "$GITHUB_OUTPUT"

# Use GitHub-provided token
export INPUT_DRY_RUN="false"
export INPUT_WEEKS_THRESHOLD="2"
export INPUT_DEFAULT_BRANCH="main"
export INPUT_GITHUB_TOKEN="${GITHUB_TOKEN}"

# Ensure INPUT_GITHUB_TOKEN is explicitly set and not empty
if [ -z "${INPUT_GITHUB_TOKEN}" ]; then
  echo "❌ ERROR: Required input 'github-token' is missing"
  exit 1
fi

# Verify the script exists before running
if [ ! -f "$GITHUB_ACTION_PATH/scripts/execute.sh" ]; then
  echo "ERROR: Execute script not found at $GITHUB_ACTION_PATH/scripts/execute.sh"
  exit 1
fi

# Make sure the scripts are executable
chmod +x "$GITHUB_ACTION_PATH/scripts/execute.sh"
chmod +x "$GITHUB_ACTION_PATH/scripts/setup.sh"
chmod +x "$GITHUB_ACTION_PATH/scripts/cleanup.sh"
chmod +x "$GITHUB_ACTION_PATH/scripts/delete-stale-branches.sh"

# Run the execute script
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
