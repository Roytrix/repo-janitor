#!/usr/bin/env bash
set -euo pipefail
set -x

# Configure git
git config --global user.name "GitHub Actions Bot"
git config --global user.email "actions@github.com"

# Get default branch
DEFAULT_BRANCH=$(git remote show origin | grep "HEAD branch" | sed 's/.*: //')
echo "Default branch is $DEFAULT_BRANCH"
echo "default_branch=$DEFAULT_BRANCH" >>"$GITHUB_OUTPUT"

# Create protected branch
PROTECTED_BRANCH="protected-test-branch"
echo "Creating protected branch $PROTECTED_BRANCH"

# Check if branch already exists
if git ls-remote --heads origin "$PROTECTED_BRANCH" | grep -q "$PROTECTED_BRANCH"; then
  echo "Branch $PROTECTED_BRANCH already exists, checking out"
  git fetch origin "$PROTECTED_BRANCH"
  git checkout "$PROTECTED_BRANCH"
else
  echo "Creating new branch $PROTECTED_BRANCH"
  git checkout -b "$PROTECTED_BRANCH"
  echo "This is a protected test branch" >protected-test-file.txt
  git add protected-test-file.txt
  git commit -m "Add protected test file"
  git push origin "$PROTECTED_BRANCH"

  # Set the branch as protected via API
  echo 'Creating branch protection rule...'
  gh api \
    repos/"$GITHUB_REPOSITORY"/branches/"$PROTECTED_BRANCH"/protection \
    --method PUT \
    --field required_status_checks=null \
    --field enforce_admins=false \
    --field "required_pull_request_reviews.required_approving_review_count=1" \
    --field restrictions=null
fi

echo "protected_branch=$PROTECTED_BRANCH" >>"$GITHUB_OUTPUT"

# Create branch that will be old and merged
OLD_MERGED_BRANCH="old-merged-branch"
echo "Creating old merged branch $OLD_MERGED_BRANCH"
git checkout "$DEFAULT_BRANCH"
git checkout -b "$OLD_MERGED_BRANCH"

# Create a unique file with timestamp to ensure it's always new
TIMESTAMP=$(date +%s)
echo "Creating old merged file with timestamp $TIMESTAMP"
echo "This will be an old merged branch - $TIMESTAMP" >test_branch_cleaner_old_merged_file.md

# Debug file creation and git status
ls -la test_branch_cleaner_old_merged_file.md
git check-ignore -v test_branch_cleaner_old_merged_file.md || echo "File is not ignored"

# Use git status to see what's happening
git status

# Force add the file with verbose output
git add -v -f test_branch_cleaner_old_merged_file.md
git status

# Commit and push with additional flags
git commit -m "Add old merged file for testing - $TIMESTAMP"
git push -f origin "$OLD_MERGED_BRANCH"
echo "old_merged_branch=$OLD_MERGED_BRANCH" >>"$GITHUB_OUTPUT"

# Create branch that will be recent and merged
RECENT_MERGED_BRANCH="recent-merged-branch"
echo "Creating recent merged branch $RECENT_MERGED_BRANCH"
git checkout "$DEFAULT_BRANCH"
git checkout -b "$RECENT_MERGED_BRANCH"

# Create unique file that won't be ignored
echo "Creating recent merged file"
UNIQUE_NAME="test_branch_cleaner_recent_merged_file_$(date +%s).md"
echo "This will be a recent merged branch" >"$UNIQUE_NAME"

# Debug file creation and git status
ls -la "$UNIQUE_NAME"
git check-ignore -v "$UNIQUE_NAME" || echo "File is not ignored"

# Add the file and check again
git add "$UNIQUE_NAME"
git status

# Commit and push
git commit -m "Add recent merged file for testing"
git push origin "$RECENT_MERGED_BRANCH"
echo "recent_merged_branch=$RECENT_MERGED_BRANCH" >>"$GITHUB_OUTPUT"

# Create branch that will be unmerged
UNMERGED_BRANCH="unmerged-branch"
echo "Creating unmerged branch $UNMERGED_BRANCH"
git checkout "$DEFAULT_BRANCH"
git checkout -b "$UNMERGED_BRANCH"

# Use a unique filename with timestamp
TIMESTAMP=$(date +%s)
echo "Creating unmerged file with timestamp $TIMESTAMP"
echo "This will be an unmerged branch - $TIMESTAMP" >"test_branch_cleaner_unmerged_file_${TIMESTAMP}.md"

# Debug file creation and git status
ls -la "test_branch_cleaner_unmerged_file_${TIMESTAMP}.md"
git check-ignore -v "test_branch_cleaner_unmerged_file_${TIMESTAMP}.md" || echo "File is not ignored"

# Add the file without forcing
git add "test_branch_cleaner_unmerged_file_${TIMESTAMP}.md"
git status

# Commit and push
git commit -m "Add unmerged file for testing - $TIMESTAMP"
git push origin "$UNMERGED_BRANCH"
echo "unmerged_branch=$UNMERGED_BRANCH" >>"$GITHUB_OUTPUT"
