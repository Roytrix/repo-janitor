#!/bin/bash

# Create a temporary file to represent GITHUB_ENV
export GITHUB_ENV=$(mktemp)
export GITHUB_OUTPUT=$(mktemp)
export GITHUB_STEP_SUMMARY=$(mktemp)
export GITHUB_REPOSITORY="test-org/test-repo"
export GITHUB_ACTION_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export GITHUB_EVENT_REPOSITORY_DEFAULT_BRANCH="main"

# Mock environment write function used by GitHub Actions
github_env_write() {
  echo "$1" >> "$GITHUB_ENV"
}

# Clean up temporary files on exit
cleanup() {
  rm -f "$GITHUB_ENV" "$GITHUB_OUTPUT" "$GITHUB_STEP_SUMMARY"
}
trap cleanup EXIT
