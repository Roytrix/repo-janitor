#!/bin/bash
# filepath: create-github-test-repo.sh

set -e
set -o pipefail

# Source the GitHub authentication helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=../../../branch-sweeper/scripts/github-auth.sh disable=SC1091
source "${PROJECT_ROOT}/branch-sweeper/scripts/github-auth.sh"

# Always show all log messages for better visibility
log() {
    echo "[INFO] $*"
}

# Parse arguments
REPO_NAME=${1:-repo-janitor-testing}
REPO_OWNER=${2:-"$GITHUB_REPOSITORY_OWNER"}

# If REPO_OWNER is not set, try to get it from the current GitHub identity
if [[ -z "$REPO_OWNER" ]]; then
    log "Trying to determine repository owner from current identity"
    REPO_OWNER=$(gh api user --jq .login 2>/dev/null || echo "")
    if [[ -z "$REPO_OWNER" ]]; then
        echo "Error: Could not determine repository owner. Please specify as the second argument."
        exit 1
    fi
    log "Determined repository owner: $REPO_OWNER"
fi

FULL_REPO_NAME="${REPO_OWNER}/${REPO_NAME}"
log "Creating repository: $FULL_REPO_NAME"

# Delete the repository if it already exists
echo "-------------------------------------------------------"
echo "STEP: Cleaning up any existing repository with the same name"
echo "-------------------------------------------------------"
echo "Executing: ${SCRIPT_DIR}/delete-github-test-repo.sh $REPO_NAME $REPO_OWNER"
"${SCRIPT_DIR}/delete-github-test-repo.sh" "$REPO_NAME" "$REPO_OWNER"
echo "Repository cleanup completed"
echo "-------------------------------------------------------"

# Calculate dates for branches
echo "-------------------------------------------------------"
echo "STEP: Calculating dates for test branches"
echo "-------------------------------------------------------"
CURRENT_DATE=$(date +%s)
echo "Current timestamp: $CURRENT_DATE ($(date -d "@$CURRENT_DATE" +"%Y-%m-%d"))"
SECONDS_PER_DAY=86400
SECONDS_PER_WEEK=$((SECONDS_PER_DAY * 7))

# For merges, calculate dates in the past
WEEKS_10_AGO=$(date -d "@$((CURRENT_DATE - SECONDS_PER_WEEK * 10))" +"%Y-%m-%d")
WEEKS_8_AGO=$(date -d "@$((CURRENT_DATE - SECONDS_PER_WEEK * 8))" +"%Y-%m-%d")
WEEKS_6_AGO=$(date -d "@$((CURRENT_DATE - SECONDS_PER_WEEK * 6))" +"%Y-%m-%d")
WEEKS_5_AGO=$(date -d "@$((CURRENT_DATE - SECONDS_PER_WEEK * 5))" +"%Y-%m-%d")
DAYS_2_AGO=$(date -d "@$((CURRENT_DATE - SECONDS_PER_DAY * 2))" +"%Y-%m-%d")

log "Date calculations:"
log "  WEEKS_10_AGO: $WEEKS_10_AGO"
log "  WEEKS_8_AGO: $WEEKS_8_AGO"
log "  WEEKS_6_AGO: $WEEKS_6_AGO"
log "  WEEKS_5_AGO: $WEEKS_5_AGO"
log "  DAYS_2_AGO: $DAYS_2_AGO"

# Create a new repository
echo "-------------------------------------------------------"
echo "STEP: Creating new repository: $FULL_REPO_NAME"
echo "-------------------------------------------------------"

# Verify we have the proper token permissions before creating repo
echo "Verifying GitHub token permissions..."
CURRENT_AUTH=$(gh auth status 2>&1)
echo "$CURRENT_AUTH"

# Display information about auth context
log "Authentication context:"
log "  User/app: $(get_operating_identity 2>/dev/null || echo "Unknown")"
echo "  Token type: ${GITHUB_TOKEN:+GitHub Token}${GITHUB_APP_TOKEN:+GitHub App Token}${GH_TOKEN:+GH Token}"

# Check if token has org admin permissions if needed
if [[ "$REPO_OWNER" != "$GITHUB_REPOSITORY_OWNER" && "$REPO_OWNER" != "$(gh api user --jq .login 2>/dev/null)" ]]; then
    echo "Testing if token has org admin permissions for $REPO_OWNER"
    ORG_PERMISSIONS=$(gh api "orgs/$REPO_OWNER" --jq '.login' 2>/dev/null || echo "ORG_ACCESS_FAILED")
    if [[ "$ORG_PERMISSIONS" == "ORG_ACCESS_FAILED" ]]; then
        echo "Warning: Token lacks permission to access organization $REPO_OWNER"
        echo "Will attempt with current user's namespace instead"
        REPO_OWNER=$(gh api user --jq .login)
        FULL_REPO_NAME="${REPO_OWNER}/${REPO_NAME}"
        echo "Updated repository name: $FULL_REPO_NAME"
    fi
fi

# Try creating the repository
echo "Attempting to create repository '$REPO_NAME'..."
echo "Create command: gh repo create \"$REPO_NAME\" --public --description \"Test repository for repo-janitor\""

if gh repo create "$REPO_NAME" --public --description "Test repository for repo-janitor"; then
    echo "✅ Repository successfully created: $FULL_REPO_NAME"
else
    CREATION_STATUS=$?
    echo "❌ Failed to create repository (exit code: $CREATION_STATUS). Checking if token has sufficient permissions..."
    TOKEN_DETAILS=$(gh auth status 2>&1)
    echo "Token details: $TOKEN_DETAILS"
    
    # If using GitHub App token, check installation permissions
    if echo "$TOKEN_DETAILS" | grep -q "app/"; then
        echo "Running as GitHub App, checking installation access..."
        INSTALLATION_INFO=$(gh api app/installations --jq 'length')
        echo "Installation has access to $INSTALLATION_INFO repositories"
    fi
    
    echo "Aborting due to repository creation failure"
    exit 1
fi

# Clone the repo locally
echo "-------------------------------------------------------"
echo "STEP: Setting up local repository"
echo "-------------------------------------------------------"
echo "Cloning repository to temporary directory..."
TEMP_DIR=$(mktemp -d)
echo "Temp directory: $TEMP_DIR"
cd "$TEMP_DIR"
echo "Cloning from: https://github.com/${FULL_REPO_NAME}.git"
git clone "https://github.com/${FULL_REPO_NAME}.git" .

# Configure git
echo "Configuring git identity..."
git config user.name "GitHub Actions"
git config user.email "actions@github.com"
echo "Git configuration complete"

# Create the initial commit
echo "# Test Repository for Repo Janitor" > README.md
git add README.md
git commit -m "Initial commit"
git push origin main

# Function to create a merged branch with a direct merge
create_merged_branch() {
    local branch_name=$1
    local commit_date=$2
    local file_name="${branch_name}.txt"
    local content="This is a test file created on the ${branch_name} branch."

    echo "Creating merged branch: $branch_name (date: $commit_date)"
    
    # Create a branch and add a file
    git checkout -b "$branch_name" main
    echo "$content" > "$file_name"
    git add "$file_name"
    
    # Use GIT_AUTHOR_DATE and GIT_COMMITTER_DATE to set date
    GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" git commit -m "Add $file_name"
    git push origin "$branch_name"
    
    # Merge the branch back to main
    git checkout main
    GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" git merge --no-ff "$branch_name" -m "Merge $branch_name into main"
    git push origin main
}

# Function to create an unmerged branch
create_unmerged_branch() {
    local branch_name=$1
    local commit_date=$2
    local file_name="${branch_name}.txt"
    local content="This is a test file created on the ${branch_name} branch."

    echo "Creating unmerged branch: $branch_name (date: $commit_date)"
    
    # Create a branch from main and add a file
    git checkout -b "$branch_name" main
    echo "$content" > "$file_name"
    git add "$file_name"
    
    # Use GIT_AUTHOR_DATE and GIT_COMMITTER_DATE to set date
    GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" git commit -m "Add $file_name"
    git push origin "$branch_name"
    
    # Go back to main
    git checkout main
}

# Function to create a merged branch via PR
create_pr_merged_branch() {
    local branch_name=$1
    local commit_date=$2
    local file_name="${branch_name}.txt"
    local content="This is a test file created on the ${branch_name} branch."

    echo "Creating PR merged branch: $branch_name (date: $commit_date)"
    
    # Create a branch and add a file
    git checkout -b "$branch_name" main
    echo "$content" > "$file_name"
    git add "$file_name"
    
    # Use GIT_AUTHOR_DATE and GIT_COMMITTER_DATE to set date
    GIT_AUTHOR_DATE="$commit_date" GIT_COMMITTER_DATE="$commit_date" git commit -m "Add $file_name"
    git push origin "$branch_name"
    
    # Create a PR and merge it
    pr_url=$(gh pr create --title "Add $branch_name" --body "Test PR for $branch_name" --head "$branch_name" --base main)
    gh pr merge "$pr_url" --merge --delete-branch=false
    
    # Go back to main and pull changes
    git checkout main
    git pull origin main
}

# Create protected branches
echo "Creating protected branches..."

# Create develop branch
git checkout -b develop main
echo "# Development branch" > develop.md
git add develop.md
git commit -m "Add develop branch"
git push origin develop

# Create production branch
git checkout -b production main
echo "# Production branch" > production.md
git add production.md
git commit -m "Add production branch"
git push origin production

# Mark branches as protected in GitHub
echo "Setting branch protection rules..."
gh api --method PUT "/repos/${FULL_REPO_NAME}/branches/main/protection" \
  -f required_status_checks[0].context="test" \
  -f enforce_admins=false \
  -f required_pull_request_reviews=null \
  -f restrictions=null

gh api --method PUT "/repos/${FULL_REPO_NAME}/branches/develop/protection" \
  -f required_status_checks[0].context="test" \
  -f enforce_admins=false \
  -f required_pull_request_reviews=null \
  -f restrictions=null

gh api --method PUT "/repos/${FULL_REPO_NAME}/branches/production/protection" \
  -f required_status_checks[0].context="test" \
  -f enforce_admins=false \
  -f required_pull_request_reviews=null \
  -f restrictions=null

# Create branches with different scenarios
echo "-------------------------------------------------------"
echo "STEP: Creating test branches with various dates and merge states"
echo "-------------------------------------------------------"
git checkout main

echo "CREATING BRANCHES THAT SHOULD BE DELETED (OLD MERGED BRANCHES)"
echo "-------------------------------------------------------------"
create_merged_branch "feature-old-merged" "$WEEKS_6_AGO" 
create_merged_branch "bugfix-old-merged" "$WEEKS_5_AGO"

echo "CREATING BRANCHES THAT SHOULD NOT BE DELETED (UNMERGED OR RECENT)"
echo "----------------------------------------------------------------"
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