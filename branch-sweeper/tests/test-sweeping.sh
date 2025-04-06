#!/bin/bash

# Test script for sweeping.sh with different configurations
set -e
set -o pipefail

# Colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Determine script locations based on where this script is run from
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
if [[ -f "${SCRIPT_DIR}/../scripts/sweeping.sh" ]]; then
    # Running from the tests directory
    SWEEPING_SCRIPT="${SCRIPT_DIR}/../scripts/sweeping.sh"
    SETUP_SCRIPT="${SCRIPT_DIR}/test-repository-setup-script.sh"
    CLEANUP_SCRIPT="${SCRIPT_DIR}/test-repository-cleanup-script.sh"
elif [[ -f "${SCRIPT_DIR}/../../branch-sweeper/scripts/sweeping.sh" ]]; then
    # Running from repo root
    SWEEPING_SCRIPT="${SCRIPT_DIR}/../../branch-sweeper/scripts/sweeping.sh"
    SETUP_SCRIPT="${SCRIPT_DIR}/test-repository-setup-script.sh" 
    CLEANUP_SCRIPT="${SCRIPT_DIR}/test-repository-cleanup-script.sh"
else
    echo -e "${RED}Error: Cannot locate sweeping.sh script${NC}"
    echo "This script must be run either from the tests directory or the repository root."
    exit 1
fi

# Check if sweeping script exists
if [ ! -f "$SWEEPING_SCRIPT" ]; then
    echo -e "${RED}Error: Sweeping script not found at $SWEEPING_SCRIPT${NC}"
    echo "Make sure you're running this script from the tests directory."
    exit 1
fi

# Make sure the script is executable
chmod +x "$SWEEPING_SCRIPT"

# Function to create a GitHub summary
create_github_summary() {
    local summary_file="github-summary.md"
    
    echo "# Branch Sweeper Test Results" > $summary_file
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
    local repo="$6"

    # Make sure test repository setup is run first
    if [ ! -d "./repo-test" ]; then
        echo "Setting up test repository first..."
        if [ -f "$SETUP_SCRIPT" ]; then
            chmod +x "$SETUP_SCRIPT"
            "$SETUP_SCRIPT"
        else
            echo -e "${RED}Error: Test repository setup script not found at $SETUP_SCRIPT${NC}"
            exit 1
        fi
    fi
    
    echo -e "\n${YELLOW}====================================${NC}"
    echo -e "${YELLOW}Running Test: ${test_name}${NC}"
    echo -e "${YELLOW}====================================${NC}"
    echo "Parameters:"
    echo "  - Dry Run: $dry_run"
    echo "  - Weeks Threshold: $weeks"
    echo "  - Default Branch: $default_branch"
    echo "  - Protected Branches: $protected_branches"
    echo "  - Repository: $repo"
    echo -e "${YELLOW}------------------------------------${NC}"
    
    # Debug branch dates
    echo -e "\n${YELLOW}Checking branch dates before sweeping:${NC}"
    cd ./repo-test
    for branch in $(git branch | cut -c 3-); do
        last_commit_date=$(git log -1 --format="%ci" $branch)
        merged_status=$(git branch --merged main | grep -w $branch || echo "not merged")
        echo "Branch $branch: Last commit: $last_commit_date, Status: $merged_status"
    done
    cd ..
    
    # Debug sweeping script with verbose mode
    echo -e "\n${YELLOW}Running sweeping script with verbose mode:${NC}"
    export DEBUG=true
    
    "$SWEEPING_SCRIPT" "$dry_run" "$weeks" "$default_branch" "$protected_branches" "$repo"
    
    echo -e "${GREEN}✓ Test completed: ${test_name}${NC}"
    
    # Check remaining branches
    echo -e "\n${YELLOW}Remaining branches after test:${NC}"
    cd ./repo-test
    git branch -a
    cd ..
    
    # Check the generated summary if it exists
    echo -e "\n${YELLOW}Summary of branch cleanup:${NC}"
    if [ -f "./repo-test/summary.md" ]; then
        cat ./repo-test/summary.md
    elif [ -f "summary.md" ]; then
        cat summary.md
    else
        echo -e "${RED}No summary file found${NC}"
    fi
    
    echo -e "${YELLOW}------------------------------------${NC}"

    # Export to GitHub summary if running in GitHub Actions
    if [ -n "$GITHUB_STEP_SUMMARY" ]; then
        echo -e "\n## Test: ${test_name}" >> $GITHUB_STEP_SUMMARY
        echo "Parameters:" >> $GITHUB_STEP_SUMMARY
        echo "- Dry Run: $dry_run" >> $GITHUB_STEP_SUMMARY
        echo "- Weeks Threshold: $weeks" >> $GITHUB_STEP_SUMMARY
        echo "- Default Branch: $default_branch" >> $GITHUB_STEP_SUMMARY
        echo "- Protected Branches: $protected_branches" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        
        echo "### Remaining branches:" >> $GITHUB_STEP_SUMMARY
        cd ./repo-test
        echo '```' >> $GITHUB_STEP_SUMMARY
        git branch -a >> $GITHUB_STEP_SUMMARY
        echo '```' >> $GITHUB_STEP_SUMMARY
        cd ..
        
        if [ -f "./repo-test/summary.md" ]; then
            echo "### Cleanup Summary:" >> $GITHUB_STEP_SUMMARY
            cat ./repo-test/summary.md >> $GITHUB_STEP_SUMMARY
        elif [ -f "summary.md" ]; then
            echo "### Cleanup Summary:" >> $GITHUB_STEP_SUMMARY
            cat summary.md >> $GITHUB_STEP_SUMMARY
        fi
        
        echo "---" >> $GITHUB_STEP_SUMMARY
    fi

    # Clean up test repository after each test
    echo -e "${YELLOW}Cleaning up test repository...${NC}"
    if [ -d "./repo-test" ]; then
        if [ -f "$CLEANUP_SCRIPT" ]; then
            chmod +x "$CLEANUP_SCRIPT"
            "$CLEANUP_SCRIPT"
        else
            echo -e "${RED}Error: Test repository cleanup script not found at $CLEANUP_SCRIPT${NC}"
            exit 1
        fi
        echo -e "${GREEN}Test repository cleaned up${NC}"
    else
        echo -e "${RED}Test repository not found for cleanup${NC}"
    fi
}

# Run all test scenarios
echo -e "${GREEN}Starting sweeping.sh tests...${NC}"

# Standard run with 4 weeks threshold
run_test "Standard run (4 weeks)" false 4 main "develop production" "test/repo"

# Dry run mode
run_test "Dry run mode (4 weeks)" true 4 main "develop production" "test/repo"

# Different time thresholds
run_test "Extended threshold (8 weeks)" false 8 main "develop production" "test/repo"

echo -e "\n${GREEN}All tests completed successfully!${NC}"