#!/bin/bash
# filepath: create-github-test-repo.sh

set -e
s    if ! gh api --method POST /orgs/"$REPO_OWN    git checkout -b "$branch_name"
    echo "$content" > "$file_name"
    git add "$file_name"
    git commit -m "Add $branch_name file"
    git push -u origin "$branch_name"epos -f name="$REPO_NAME" -f description="Test repository for repo-janitor" -f private=false 2>&1 | tee /tmp/gh-create-output.log; thent -o pipefail

# Source the GitHub authentication helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../../branch-sweeper/scripts/github-auth.sh disable=SC1091
source "${PROJECT_ROOT}/branch-sweeper/scripts/github-auth.sh"

# Enable debug mode for verbose output
DEBUG=${DEBUG:-false}

# Function to log debug information
debug() {
    if [ "$DEBUG" = "true" ]; then
        echo "[DEBUG] $*"
    fi
}

# Authenticate with GitHub
if ! check_github_auth; then
    echo "Failed to authenticate with GitHub. Exiting."
    exit 1
fi

# Get repository name from argument or use default
if [ -n "$1" ]; then
    REPO_NAME=$1
else
    REPO_NAME="branch-sweeper-test-repo"
    echo "Using default repository name: $REPO_NAME"
fi

# Step 1: Create a new GitHub repository
echo "Creating GitHub repository: $REPO_NAME"
debug "Getting identity for repository creation"
if ! CURRENT_USER=$(get_operating_identity); then
    echo "Failed to get GitHub identity. Exiting."
    exit 1
fi
debug "Current identity: $CURRENT_USER"

# Handle different behavior for GitHub App vs. user
if [[ "$CURRENT_USER" == app/* ]]; then
    # For GitHub Apps, we need to use the API to create a repository in the organization/user account
    # where the app is installed
    echo "Creating repository using GitHub App: $REPO_NAME"
    
    # Use current token with API directly
    REPO_OWNER=$(gh api /installation/repositories --jq '.repositories[0].owner.login' 2>/dev/null)
    if [ -z "$REPO_OWNER" ]; then
        REPO_OWNER="${GITHUB_REPOSITORY_OWNER:-$CURRENT_USER}"
    fi
    
    echo "Creating repository as: $REPO_OWNER/$REPO_NAME"
    
    # Use API directly to create repository
    if ! gh api --method POST "/orgs/$REPO_OWNER/repos" -f name="$REPO_NAME" -f description="Test repository for repo-janitor" -f private=false 2>&1 | tee /tmp/gh-create-output.log; then
        # Fallback to create in user account
        echo "Trying to create in user account instead..."
        gh api --method POST /user/repos -f name="$REPO_NAME" -f description="Test repository for repo-janitor" -f private=false 2>&1 | tee /tmp/gh-create-output.log
    fi
else
    # For regular user authentication
    echo "Creating repository as: $CURRENT_USER/$REPO_NAME"
    
    # Use more verbose options and capture output
    if ! gh repo create "$REPO_NAME" --public --clone --description "Test repository for repo-janitor" 2>&1 | tee /tmp/gh-create-output.log; then
    echo "Error creating repository. See details below:"
    cat /tmp/gh-create-output.log
    echo "Trying alternative approach with GraphQL..."
    
    # Try alternative approach using REST API directly
    debug "Attempting to create repository via REST API"
    if ! gh api --method POST repos -f name="$REPO_NAME" -f description="Test repository for repo-janitor" -f private=false 2>&1 | tee /tmp/gh-create-output.log; then
        echo "Failed to create repository using alternative method. Check permissions."
        exit 1
    fi
    
    # Clone the repository after creating it with the API
    gh repo clone "$CURRENT_USER/$REPO_NAME" || exit 1
    fi
fi

# Move into the repository directory
cd "$REPO_NAME"

# Step 2: Set up main branch with content
echo "# Test Repository" > README.md
git add README.md
git commit -m "Initial commit"
git push -u origin HEAD

# Rename default branch to main (if not already)
gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/branches/$(git branch --show-current)/rename" \
  -X POST -F new_name=main

# Step 3: Create protected branches
create_protected_branch() {
    local branch_name=$1
    local file_name=$2
    local content=$3
    
    git checkout -b "$branch_name"
    echo "$content" > "$file_name"
    git add "$file_name"
    git commit -m "Add $branch_name documentation"
    git push -u origin "$branch_name"
    
    # Set branch protection using GitHub API
    gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/branches/$branch_name/protection" \
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
DAYS_2_AGO=$(date -d "2 days ago" +"%Y-%m-%dT%H:%M:%S")

# Step 5: Create merged branches (stale)
create_merged_stale_branch() {
    local branch_name=$1
    local commit_date=$2
    
    git checkout -b "$branch_name"
    echo "# $branch_name feature" > "$branch_name.md"
    git add "$branch_name.md"
    GIT_COMMITTER_DATE="$commit_date" git commit -m "Add $branch_name feature" --date="$commit_date"
    git push -u origin "$branch_name"
    
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
    
    git checkout -b "$branch_name"
    echo "# $branch_name feature" > "$branch_name.md"
    git add "$branch_name.md"
    GIT_COMMITTER_DATE="$commit_date" git commit -m "Add $branch_name feature" --date="$commit_date"
    git push -u origin "$branch_name"
    
    git checkout main
}

# Step 7: Create PR-style merged branch
create_pr_merged_branch() {
    local branch_name=$1
    local commit_date=$2
    
    git checkout -b "$branch_name"
    echo "# $branch_name feature" > "$branch_name.md"
    git add "$branch_name.md"
    GIT_COMMITTER_DATE="$commit_date" git commit -m "Add $branch_name feature" --date="$commit_date"
    git push -u origin "$branch_name"
    
    # Create and merge a PR
    PR_URL=$(gh pr create --title "Merge $branch_name" --body "Test PR for $branch_name" --base main)
    gh pr merge "$PR_URL" --merge
    
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
    read -r REPO_NAME
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
read -r CONFIRM

if [[ $CONFIRM != "y" && $CONFIRM != "Y" ]]; then
    echo "Deletion cancelled."
    exit 0
fi

# Try to delete the repository
echo "Deleting repository: $REPO_NAME..."
if gh repo delete "$REPO_NAME" --yes; then
    echo "Repository $REPO_NAME has been successfully deleted."
else
    echo "Failed to delete repository. Check if the repository exists and you have proper permissions."
    exit 1
fi