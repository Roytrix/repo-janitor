#!/bin/bash

PROTECTED_BRANCHES=$(gh api repos/$1/branches --jq '.[] | select(.protected) | .name' | tr '\n' ' ')
echo "Protected branches: $PROTECTED_BRANCHES"
echo "PROTECTED_BRANCHES=$PROTECTED_BRANCHES" >> $GITHUB_ENV