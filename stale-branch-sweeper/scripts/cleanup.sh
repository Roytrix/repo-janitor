#!/usr/bin/env bash
set -euo pipefail
set -x

# Performs cleanup after branch sweeper execution

echo "Performing cleanup..."

echo "Cleaning up test branches regardless of test outcome..."

# Get branch names from environment variables
PROTECTED_BRANCH="${INPUT_PROTECTED_BRANCH:-}"
OLD_MERGED_BRANCH="${INPUT_OLD_MERGED_BRANCH:-}"
RECENT_MERGED_BRANCH="${INPUT_RECENT_MERGED_BRANCH:-}"
UNMERGED_BRANCH="${INPUT_UNMERGED_BRANCH:-}"
DEFAULT_BRANCH="${INPUT_DEFAULT_BRANCH:-}"

# First remove protection from protected branch
if [[ -n "${PROTECTED_BRANCH}" ]]; then
  echo "Removing branch protection rule..."
  gh api \
    "repos/${GITHUB_REPOSITORY}/branches/${PROTECTED_BRANCH}/protection" \
    --method DELETE || echo "::warning::Failed to remove protection rule via API"
  
  # Verify protection was removed
  if gh api "repos/${GITHUB_REPOSITORY}/branches/${PROTECTED_BRANCH}" 2>/dev/null | grep -q '"protected": true'; then
    echo "::warning::Failed to remove protection from ${PROTECTED_BRANCH}"
  else
    echo "Successfully removed protection from ${PROTECTED_BRANCH}"
  fi
fi

# Configure git
git config --global user.name "GitHub Actions Bot"
git config --global user.email "actions@github.com"

# Checkout default branch
git checkout "${DEFAULT_BRANCH}" || echo "::warning::Failed to checkout ${DEFAULT_BRANCH}"
git pull origin "${DEFAULT_BRANCH}" || echo "::warning::Failed to pull latest changes from ${DEFAULT_BRANCH}"

# Remove test files
echo "Cleaning up test files from ${DEFAULT_BRANCH}..."
git rm -f test_branch_cleaner_*.md 2>/dev/null || echo "No test files to remove"
git rm -f backdated-test-file.txt 2>/dev/null || echo "No backdated test file to remove"
git rm -f protected-test-file.txt 2>/dev/null || echo "No protected test file to remove"
# Add any other test files that might be created in the execute script
git rm -f .stale-branch-* 2>/dev/null || echo "No stale branch marker files to remove"

# Commit and push changes if any files were modified
if ! git diff-index --quiet HEAD 2>/dev/null; then
  git commit -m "Clean up test branch cleaner test files"
  git push origin "${DEFAULT_BRANCH}" || echo "::warning::Failed to push cleanup changes to ${DEFAULT_BRANCH}"
  echo "Successfully removed test files from ${DEFAULT_BRANCH}"
else
  echo "No test files found to clean up"
fi

# Create an array to store branch names
BRANCHES=()

# Only add non-empty branch names to the array
[[ -n "${PROTECTED_BRANCH}" ]] && BRANCHES+=("${PROTECTED_BRANCH}")
[[ -n "${OLD_MERGED_BRANCH}" ]] && BRANCHES+=("${OLD_MERGED_BRANCH}")
[[ -n "${RECENT_MERGED_BRANCH}" ]] && BRANCHES+=("${RECENT_MERGED_BRANCH}")
[[ -n "${UNMERGED_BRANCH}" ]] && BRANCHES+=("${UNMERGED_BRANCH}")

# Print the branches that will be deleted for debugging
echo "Branches to be deleted: ${BRANCHES[*]}"

# Delete each branch in the array
for BRANCH in "${BRANCHES[@]}"; do
  echo "Deleting branch: ${BRANCH}"
  git push origin --delete "${BRANCH}" 2>/dev/null || echo "Failed to delete remote branch ${BRANCH}"
  git branch -D "${BRANCH}" 2>/dev/null || echo "No local branch ${BRANCH} to delete"
done

# Clean up any other local branches created during test
echo "Cleaning up any other test branches..."
git fetch --prune origin || echo "::warning::Failed to prune remote tracking branches"

# Look for and delete any test branches that might have been created
git branch | grep -E "test-branch-|stale-test-|temp-branch-" | xargs -r git branch -D || echo "No additional test branches found"

# Upload summary to step summary
if [ -f summary.md ]; then
  cat summary.md >> "${GITHUB_STEP_SUMMARY}" || echo "::warning::Failed to upload summary to GITHUB_STEP_SUMMARY"
else
  echo "::warning::Summary file not found"
fi

# Remove temporary files
rm -f *.tmp 2>/dev/null || true
rm -f stale-branch-*.log 2>/dev/null || true
rm -f branch-sweep-*.json 2>/dev/null || true
# Remove any temporary git configuration
git config --unset-all user.name 2>/dev/null || true
git config --unset-all user.email 2>/dev/null || true

echo "Cleanup completed successfully"
