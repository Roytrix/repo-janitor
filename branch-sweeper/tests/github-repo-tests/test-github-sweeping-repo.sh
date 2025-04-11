#!/bin/bash

# Test script for sweeping.sh with GitHub repositories
set -e
set -o pipefail

# Source the GitHub authentication helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${PROJECT_ROOT}/branch-sweeper/scripts/github-auth.sh"

# Colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Authenticate with GitHub
if ! check_github_auth; then
    echo -e "${RED}Failed to authenticate with GitHub. Exiting.${NC}"
    exit 1
fi

# Default repo name
DEFAULT_REPO_NAME="repo-janitor-testing"

# Get repository name from argument or use default
if [ -n "$1" ]; then
    REPO_NAME=$1
else
    REPO_NAME=$DEFAULT_REPO_NAME
    echo "Using default repository name: $REPO_NAME"
fi

# Determine script locations based on where this script is run from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
if [[ -f "${PARENT_DIR}/../scripts/sweeping.sh" ]]; then
    # Running from the github-repo-tests directory
    SWEEPING_SCRIPT="${PARENT_DIR}/../scripts/sweeping.sh"
    CREATE_SCRIPT="${SCRIPT_DIR}/create-github-test-repo.sh"
    DELETE_SCRIPT="${SCRIPT_DIR}/delete-github-test-repo.sh"
elif [[ -f "${SCRIPT_DIR}/../../../branch-sweeper/scripts/sweeping.sh" ]]; then
    # Running from repo root
    SWEEPING_SCRIPT="${SCRIPT_DIR}/../../../branch-sweeper/scripts/sweeping.sh"
    CREATE_SCRIPT="${SCRIPT_DIR}/create-github-test-repo.sh"
    DELETE_SCRIPT="${SCRIPT_DIR}/delete-github-test-repo.sh"
else
    echo -e "${RED}Error: Cannot locate sweeping.sh script${NC}"
    echo "This script must be run either from the github-repo-tests directory or the repository root."
    exit 1
fi

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed.${NC}"
    echo "Please install it from https://cli.github.com/"
    exit 1
fi

# Check if authenticated with GitHub CLI and validate token permissions
echo -e "${YELLOW}Verifying GitHub authentication and permissions...${NC}"

# Run gh auth status and capture output for inspection
AUTH_OUTPUT=$(gh auth status 2>&1)
AUTH_STATUS=$?

if [[ $AUTH_STATUS -ne 0 ]]; then
    echo -e "${RED}You are not authenticated with GitHub CLI.${NC}"
    echo "Please run 'gh auth login' first."
    exit 1
fi

echo "$AUTH_OUTPUT"

# Check if we're running with a GitHub App
if [ -n "${RJ_APP_ID}" ]; then
    echo -e "${GREEN}Running with GitHub App authentication (App ID: ${RJ_APP_ID})${NC}"
    echo "Permissions for Repo Janitor App:"
    echo "- Read access to metadata"
    echo "- Read/write access to administration, code, and pull requests"
    echo "(Token scopes not applicable for GitHub Apps)"
else
    # Only check token scopes if not using GitHub App
    if ! echo "$AUTH_OUTPUT" | grep -q "repo"; then
        echo -e "${RED}Warning: Your GitHub token may not have 'repo' scope${NC}"
        echo "This is required for repository operations"
    fi
fi

# Verify API access (GitHub App compatible)
echo -e "${YELLOW}Checking API access...${NC}"

# For GitHub Apps, check repository API access instead of user API
REPO_OWNER=${GITHUB_REPOSITORY_OWNER:-$(echo $GITHUB_REPOSITORY | cut -d '/' -f1)}
REPO_NAME=${GITHUB_REPOSITORY#*/}
FULL_REPO="${REPO_OWNER}/${REPO_NAME}"

if [[ -z "$FULL_REPO" || "$FULL_REPO" == "/" ]]; then
    # Try to get it from the remote
    FULL_REPO=$(git config --get remote.origin.url | sed 's/.*github.com[:/]\(.*\)\.git/\1/')
fi

echo "Testing access to repository: $FULL_REPO"
if ! REPO_INFO=$(gh api "repos/$FULL_REPO" --jq '.name' 2>/dev/null); then
    echo -e "${RED}Error: Cannot access GitHub repository API with current token${NC}"
    echo "This might be due to insufficient permissions or a token issue"
    echo "Full error: $(gh api "repos/$FULL_REPO" 2>&1 || echo 'API call failed')"
    exit 1
fi

echo "Repository access verified: $REPO_INFO"

# Test repository permissions specifically for a GitHub App with:
# - Read access to metadata
# - Read and write access to administration, code, and pull requests
echo -e "${YELLOW}Testing repository permissions...${NC}"

# Instead of creating a new repository (which requires different permissions),
# test the specific permissions that Repo Janitor App has
echo "Testing branch list access (code permission)..."
if ! gh api "repos/$FULL_REPO/branches" --silent &>/dev/null; then
    echo -e "${RED}Warning: Token doesn't have branch read access${NC}"
    echo "The GitHub App needs 'Repository: Code' read permission"
    echo "Branch sweeping operations may fail"
else
    echo -e "${GREEN}Branch read access verified${NC}"
fi

echo "Testing branch protection access (administration permission)..."
if ! gh api "repos/$FULL_REPO/branches/main/protection" --silent &>/dev/null; then
    echo -e "${YELLOW}Note: Token doesn't have branch protection access${NC}"
    echo "This is okay if branch protection isn't enabled on this repository"
else
    echo -e "${GREEN}Branch protection access verified${NC}"
fi

echo "Testing pull request access..."
if ! gh api "repos/$FULL_REPO/pulls" --method GET --silent &>/dev/null; then
    echo -e "${RED}Warning: Token doesn't have pull request access${NC}"
    echo "The GitHub App needs 'Pull requests' permission"
else
    echo -e "${GREEN}Pull request access verified${NC}"
fi

# Check if scripts exist
if [ ! -f "$SWEEPING_SCRIPT" ]; then
    echo -e "${RED}Error: Sweeping script not found at $SWEEPING_SCRIPT${NC}"
    exit 1
fi

if [ ! -f "$CREATE_SCRIPT" ]; then
    echo -e "${RED}Error: Create repository script not found at $CREATE_SCRIPT${NC}"
    exit 1
fi

if [ ! -f "$DELETE_SCRIPT" ]; then
    echo -e "${RED}Error: Delete repository script not found at $DELETE_SCRIPT${NC}"
    exit 1
fi

# Make sure the scripts are executable
chmod +x "$SWEEPING_SCRIPT"
chmod +x "$CREATE_SCRIPT"
chmod +x "$DELETE_SCRIPT"

# Function to create a GitHub summary
create_github_summary() {
    local summary_file="github-summary.md"
    
    echo "# Branch Sweeper GitHub Test Results" > "$summary_file"
    echo "$(date)" >> "$summary_file"
    echo "" >> "$summary_file"
    echo "## Test Scenarios" >> "$summary_file"
    
    # Add more information as needed
    echo "$summary_file"  # Return the filename by printing it
}

# Function to run a test and report results
run_test() {
    local test_name="$1"
    local dry_run="$2"
    local weeks="$3"
    local default_branch="$4"
    local protected_branches="$5"
    
    # Get the current user and repo for the GitHub API - do this in a GitHub App compatible way
    local gh_user
    # Try to get from environment variable first (for GitHub Actions)
    if [[ -n "$GITHUB_REPOSITORY_OWNER" ]]; then
        gh_user="$GITHUB_REPOSITORY_OWNER"
    # For GitHub Apps, we can't use the /user endpoint, so extract from the current repo
    elif [[ -n "$FULL_REPO" ]]; then
        gh_user=$(echo "$FULL_REPO" | cut -d '/' -f1)
    # Fallback to git config
    else
        gh_user=$(git config --get remote.origin.url | sed -E 's/.*github.com[:/]([^/]+).*/\1/')
    fi
    local gh_repo="${gh_user}/${REPO_NAME}"
    
    echo -e "\n${YELLOW}====================================${NC}"
    echo -e "${YELLOW}Running Test: ${test_name}${NC}"
    echo -e "${YELLOW}====================================${NC}"
    echo "Parameters:"
    echo "  - Repository: $gh_repo"
    echo "  - Dry Run: $dry_run"
    echo "  - Weeks Threshold: $weeks"
    echo "  - Default Branch: $default_branch"
    echo "  - Protected Branches: $protected_branches"
    echo -e "${YELLOW}------------------------------------${NC}"
    
    # Setup the test repository with the exact repo name
    echo -e "\n${YELLOW}Setting up GitHub test repository...${NC}"
    "$CREATE_SCRIPT" "$REPO_NAME"
    
    # Clone the repository for testing
    if [ -d "$REPO_NAME" ]; then
        echo "Directory $REPO_NAME already exists. Removing..."
        rm -rf "$REPO_NAME"
    fi
    
    gh repo clone "$gh_repo" "$REPO_NAME"
    cd "$REPO_NAME" || exit 1
    
    # Debug branch dates
    echo -e "\n${YELLOW}Checking branch dates before sweeping:${NC}"
    while IFS= read -r branch; do
        # Skip empty lines
        [ -z "$branch" ] && continue
        
        # Remove origin/ prefix if present
        branch="${branch#origin/}"
        
        last_commit_date=$(git log -1 --format="%ci" "origin/$branch")
        merged_status=$(git branch -r --merged "origin/main" | grep -w "origin/$branch" || echo "not merged")
        echo "Branch $branch: Last commit: $last_commit_date, Status: $merged_status"
    done < <(git branch -r | grep -v "HEAD" | sed 's/origin\///')
    
    # Debug sweeping script with verbose mode
    echo -e "\n${YELLOW}Running sweeping script with verbose mode:${NC}"
    export DEBUG=true
    
    # Run the sweeping script
    "$SWEEPING_SCRIPT" "$dry_run" "$weeks" "$default_branch" "$protected_branches" "$gh_repo"
    
    echo -e "${GREEN}✓ Test completed: ${test_name}${NC}"
    
    # Check remaining branches
    echo -e "\n${YELLOW}Remaining branches after test:${NC}"
    git fetch --all
    git branch -r
    
    # Check the generated summary if it exists
    echo -e "\n${YELLOW}Summary of branch cleanup:${NC}"
    if [ -f "summary.md" ]; then
        cat summary.md
        # Copy the summary to parent directory with test name
        cp summary.md "../summary-github-$test_name.md"
    else
        echo -e "${RED}No summary file found${NC}"
    fi
    
    # Go back to parent directory
    cd ..
    
    # Export to GitHub summary if running in GitHub Actions
    if [ -n "$GITHUB_STEP_SUMMARY" ]; then
        {
            echo -e "\n## GitHub Test: ${test_name}"
            echo "Parameters:"
            echo "- Repository: ${gh_repo}"
            echo "- Dry Run: ${dry_run}"
            echo "- Weeks Threshold: ${weeks}"
            echo "- Default Branch: ${default_branch}"
            echo "- Protected Branches: ${protected_branches}"
            echo ""
            
            echo "### Remaining branches:"
            echo '```'
        } >> "${GITHUB_STEP_SUMMARY}"
        
        cd "${REPO_NAME}"
        git branch -r >> "${GITHUB_STEP_SUMMARY}"
        cd ..
        
        {
            echo '```'
            
            if [ -f "${REPO_NAME}/summary.md" ]; then
                echo "### Cleanup Summary:"
                cat "${REPO_NAME}/summary.md"
            fi
            
            echo "---"
        } >> "${GITHUB_STEP_SUMMARY}"
    fi
    
    # Clean up the repository
    echo -e "${YELLOW}Cleaning up local repository...${NC}"
    rm -rf "${REPO_NAME}"
}

# Function to clean up at the end
cleanup() {
    echo -e "\n${YELLOW}Cleaning up GitHub test repository...${NC}"
    
    # Check if the repository exists before attempting to delete it
    local gh_user
    gh_user=$(get_operating_identity)
    
    # For GitHub Apps, get the repository owner from installations
    if [[ "$gh_user" == app/* ]]; then
        # Try to get a repository from the current installation
        local app_repo_owner
        app_repo_owner=$(gh api /installation/repositories --jq '.repositories[0].owner.login' 2>/dev/null)
        if [ -n "$app_repo_owner" ]; then
            gh_user="$app_repo_owner"
        elif [ -n "$GITHUB_REPOSITORY_OWNER" ]; then
            gh_user="$GITHUB_REPOSITORY_OWNER"
        fi
    fi
    
    local gh_repo="${gh_user}/${REPO_NAME}"
    
    echo "Checking if repository ${gh_repo} exists before deletion..."
    if gh repo view "${gh_repo}" --json name &>/dev/null; then
        echo "Repository exists, proceeding with deletion..."
        
        # Verbose deletion with error handling
        if ! "$DELETE_SCRIPT" "$REPO_NAME"; then
            echo -e "${RED}Failed to delete with script, trying direct API call...${NC}"
            
            # Try direct API deletion as fallback
            if gh api --method DELETE "repos/${gh_repo}" &>/dev/null; then
                echo -e "${GREEN}Repository deleted via direct API call${NC}"
            else
                echo -e "${RED}Failed to delete repository through all methods${NC}"
                echo "You may need to manually delete the repository"
            fi
        else
            echo -e "${GREEN}Test repository cleaned up successfully${NC}"
        fi
    else
        echo -e "${YELLOW}Repository does not exist or is not accessible, no cleanup needed${NC}"
    fi
}

# Set up trap to ensure cleanup on exit
trap cleanup EXIT

# Verify GitHub permissions before running tests
echo -e "${YELLOW}Verifying GitHub permissions...${NC}"
echo "Current GitHub identity:"
CURRENT_IDENTITY=$(get_operating_identity)
echo "$CURRENT_IDENTITY"

# For GitHub Apps, check installation access instead of user identity
if [[ "$CURRENT_IDENTITY" == app/* ]]; then
    echo "Running as GitHub App, checking installation access..."
    INSTALLATION_CHECK=$(gh api /installation/repositories --jq '.total_count // 0' 2>/dev/null)
    echo "Installation has access to $INSTALLATION_CHECK repositories"
fi

echo "Available scopes and permissions:"
gh auth status -t 2>&1 | grep -E "Token scopes:|✓|×"

echo "Testing repository permissions..."

# Different API endpoints for user tokens vs GitHub Apps
if [ -n "${RJ_APP_ID}" ]; then
  echo "GitHub App authentication detected, skipping repository creation test"
  echo "Instead, validating repository administrative access..."
  
  # For GitHub Apps, check that we have admin access to at least one repo
  REPO_COUNT=$(gh api /installation/repositories --jq '.repositories | length' 2>/dev/null || echo "0")
  
  if [ "$REPO_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ App has access to $REPO_COUNT repositories${NC}"
    # Check admin permission on first repo
    REPO_FULL_NAME=$(gh api /installation/repositories --jq '.repositories[0].full_name' 2>/dev/null)
    echo "Testing administrative access on: $REPO_FULL_NAME"
    if gh api "repos/$REPO_FULL_NAME" --jq '.permissions.admin' 2>/dev/null | grep -q "true"; then
      echo -e "${GREEN}✓ App has admin permissions on $REPO_FULL_NAME${NC}"
    else
      echo -e "${YELLOW}⚠ App doesn't have admin permissions on $REPO_FULL_NAME${NC}"
      echo "Some operations might be restricted"
    fi
  else
    echo -e "${RED}⚠ No accessible repositories found for this GitHub App${NC}"
    echo "Check that the app is installed on the target repositories"
  fi
else
  # For user tokens, try to create a test repo
  echo "Testing repository creation permissions:"
  if gh api --method POST /user/repos -f name=permission_test_repo -f private=true -f auto_init=true --silent; then
    echo -e "${GREEN}✓ Repository creation permission verified${NC}"
    gh repo delete permission_test_repo --yes || echo "Failed to delete test repo, but creation worked."
  else
    echo -e "${RED}⚠ Repository creation may be restricted - tests might fail${NC}"
    echo "Check that your token has 'repo' scope"
  fi
fi

# Run all test scenarios
echo -e "${GREEN}Starting GitHub repository sweeping tests...${NC}"

# Standard run with 4 weeks threshold with extensive debugging
export DEBUG=true
echo "Running with DEBUG=true for more verbose output"
run_test "Standard run (4 weeks)" false 4 main "develop production"

# Comment out additional tests for now to focus on fixing the first one
# Only uncomment these once the first test is working properly
# # Dry run mode
# run_test "Dry run mode (4 weeks)" true 4 main "develop production"
# 
# # Different time thresholds
# run_test "Extended threshold (8 weeks)" false 8 main "develop production"

echo -e "\n${YELLOW}Tests completed. Check above logs for any errors.${NC}"