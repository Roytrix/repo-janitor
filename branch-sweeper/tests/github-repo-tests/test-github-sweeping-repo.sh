#!/bin/bash

# Test script for sweeping.sh with GitHub repositories
set -e
set -o pipefail

# Colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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

# Check if user is authenticated with GitHub CLI
if ! gh auth status &> /dev/null; then
    echo -e "${RED}You are not authenticated with GitHub CLI.${NC}"
    echo "Please run 'gh auth login' first."
    exit 1
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
    
    echo "# Branch Sweeper GitHub Test Results" > $summary_file
    echo "$(date)" >> $summary_file
    echo "" >> $summary_file
    echo "## Test Scenarios" >> $summary_file
    
    # Add more information as needed
    return $summary_file
}

# Function to run a test and report results
run_test() {
    local test_name="$1"
    local dry_run="$2"
    local weeks="$3"
    local default_branch="$4"
    local protected_branches="$5"
    
    # Get the current user and repo for the GitHub API - do this first
    local gh_user
    gh_user=$(gh api user | jq -r .login)
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
    cd "$REPO_NAME"
    
    # Debug branch dates
    echo -e "\n${YELLOW}Checking branch dates before sweeping:${NC}"
    for branch in $(git branch -r | grep -v "HEAD" | sed 's/origin\///'); do
        last_commit_date=$(git log -1 --format="%ci" origin/$branch)
        merged_status=$(git branch -r --merged origin/main | grep -w "origin/$branch" || echo "not merged")
        echo "Branch $branch: Last commit: $last_commit_date, Status: $merged_status"
    done
    
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
        echo -e "\n## GitHub Test: ${test_name}" >> $GITHUB_STEP_SUMMARY
        echo "Parameters:" >> $GITHUB_STEP_SUMMARY
        echo "- Repository: $gh_repo" >> $GITHUB_STEP_SUMMARY
        echo "- Dry Run: $dry_run" >> $GITHUB_STEP_SUMMARY
        echo "- Weeks Threshold: $weeks" >> $GITHUB_STEP_SUMMARY
        echo "- Default Branch: $default_branch" >> $GITHUB_STEP_SUMMARY
        echo "- Protected Branches: $protected_branches" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        
        echo "### Remaining branches:" >> $GITHUB_STEP_SUMMARY
        echo '```' >> $GITHUB_STEP_SUMMARY
        cd "$REPO_NAME"
        git branch -r >> $GITHUB_STEP_SUMMARY
        cd ..
        echo '```' >> $GITHUB_STEP_SUMMARY
        
        if [ -f "$REPO_NAME/summary.md" ]; then
            echo "### Cleanup Summary:" >> $GITHUB_STEP_SUMMARY
            cat "$REPO_NAME/summary.md" >> $GITHUB_STEP_SUMMARY
        fi
        
        echo "---" >> $GITHUB_STEP_SUMMARY
    fi
    
    # Clean up the repository
    echo -e "${YELLOW}Cleaning up local repository...${NC}"
    rm -rf "$REPO_NAME"
}

# Function to clean up at the end
cleanup() {
    echo -e "\n${YELLOW}Cleaning up GitHub test repository...${NC}"
    
    # Check if the repository exists before attempting to delete it
    local gh_user=$(gh api user | jq -r .login)
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
gh api user --jq '.login, .type'

echo "Available scopes and permissions:"
gh auth status -t 2>&1 | grep -E "Token scopes:|✓|×"

echo "Testing repository creation permissions:"
if gh api --method POST /user/repos -f name=permission_test_repo -f private=true -f auto_init=true --silent; then
  echo -e "${GREEN}✓ Repository creation permission verified${NC}"
  gh repo delete permission_test_repo --yes || echo "Failed to delete test repo, but creation worked."
else
  echo -e "${RED}⚠ Repository creation may be restricted - tests might fail${NC}"
  echo "If you're using a GitHub App token, ensure it has 'Repository: Administration' permissions"
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