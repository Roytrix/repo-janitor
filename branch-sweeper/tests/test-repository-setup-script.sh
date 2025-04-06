#!/bin/bash

set -e

# Create a test git repository with various branch scenarios
# Change from absolute path to relative path
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
    
    git checkout -b $branch_name
    echo "# $branch_name feature" > $branch_name.md
    git add $branch_name.md
    git commit -m "Add $branch_name feature"
    git checkout main
}

# Create various branches with different dates
create_merged_stale_branch "feature-old-merged" "2023-01-01T12:00:00"
create_merged_stale_branch "bugfix-old-merged" "2023-02-01T12:00:00"
create_old_unmerged_branch "feature-very-old-unmerged" "2022-12-01T12:00:00"
create_old_unmerged_branch "feature-old-unmerged" "2023-01-15T12:00:00"
create_pr_merged_branch "feature-pr-merged" "2023-03-01T12:00:00"
create_recent_branch "feature-recent-unmerged"

# Add a remote (simulated)
git remote add origin /tmp/fake-remote
echo "Test repository created with various branch scenarios"

# Print summary
echo "============= BRANCH SUMMARY ============="
echo "Protected branches:"
echo "  - main (default)"
echo "  - develop"
echo "  - production"
echo ""
echo "Merged branches (stale):"
echo "  - feature-old-merged (from 2023-01-01)"
echo "  - bugfix-old-merged (from 2023-02-01)"
echo "  - feature-pr-merged (from 2023-03-01, PR style merge)"
echo ""
echo "Unmerged branches:"
echo "  - feature-very-old-unmerged (from 2022-12-01, older than a month)"
echo "  - feature-old-unmerged (from 2023-01-15, older than threshold)"
echo "  - feature-recent-unmerged (recent, should be kept)"
echo "=========================================="

# Print how to run the sweeper script
echo ""
echo "To test the sweeping script, run:"
echo "sweeping.sh false 4 main 'develop production' repo-test/tester"
echo ""
echo "For dry run mode:"
echo "sweeping.sh true 4 main 'develop production' repo-test/tester"