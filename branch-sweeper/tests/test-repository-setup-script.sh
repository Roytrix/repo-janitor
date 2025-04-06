#!/bin/bash

set -e

# Configure git user identity
git config --global user.name "GitHub Actions"
git config --global user.email "actions@github.com"

# Create a test git repository with various branch scenarios
mkdir -p ./repo-test
cd ./repo-test

# Initialize the repository
git init

# Create the default/main branch with some content
echo "# Test Repository" > README.md
git add README.md
git commit -m "Initial commit"

# Ensure we're on main branch
git checkout -b main
git branch -D master 2>/dev/null || true

# Create a first protected branch
git checkout -b develop
echo "# Development Branch" > DEVELOP.md
git add DEVELOP.md
git commit -m "Add develop documentation"
git checkout main

# Create another protected branch
git checkout -b production
echo "# Production Branch" > PRODUCTION.md
git add PRODUCTION.md
git commit -m "Add production documentation"
git checkout main

# Calculate dates relative to today instead of hardcoded
CURRENT_DATE=$(date +%s)
WEEKS_5_AGO=$(date -d "5 weeks ago" +"%Y-%m-%dT%H:%M:%S")
WEEKS_6_AGO=$(date -d "6 weeks ago" +"%Y-%m-%dT%H:%M:%S")
WEEKS_10_AGO=$(date -d "10 weeks ago" +"%Y-%m-%dT%H:%M:%S")
WEEKS_8_AGO=$(date -d "8 weeks ago" +"%Y-%m-%dT%H:%M:%S")
DAYS_15_AGO=$(date -d "15 days ago" +"%Y-%m-%dT%H:%M:%S")
DAYS_2_AGO=$(date -d "2 days ago" +"%Y-%m-%dT%H:%M:%S")

# Create a merged branch that's older than the threshold (stale)
create_merged_stale_branch() {
    local branch_name=$1
    local commit_date="$2"
    
    git checkout -b $branch_name
    echo "# $branch_name feature" > $branch_name.md
    git add $branch_name.md
    GIT_COMMITTER_DATE="$commit_date" git commit -m "Add $branch_name feature" --date="$commit_date"
    git checkout main
    git merge --no-ff $branch_name -m "Merge branch '$branch_name'"
}

# Create a non-merged branch that's older than a month
create_old_unmerged_branch() {
    local branch_name=$1
    local commit_date="$2"
    
    git checkout -b $branch_name
    echo "# $branch_name feature" > $branch_name.md
    git add $branch_name.md
    GIT_COMMITTER_DATE="$commit_date" git commit -m "Add $branch_name feature" --date="$commit_date"
    git checkout main
}

# Create a branch that's merged via PR-style merge commit
create_pr_merged_branch() {
    local branch_name=$1
    local commit_date="$2"
    
    git checkout -b $branch_name
    echo "# $branch_name feature" > $branch_name.md
    git add $branch_name.md
    GIT_COMMITTER_DATE="$commit_date" git commit -m "Add $branch_name feature" --date="$commit_date"
    git checkout main
    git merge --no-ff $branch_name -m "Merge pull request #123 from user/$branch_name"
}

# Create a recent unmerged branch that should be kept
create_recent_branch() {
    local branch_name=$1
    local commit_date="$2"
    
    git checkout -b $branch_name
    echo "# $branch_name feature" > $branch_name.md
    git add $branch_name.md
    GIT_COMMITTER_DATE="$commit_date" git commit -m "Add $branch_name feature" --date="$commit_date"
    git checkout main
}

# Create various branches with different dates (using relative dates)
create_merged_stale_branch "feature-old-merged" "$WEEKS_6_AGO"
create_merged_stale_branch "bugfix-old-merged" "$WEEKS_5_AGO"
create_old_unmerged_branch "feature-very-old-unmerged" "$WEEKS_10_AGO"
create_old_unmerged_branch "feature-old-unmerged" "$WEEKS_8_AGO"
create_pr_merged_branch "feature-pr-merged" "$WEEKS_5_AGO"
create_recent_branch "feature-recent-unmerged" "$DAYS_2_AGO"

echo "Test repository created with various branch scenarios"

# Print summary
echo "============= BRANCH SUMMARY ============="
echo "Protected branches:"
echo "  - main (default)"
echo "  - develop"
echo "  - production"
echo ""
echo "Merged branches (stale):"
echo "  - feature-old-merged (from $WEEKS_6_AGO)"
echo "  - bugfix-old-merged (from $WEEKS_5_AGO)"
echo "  - feature-pr-merged (from $WEEKS_5_AGO, PR style merge)"
echo ""
echo "Unmerged branches:"
echo "  - feature-very-old-unmerged (from $WEEKS_10_AGO, older than a month)"
echo "  - feature-old-unmerged (from $WEEKS_8_AGO, older than threshold)"
echo "  - feature-recent-unmerged (from $DAYS_2_AGO, recent, should be kept)"
echo "=========================================="