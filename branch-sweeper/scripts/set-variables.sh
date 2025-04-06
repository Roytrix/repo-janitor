#!/bin/bash
# shellcheck shell=bash

# Determine if this is a dry run
DRY_RUN="${1}"
echo "DRY_RUN=$DRY_RUN" >> $GITHUB_ENV

# Determine weeks threshold
WEEKS_THRESHOLD="${2}"
echo "WEEKS_THRESHOLD=$WEEKS_THRESHOLD" >> $GITHUB_ENV

# Determine default branch
if [[ -n "${3}" ]]; then
  DEFAULT_BRANCH="${3}"
else
  DEFAULT_BRANCH="${4}"
fi
echo "DEFAULT_BRANCH=$DEFAULT_BRANCH" >> $GITHUB_ENV

echo "Running with weeks threshold: $WEEKS_THRESHOLD"
echo "Dry run mode: $DRY_RUN"
echo "Default branch: $DEFAULT_BRANCH"