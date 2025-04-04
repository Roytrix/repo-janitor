#!/usr/bin/env bash
set -euo pipefail
set -x

# Set default weeks threshold if not provided
WEEKS_THRESHOLD="${1:-2}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "::group::Setting up test environment"
echo "Starting test environment setup with weeks threshold: ${WEEKS_THRESHOLD}"

# Step 1: Create test branches
echo "::group::Creating test branches"
# Execute the create-tests-branches.sh script and capture outputs
OUTPUT_FILE=$(mktemp)
"${SCRIPT_DIR}/create-tests-branches.sh" >"${OUTPUT_FILE}" 2>&1 || {
  cat "${OUTPUT_FILE}"
  echo "::error::Failed to create test branches"
  exit 1
}
cat "${OUTPUT_FILE}"

# Extract the branch info from the output
DEFAULT_BRANCH=$(grep "default_branch=" "${OUTPUT_FILE}" | cut -d'=' -f2)
OLD_MERGED_BRANCH=$(grep "old_merged_branch=" "${OUTPUT_FILE}" | cut -d'=' -f2)
RECENT_MERGED_BRANCH=$(grep "recent_merged_branch=" "${OUTPUT_FILE}" | cut -d'=' -f2)
PROTECTED_BRANCH=$(grep "protected_branch=" "${OUTPUT_FILE}" | cut -d'=' -f2)
UNMERGED_BRANCH=$(grep "unmerged_branch=" "${OUTPUT_FILE}" | cut -d'=' -f2)

# Validate that we got all required branch names
if [[ -z "${DEFAULT_BRANCH}" || -z "${OLD_MERGED_BRANCH}" || -z "${RECENT_MERGED_BRANCH}" || -z "${UNMERGED_BRANCH}" ]]; then
  echo "::error::Failed to extract all required branch names"
  exit 1
fi

echo "Default branch: ${DEFAULT_BRANCH}"
echo "Old merged branch: ${OLD_MERGED_BRANCH}"
echo "Recent merged branch: ${RECENT_MERGED_BRANCH}"
echo "Protected branch: ${PROTECTED_BRANCH}"
echo "Unmerged branch: ${UNMERGED_BRANCH}"
echo "::endgroup::"

# Step 2: Merge test branches into default branch
echo "::group::Merging test branches into default branch"
# Checkout the default branch
git checkout "${DEFAULT_BRANCH}"

# Merge old branch to default
echo "Merging ${OLD_MERGED_BRANCH} into ${DEFAULT_BRANCH}"
git merge --no-ff "${OLD_MERGED_BRANCH}" -m "Merge ${OLD_MERGED_BRANCH} into ${DEFAULT_BRANCH}"
git push origin "${DEFAULT_BRANCH}"

# Merge recent branch to default
echo "Merging ${RECENT_MERGED_BRANCH} into ${DEFAULT_BRANCH}"
git merge --no-ff "${RECENT_MERGED_BRANCH}" -m "Merge ${RECENT_MERGED_BRANCH} into ${DEFAULT_BRANCH}"
git push origin "${DEFAULT_BRANCH}"
echo "::endgroup::"

# Step 3: Backdate old branch commit
echo "::group::Backdating old branch commit"
# Checkout the old branch
git checkout "${OLD_MERGED_BRANCH}"

# Calculate date in the past based on the threshold - make it clearly older
OLDER_WEEKS=$((WEEKS_THRESHOLD + 2))  # 2 extra weeks to ensure it's definitely older
PAST_DATE=$(date -d "${OLDER_WEEKS} weeks ago" +"%Y-%m-%d %H:%M:%S")
echo "Backdating branch to: ${PAST_DATE} (${OLDER_WEEKS} weeks ago, threshold is ${WEEKS_THRESHOLD} weeks)"

# Create a file with a timestamp
echo "This branch was properly backdated for testing" > backdated-test-file.txt
git add backdated-test-file.txt

# Use environment variables to set both author and committer dates
export GIT_AUTHOR_DATE="${PAST_DATE}"
export GIT_COMMITTER_DATE="${PAST_DATE}"
git commit -m "Backdated commit for testing branch cleaner"

# Force push to update the branch
git push -f origin "HEAD:${OLD_MERGED_BRANCH}"

# Print the commit date for verification
echo "Commit date is now:"
git log -1 --format="%ad" --date=iso
echo "::endgroup::"

echo "Test environment setup complete!"
echo "::endgroup::"

# Output variables that might be needed by other steps - using command grouping for efficiency
{
  echo "default_branch=${DEFAULT_BRANCH}"
  echo "old_merged_branch=${OLD_MERGED_BRANCH}"
  echo "recent_merged_branch=${RECENT_MERGED_BRANCH}"
  echo "protected_branch=${PROTECTED_BRANCH}"
  echo "unmerged_branch=${UNMERGED_BRANCH}"
} >> "${GITHUB_OUTPUT:-/dev/null}"
