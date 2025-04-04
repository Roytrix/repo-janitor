#!/usr/bin/env bash
set -euo pipefail
set -x

# Use command line arguments with fallback to environment variables
DEFAULT_BRANCH="${1:-${DEFAULT_BRANCH_ENV:-main}}"
OLD_MERGED_BRANCH="${2:-${OLD_MERGED_BRANCH_ENV:-}}"
RECENT_MERGED_BRANCH="${3:-${RECENT_MERGED_BRANCH_ENV:-}}"

# Check if required variables are set
if [ -z "${OLD_MERGED_BRANCH}" ] || [ -z "${RECENT_MERGED_BRANCH}" ]; then
  echo "::error::Required branch names are not set. Please provide them as arguments or set environment variables."
  echo "Usage: $0 [default_branch] [old_merged_branch] [recent_merged_branch]"
  exit 1
fi

# Merge old branch to default
git checkout "${DEFAULT_BRANCH}"
git merge --no-ff "${OLD_MERGED_BRANCH}" -m "Merge ${OLD_MERGED_BRANCH} into ${DEFAULT_BRANCH}"
git push origin "${DEFAULT_BRANCH}"

# Merge recent branch to default
git merge --no-ff "${RECENT_MERGED_BRANCH}" -m "Merge ${RECENT_MERGED_BRANCH} into ${DEFAULT_BRANCH}"
git push origin "${DEFAULT_BRANCH}"