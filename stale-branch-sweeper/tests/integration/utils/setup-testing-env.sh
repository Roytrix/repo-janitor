#!/usr/bin/env bash
set -euo pipefail
set -x

# Determine script directory for relative path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "::debug::Creating test branches for integration tests..."

# Call the create-test-branches.sh script with proper error handling
if ! "${SCRIPT_DIR}/create-test-branches.sh"; then
  echo "::error::Failed to create test branches"
  exit 1
fi

echo "::debug::Test branches created successfully"

# Merge test branches into default branch
echo "::debug::Merging test branches into default branch..."
if ! "${SCRIPT_DIR}/merge-test-branches-into-default-branch.sh"; then
  echo "::error::Failed to merge test branches into default branch"
  exit 1
fi

echo "::debug::Test branches merged successfully"

# Backdate commits on old branches
echo "::debug::Backdating commits on old branches..."
if ! "${SCRIPT_DIR}/backdate-old-branch-commits.sh"; then
  echo "::error::Failed to backdate commits on old branches"
  exit 1
fi

echo "::debug::Old branch commits backdated successfully"

