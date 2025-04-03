#!/bin/bash
set -e
set -o pipefail

# Setup script for stale-branch-sweeper
echo "Setting up environment..."

# Use INPUT_GITHUB_TOKEN if provided, otherwise fall back to GITHUB_TOKEN
if [ -n "${INPUT_GITHUB_TOKEN}" ]; then
  export GITHUB_TOKEN="${INPUT_GITHUB_TOKEN}"
elif [ -z "${GITHUB_TOKEN}" ]; then
  echo "::error::GitHub token is missing. Please ensure GITHUB_TOKEN is available or provide 'github-token' input."
  exit 1
fi

# Set days stale (priority to INPUT_DAYS_STALE)
if [ -z "${INPUT_DAYS_STALE}" ]; then
  echo "::warning::Using default value for 'days-stale'"
  DAYS_STALE=90
else
  DAYS_STALE="${INPUT_DAYS_STALE}"
fi
echo "DAYS_STALE=${DAYS_STALE}" >> $GITHUB_ENV

# Determine if this is a dry run (check both variable sources)
DRY_RUN="${GITHUB_EVENT_INPUTS_DRY_RUN:-${INPUT_DRY_RUN:-false}}"
echo "DRY_RUN=${DRY_RUN}" >> $GITHUB_ENV

# Set exclude pattern
EXCLUDE_PATTERN="${INPUT_EXCLUDE_PATTERN:-}"
echo "EXCLUDE_PATTERN=${EXCLUDE_PATTERN}" >> $GITHUB_ENV

# Set skip confirmation
SKIP_CONFIRMATION="${INPUT_SKIP_CONFIRMATION:-false}"
echo "SKIP_CONFIRMATION=${SKIP_CONFIRMATION}" >> $GITHUB_ENV

# Set repository
REPOSITORY="${GITHUB_REPOSITORY}"
echo "REPOSITORY=${REPOSITORY}" >> $GITHUB_ENV

# Determine weeks threshold
WEEKS_THRESHOLD="${GITHUB_EVENT_INPUTS_WEEKS_THRESHOLD:-${INPUT_WEEKS_THRESHOLD:-2}}"
echo "WEEKS_THRESHOLD=${WEEKS_THRESHOLD}" >> $GITHUB_ENV

# Determine default branch
if [[ -n "${INPUT_DEFAULT_BRANCH}" ]]; then
  DEFAULT_BRANCH="${INPUT_DEFAULT_BRANCH}"
else
  DEFAULT_BRANCH="${GITHUB_EVENT_REPOSITORY_DEFAULT_BRANCH}"
fi
echo "DEFAULT_BRANCH=${DEFAULT_BRANCH}" >> $GITHUB_ENV

# Enable debug mode if specified
if [ "${INPUT_DEBUG:-false}" = "true" ]; then
  set -x
  echo "Debug mode enabled"
fi

# Validate inputs
if [[ ! "${DAYS_STALE}" =~ ^[0-9]+$ ]]; then
    echo "::error::days-stale must be a positive number"
    exit 1
fi

if [[ ! "${WEEKS_THRESHOLD}" =~ ^[0-9]+$ ]]; then
    echo "::error::weeks-threshold must be a positive number"
    exit 1
fi

# Fetch protected branches
PROTECTED_BRANCHES=$(gh api "repos/${GITHUB_REPOSITORY}/branches" --jq '.[] | select(.protected) | .name' | tr '\n' ' ')
echo "PROTECTED_BRANCHES=${PROTECTED_BRANCHES}" >> $GITHUB_ENV

# Configure git
git config --global user.name "GitHub Actions Bot"
git config --global user.email "actions@github.com"

# Log configuration summary
echo "Running with configuration:"
echo "- Days stale: ${DAYS_STALE}"
echo "- Weeks threshold: ${WEEKS_THRESHOLD}"
echo "- Default branch: ${DEFAULT_BRANCH}"
echo "- Dry run mode: ${DRY_RUN}"
echo "- Protected branches: ${PROTECTED_BRANCHES}"

echo "Environment setup complete."
