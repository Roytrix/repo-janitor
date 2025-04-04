#!/usr/bin/env bash
set -euo pipefail
set -x

# Script for executing the main branch cleanup logic

# Load configuration from environment variables
echo "::debug::Loading configuration from environment variables"
DRY_RUN="${INPUT_DRY_RUN:-false}"
WEEKS_THRESHOLD="${INPUT_WEEKS_THRESHOLD:-4}"
DEFAULT_BRANCH="${INPUT_DEFAULT_BRANCH:-}"
PROTECTED_BRANCHES="${INPUT_PROTECTED_BRANCHES:-}"

# Export variables for use in the sweeping script
export DRY_RUN
export WEEKS_THRESHOLD
export DEFAULT_BRANCH
export PROTECTED_BRANCHES

echo "::debug::Configuration loaded - Dry run: ${DRY_RUN}, Weeks threshold: ${WEEKS_THRESHOLD}"
echo "::debug::Default branch: ${DEFAULT_BRANCH:-(auto-detect)}"
echo "::debug::Protected branches: ${PROTECTED_BRANCHES:-(none specified)}"

# Run the branch sweeping script
echo "Starting branch cleanup process..."
if ! "${GITHUB_ACTION_PATH}/scripts/sweeping.sh"; then
  echo "::error::Branch sweeping script failed"
  exit 1
fi

echo "Branch analysis and cleanup completed successfully"


