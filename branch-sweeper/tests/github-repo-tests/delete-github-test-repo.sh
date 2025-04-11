#!/bin/bash
# filepath: delete-github-test-repo.sh

set -e

# Source the GitHub authentication helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
source "${PROJECT_ROOT}/branch-sweeper/scripts/github-auth.sh"

# Check if GitHub CLI is installed
if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo "Please install it from https://cli.github.com/"
    exit 1
fi

# Authenticate with GitHub
if ! check_github_auth; then
    echo "Failed to authenticate with GitHub. Exiting."
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

# Show more details about the repository before trying to delete it
echo "Deleting repository: $REPO_NAME..."
echo "Current identity:"
CURRENT_IDENTITY=$(get_operating_identity)
echo "$CURRENT_IDENTITY"

echo "Checking repository details..."
if gh repo view $REPO_NAME --json owner,name,visibility,url 2>/dev/null; then
    echo "Repository exists and is accessible."
else
    echo "Could not fetch repository details. HTTP status: $?"
    echo "Full repository path may be incorrect. Trying with current identity's namespace..."
    CURRENT_USER=$(get_operating_identity)
    # For GitHub Apps, try to find the repository owner from installations
    if [[ "$CURRENT_USER" == app/* && -n "$GITHUB_TOKEN" ]]; then
        # Try to get a repository from the current installation
        REPO_OWNER=$(gh api /installation/repositories --jq '.repositories[0].owner.login' 2>/dev/null)
        if [ -n "$REPO_OWNER" ]; then
            CURRENT_USER="$REPO_OWNER"
        fi
    fi
    FULL_REPO_PATH="$CURRENT_USER/$REPO_NAME"
    echo "Attempting with full path: $FULL_REPO_PATH"
    if gh repo view "$FULL_REPO_PATH" --json owner,name,visibility,url 2>/dev/null; then
        echo "Repository found using full path: $FULL_REPO_PATH"
        REPO_NAME="$FULL_REPO_PATH"
    else
        echo "Repository not found with either path. Proceeding with delete attempt anyway."
    fi
fi

# Try to delete the repository with debug info
echo "Running deletion command with verbose output..."
if GH_DEBUG=api gh repo delete $REPO_NAME --yes; then
    echo "Repository $REPO_NAME has been successfully deleted."
else
    DELETE_STATUS=$?
    echo "Failed to delete repository. Exit code: $DELETE_STATUS"
    echo "Checking if repository still exists..."
    if gh repo view $REPO_NAME --json owner,name,visibility,url 2>/dev/null; then
        echo "Repository still exists but delete operation failed."
        echo "This could be a permissions issue - ensure you have admin rights to this repository."
    else
        echo "Repository does not seem to exist although deletion returned an error."
        echo "It may have already been deleted or named differently."
    fi
    exit 1
fi