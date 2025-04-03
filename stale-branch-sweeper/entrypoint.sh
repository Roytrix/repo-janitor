#!/bin/bash
set -e
set -u

# Main entry point for the stale-branch-sweeper GitHub Action

echo "Starting stale branch sweeper..."

# Source helper functions
source "${GITHUB_ACTION_PATH}/scripts/setup.sh"

# Execute main functionality
"${GITHUB_ACTION_PATH}/scripts/execute.sh"

# Cleanup
source "${GITHUB_ACTION_PATH}/scripts/cleanup.sh"

echo "Branch cleanup completed successfully!"
exit 0
