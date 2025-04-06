#!/bin/bash

# Test repository cleanup script
# This script ensures proper disposal of resources created by test-repository-setup-script.sh

set -e

# Colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting test repository cleanup...${NC}"

# Check if the repo-test directory exists
if [ -d "./repo-test" ]; then
    echo "Found repo-test directory, removing..."
    
    # Remove the Git configuration to prevent accidental commits
    cd ./repo-test
    if [ -d ".git" ]; then
        # Unset any Git hooks or configurations
        git config --local --unset-all core.hookspath 2>/dev/null || true
        git config --local --unset-all user.name 2>/dev/null || true
        git config --local --unset-all user.email 2>/dev/null || true
    fi
    cd ..
    
    # Remove the entire directory
    rm -rf ./repo-test
    echo -e "${GREEN}Successfully removed repo-test directory${NC}"
else
    echo -e "${YELLOW}No repo-test directory found, nothing to clean up${NC}"
fi

# Clean up fake remote if it exists
if [ -d "/tmp/fake-remote" ]; then
    echo "Removing fake remote directory..."
    rm -rf /tmp/fake-remote
    echo -e "${GREEN}Successfully removed fake remote${NC}"
fi

# Clean up any summary files
if [ -f "summary.md" ]; then
    echo "Removing summary file..."
    rm -f summary.md
    echo -e "${GREEN}Successfully removed summary file${NC}"
fi

echo -e "${GREEN}Test repository cleanup completed successfully${NC}"
echo -e "${YELLOW}You can now run new tests with a clean environment${NC}"