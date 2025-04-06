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