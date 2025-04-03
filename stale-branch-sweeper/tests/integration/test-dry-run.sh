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

# Use absolute path to the action root directory
export GITHUB_ACTION_PATH="$ACTION_ROOT"
export GITHUB_ENV="$TEST_REPO_DIR/github_env"
export GITHUB_OUTPUT="$TEST_REPO_DIR/github_output"

# Debug output to verify paths
echo "================================================================"
echo "🔍 DEBUG: SCRIPT PATHS"
echo "Test script path: $TEST_SCRIPT_PATH"
echo "Test script dir: $TEST_SCRIPT_DIR"
echo "Tests dir: $TESTS_DIR"
echo "Action root: $ACTION_ROOT"
echo "================================================================"

echo "================================================================"
echo "🔍 DEBUG: GITHUB_ACTION_PATH"
echo "GITHUB_ACTION_PATH: $GITHUB_ACTION_PATH"
echo "Execute script path: $GITHUB_ACTION_PATH/scripts/execute.sh"
echo "================================================================"

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
export INPUT_DRY_RUN="true"
export INPUT_WEEKS_THRESHOLD="2"
export INPUT_DEFAULT_BRANCH="main"
export INPUT_GITHUB_TOKEN="${GITHUB_TOKEN}"

# Debug output for environment variables
echo "================================================================"
echo "🔍 DEBUG: ENVIRONMENT VARIABLES"
echo "GITHUB_TOKEN: ${GITHUB_TOKEN:0:3}... (partially hidden)"
echo "INPUT_GITHUB_TOKEN: ${INPUT_GITHUB_TOKEN:0:3}... (partially hidden)"
echo "INPUT_DRY_RUN: ${INPUT_DRY_RUN}"
echo "INPUT_WEEKS_THRESHOLD: ${INPUT_WEEKS_THRESHOLD}"
echo "INPUT_DEFAULT_BRANCH: ${INPUT_DEFAULT_BRANCH}"
echo "================================================================"

# Ensure INPUT_GITHUB_TOKEN is explicitly set and not empty
if [ -z "${INPUT_GITHUB_TOKEN}" ]; then
  echo "❌ ERROR: INPUT_GITHUB_TOKEN is empty before running the script"
  exit 1
fi

# Source the GITHUB_ENV to get the variables if it exists
if [[ -f "$GITHUB_ENV" ]]; then
  source "$GITHUB_ENV"
fi

# Verify the script exists before running
if [ ! -f "$GITHUB_ACTION_PATH/scripts/execute.sh" ]; then
  echo "ERROR: Execute script not found at $GITHUB_ACTION_PATH/scripts/execute.sh"
  echo "Current directory: $(pwd)"
  echo "GITHUB_ACTION_PATH contents:"
  ls -la "$GITHUB_ACTION_PATH" || echo "Directory not found"
  echo "Scripts directory contents:"
  ls -la "$GITHUB_ACTION_PATH/scripts/" || echo "Directory not found"
  exit 1
fi

echo "✅ Execute script found at: $GITHUB_ACTION_PATH/scripts/execute.sh"

# Make sure the script is executable
chmod +x "$GITHUB_ACTION_PATH/scripts/execute.sh"
echo "✅ Execute script is now executable"

# Also ensure setup.sh is executable
chmod +x "$GITHUB_ACTION_PATH/scripts/setup.sh"
echo "✅ Setup script is now executable"

# Debug the setup.sh script
echo "================================================================"
echo "🔍 DEBUG: SETUP.SH CONTENT"
head -n 20 "$GITHUB_ACTION_PATH/scripts/setup.sh"
echo "... (truncated)"
echo "================================================================"

# Run the execute script with trace mode
echo "Running execute script: $GITHUB_ACTION_PATH/scripts/execute.sh"
echo "================================================================"
set -x
"$GITHUB_ACTION_PATH/scripts/execute.sh"
set +x
echo "================================================================"
echo "✅ Execute script completed"

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
