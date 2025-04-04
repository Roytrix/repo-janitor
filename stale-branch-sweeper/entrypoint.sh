#!/usr/bin/env bash
set -euo pipefail
set -x

# Main entry point for the stale-branch-sweeper GitHub Action

echo "Starting stale branch sweeper..."

# Source helper functions
# shellcheck disable=SC1091
if ! source "${GITHUB_ACTION_PATH}/scripts/setup.sh"; then
  echo "::error::Failed to source setup script"
  exit 1
fi

# Execute main functionality with error checking
if ! "${GITHUB_ACTION_PATH}/scripts/execute.sh"; then
  echo "::error::Main execution script failed"
  exit 1
fi

# Cleanup
# shellcheck disable=SC1091
if ! source "${GITHUB_ACTION_PATH}/scripts/cleanup.sh"; then
  echo "::error::Failed to source cleanup script"
  exit 1
fi

echo "Branch cleanup completed successfully!"
exit 0
