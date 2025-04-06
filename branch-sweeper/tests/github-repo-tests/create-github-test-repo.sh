#!/bin/bash
# filepath: create-github-test-repo.sh

set -e

# Repository name (change this as needed)
REPO_NAME="branch-sweeper-test-repo"

# Step 1: Create a new GitHub repository
echo "Creating GitHub repository: $REPO_NAME"
gh repo create $REPO_NAME --public --clone

# Move into the repository directory
cd $REPO_NAME

# Step 2: Set up main branch with content
echo "# Test Repository" > README.md
git add README.md
git commit -m "Initial commit"
git push -u origin HEAD

# Rename default branch to main (if not already)
gh api repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/branches/$(git branch --show-current)/rename \
  -X POST -F new_name=main

# Step 3: Create protected branches
create_protected_branch() {
    local branch_name=$1
    local file_name=$2
    local content=$3
    
    git checkout -b $branch_name
    echo "$content" > $file_name
    git add $file_name
    git commit -m "Add $branch_name documentation"
    git push -u origin $branch_name
    
    # Set branch protection using GitHub API
    gh api repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/branches/$branch_name/protection \
      -X PUT \
      -F required_status_checks[strict]=false \
      -F required_status_checks[contexts]="[]" \
      -F enforce_admins=false \
      -F required_pull_request_reviews=null \
      -F restrictions=null
    
    git checkout main
}

# Create protected branches
create_protected_branch "develop" "DEVELOP.md" "# Development Branch"
create_protected_branch "production" "PRODUCTION.md" "# Production Branch"

# Step 4: Calculate dates relative to today
WEEKS_5_AGO=$(date -d "5 weeks ago" +"%Y-%m-%dT%H:%M:%S")
WEEKS_6_AGO=$(date -d "6 weeks ago" +"%Y-%m-%dT%H:%M:%S")
WEEKS_8_AGO=$(date -d "8 weeks ago" +"%Y-%m-%dT%H:%M:%S")
WEEKS_10_AGO=$(date -d "10 weeks ago" +"%Y-%m-%dT%H:%M:%S")
DAYS_15_AGO=$(date -d "15 days ago" +"%Y-%m-%dT%H:%M:%S")
DAYS_2_AGO=$(date -d "2 days ago" +"%Y-%m-%dT%H:%M:%S")

# Step 5: Create merged branches (stale)
create_merged_stale_branch() {
    local branch_name=$1
    local commit_date=$2
    
    git checkout -b $branch_name
    echo "# $branch_name feature" > "$branch_name.md"
    git add "$branch_name.md"
    GIT_COMMITTER_DATE="$commit_date" git commit -m "Add $branch_name feature" --date="$commit_date"
    git push -u origin $branch_name
    
    # Create and merge a PR
    PR_URL=$(gh pr create --title "Merge $branch_name" --body "Test PR for $branch_name" --base main)
    gh pr merge $PR_URL --merge
    
    git checkout main
    git pull
}

# Step 6: Create unmerged branches
create_unmerged_branch() {
    local branch_name=$1
    local commit_date=$2
    
    git checkout -b $branch_name
    echo "# $branch_name feature" > "$branch_name.md"
    git add "$branch_name.md"
    GIT_COMMITTER_DATE="$commit_date" git commit -m "Add $branch_name feature" --date="$commit_date"
    git push -u origin $branch_name
    
    git checkout main
}

# Step 7: Create PR-style merged branch
create_pr_merged_branch() {
    local branch_name=$1
    local commit_date=$2
    
    git checkout -b $branch_name
    echo "# $branch_name feature" > "$branch_name.md"
    git add "$branch_name.md"
    GIT_COMMITTER_DATE="$commit_date" git commit -m "Add $branch_name feature" --date="$commit_date"
    git push -u origin $branch_name
    
    # Create and merge a PR
    PR_URL=$(gh pr create --title "Merge $branch_name" --body "Test PR for $branch_name" --base main)
    gh pr merge $PR_URL --merge
    
    git checkout main
    git pull
}

# Create various branches with different dates
create_merged_stale_branch "feature-old-merged" "$WEEKS_6_AGO"
create_merged_stale_branch "bugfix-old-merged" "$WEEKS_5_AGO"
create_unmerged_branch "feature-very-old-unmerged" "$WEEKS_10_AGO"
create_unmerged_branch "feature-old-unmerged" "$WEEKS_8_AGO"
create_pr_merged_branch "feature-pr-merged" "$WEEKS_5_AGO"
create_unmerged_branch "feature-recent-unmerged" "$DAYS_2_AGO"

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

#!/bin/bash
# filepath: delete-github-test-repo.sh

set -e

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo "Please install it from https://cli.github.com/"
    exit 1
fi

# Check if user is authenticated with GitHub CLI
if ! gh auth status &> /dev/null; then
    echo "You are not authenticated with GitHub CLI."
    echo "Please run 'gh auth login' first."
    exit 1
fi

# Get repository name from argument or prompt for it
if [ -n "$1" ]; then
    REPO_NAME=$1
else
    echo -n "Enter repository name to delete: "
    read REPO_NAME
fi

# Validate repository name is not empty
if [ -z "$REPO_NAME" ]; then
    echo "Error: Repository name cannot be empty."
    exit 1
fi

# Confirm deletion
echo "WARNING: You are about to delete the repository: $REPO_NAME"
echo "This action CANNOT be undone."
echo -n "Are you sure you want to continue? (y/N): "
read CONFIRM

if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
    echo "Deletion cancelled."
    exit 0
fi

# Try to delete the repository
echo "Deleting repository: $REPO_NAME..."
if gh repo delete $REPO_NAME --yes; then
    echo "Repository $REPO_NAME has been successfully deleted."
else
    echo "Failed to delete repository. Check if the repository exists and you have proper permissions."
    exit 1
fi