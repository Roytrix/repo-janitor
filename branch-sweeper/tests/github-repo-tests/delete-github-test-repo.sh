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

# Try to delete the repository
echo "Deleting repository: $REPO_NAME..."
if gh repo delete $REPO_NAME --yes; then
    echo "Repository $REPO_NAME has been successfully deleted."
else
    echo "Failed to delete repository. Check if the repository exists and you have proper permissions."
    exit 1
fi