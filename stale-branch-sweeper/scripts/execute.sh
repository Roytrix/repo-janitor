#!/bin/bash
set -e
set -o pipefail

# Main execution script for stale-branch-sweeper
echo "Executing branch cleanup..."

# Source setup script to prepare environment and validate inputs
source "${GITHUB_ACTION_PATH}/scripts/setup.sh"

# Execute the main branch deletion logic
"${GITHUB_ACTION_PATH}/scripts/delete-stale-branches.sh"

# Perform cleanup operations
source "${GITHUB_ACTION_PATH}/scripts/cleanup.sh"

echo "Branch cleanup completed."


