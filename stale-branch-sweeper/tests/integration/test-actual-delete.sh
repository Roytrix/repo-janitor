#!/usr/bin/env bash
set -euo pipefail
set -x

# Get the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Define the utils directory path
UTILS_DIR="${SCRIPT_DIR}/utils"

# Use setup-testing-env.sh to create test branches
echo "Setting up test environment with test branches..."
WEEKS_THRESHOLD="2"

# Run setup testing environment script to create branches
OUTPUT_FILE=$(mktemp)
"$UTILS_DIR/setup-testing-env.sh" "$WEEKS_THRESHOLD" >"$OUTPUT_FILE" 2>&1 || {
  cat "$OUTPUT_FILE"
  echo "::error::Failed to set up test environment"
  exit 1
}

# Extract branch information from the output
DEFAULT_BRANCH=$(grep "default_branch=" "$OUTPUT_FILE" | cut -d'=' -f2)
OLD_MERGED_BRANCH=$(grep "old_merged_branch=" "$OUTPUT_FILE" | cut -d'=' -f2)
RECENT_MERGED_BRANCH=$(grep "recent_merged_branch=" "$OUTPUT_FILE" | cut -d'=' -f2)
PROTECTED_BRANCH=$(grep "protected_branch=" "$OUTPUT_FILE" | cut -d'=' -f2)
UNMERGED_BRANCH=$(grep "unmerged_branch=" "$OUTPUT_FILE" | cut -d'=' -f2)

# Print branch information for debugging
echo "Using branches:"
echo "- Default branch: $DEFAULT_BRANCH"
echo "- Old merged branch: $OLD_MERGED_BRANCH"
echo "- Recent merged branch: $RECENT_MERGED_BRANCH"
echo "- Protected branch: $PROTECTED_BRANCH"
echo "- Unmerged branch: $UNMERGED_BRANCH"

# Use GitHub-provided token
export INPUT_DRY_RUN="false"
export INPUT_WEEKS_THRESHOLD="$WEEKS_THRESHOLD"
export INPUT_DEFAULT_BRANCH="$DEFAULT_BRANCH"
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
chmod +x "$GITHUB_ACTION_PATH/scripts/sweeping.sh"

# Run the execute script
"$GITHUB_ACTION_PATH/scripts/execute.sh"

# Verify old branch doesn't exist anymore
if git ls-remote --exit-code --heads origin "$OLD_MERGED_BRANCH" >/dev/null 2>&1; then
  echo "ERROR: $OLD_MERGED_BRANCH should have been deleted"
  exit 1
fi

# Verify unmerged but old branch is deleted (if it's older than a month)
# Skip this check if we know it's not that old
if git show-ref --verify --quiet "refs/remotes/origin/$UNMERGED_BRANCH"; then
  UNMERGED_BRANCH_DATE=$(git log -1 --format="%at" "origin/$UNMERGED_BRANCH")
  MONTH_AGO=$(date -d "1 month ago" +%s)
  
  if [ "$UNMERGED_BRANCH_DATE" -lt "$MONTH_AGO" ] && git ls-remote --exit-code --heads origin "$UNMERGED_BRANCH" >/dev/null 2>&1; then
    echo "ERROR: $UNMERGED_BRANCH is older than a month and should have been deleted"
    exit 1
  fi
fi

# Verify that recent-branch still exists
if ! git ls-remote --exit-code --heads origin "$RECENT_MERGED_BRANCH" >/dev/null; then
  echo "ERROR: $RECENT_MERGED_BRANCH should NOT have been deleted"
  exit 1
fi

# Verify that protected-branch still exists
if ! git ls-remote --exit-code --heads origin "$PROTECTED_BRANCH" >/dev/null; then
  echo "ERROR: $PROTECTED_BRANCH should NOT have been deleted"
  exit 1
fi

echo "Actual deletion test passed - stale branches were deleted correctly"

# Clean up
cd /tmp
rm -rf "$TEST_REPO_DIR"
exit 0
