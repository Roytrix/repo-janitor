#!/bin/bash
#
# branch-cleaner.sh - Clean up stale branches that have been merged
# 
# Usage: ./branch-cleaner.sh [OPTIONS]
#
# Options:
#   --dry-run=BOOL        Run in dry-run mode (true/false)
#   --weeks-threshold=N   Age threshold in weeks (default: 2)
#
# Environment variables:
#   PROTECTED_BRANCHES    Space-separated list of protected branches
#
# Exit codes:
#   0   Success
#   1   Invalid arguments
#   2   Execution error
#
# Version: 1.0.1

set -e
set -o pipefail

# Parse arguments
DRY_RUN="${DRY_RUN}"
WEEKS_THRESHOLD="${WEEKS_THRESHOLD}"
DEFAULT_BRANCH="${DEFAULT_BRANCH}"


# Calculate date threshold based on input
CUTOFF_DATE=$(date -d "${WEEKS_THRESHOLD} weeks ago" +%s)
echo "Deleting branches merged before: $(date -d @"$CUTOFF_DATE" '+%Y-%m-%d')"

# Calculate date threshold for branches older than a month
MONTH_CUTOFF_DATE=$(date -d "1 month ago" +%s)
echo "Deleting branches older than a month: $(date -d @"$MONTH_CUTOFF_DATE" '+%Y-%m-%d')"

# If DEFAULT_BRANCH is empty, determine it (fallback mechanism)
if [[ -z "$DEFAULT_BRANCH" ]]; then
  DEFAULT_BRANCH=$(git remote show origin | grep "HEAD branch" | sed 's/.*: //')
fi
echo "Default branch is $DEFAULT_BRANCH"

# Fetch all branches
echo "Fetching all branches..."
git fetch --all

# Use protected branches from environment, ensure it's initialized
PROTECTED_BRANCHES=${PROTECTED_BRANCHES:-""}

# Protected branches that should never be deleted
# Check if default branch is already in the protected branches list
if ! echo "${PROTECTED_BRANCHES}" | grep -qw "$DEFAULT_BRANCH"; then
  PROTECTED_BRANCHES="${PROTECTED_BRANCHES} $DEFAULT_BRANCH"
fi
echo "Protected branches: $PROTECTED_BRANCHES"

# Create a unique list of branches to check against
BRANCHES_TO_CHECK=$(echo "$PROTECTED_BRANCHES $DEFAULT_BRANCH" | tr ' ' '\n' | sort -u | tr '\n' ' ')
echo "Branches to check for merge status: $BRANCHES_TO_CHECK"

# Create arrays to track results
declare -a DELETED_BRANCHES=()
declare -a SKIPPED_BRANCHES=()
declare -a NOT_MERGED_BRANCHES=()
declare -a STALE_UNMERGED_BRANCHES=()

# Function to check if branch exists
branch_exists() {
  local branch_name="$1"
  git ls-remote --exit-code --heads origin "$branch_name" &>/dev/null
  return $?
}

# Get all remote branches that have been merged to the default branch
echo "Finding merged branches..."

# Debug: Show what for-each-ref is returning
echo "DEBUG: Examining branch references from git:"
git for-each-ref --format='%(refname:short) %(committerdate:unix)' refs/remotes/origin/ | head -5

while read -r BRANCH_INFO; do
  # More reliable extraction - strip origin/ prefix but keep the rest intact
  REF_NAME=$(echo "$BRANCH_INFO" | awk '{print $1}')

  # Skip the bare "origin" entry and only process proper branch references
  if [[ "$REF_NAME" = "origin" || ! "$REF_NAME" == origin/* ]]; then
    echo "Skipping non-branch reference: $REF_NAME"
    continue
  fi

  BRANCH_NAME=${REF_NAME#origin/}
  COMMIT_DATE=$(echo "$BRANCH_INFO" | awk '{print $2}')

  echo "DEBUG: Processing ref=$REF_NAME, branch=$BRANCH_NAME"

  # Skip empty branch names and origin/HEAD
  if [[ -z "$BRANCH_NAME" || "$BRANCH_NAME" = "HEAD" ]]; then
    continue
  fi

  # Check if this is a protected branch
  if echo "$PROTECTED_BRANCHES" | grep -qw "$BRANCH_NAME"; then
    echo "Skipping protected branch: $BRANCH_NAME"
    SKIPPED_BRANCHES+=("$BRANCH_NAME (protected)")
    continue
  fi

  # Check for evidence this branch was merged anywhere
  echo "DEBUG: Looking for merge evidence for $BRANCH_NAME"

  # Use GitHub API via gh CLI to check if branch is merged
  BRANCH_IS_MERGED=false

  # Check if branch appears as merged in GitHub
  echo "DEBUG: Checking if branch is merged using GitHub API"

  # Check for closed/merged PRs that reference this branch
  PR_INFO=$(gh pr list --head "$BRANCH_NAME" --state merged --json number,title,mergedAt --limit 1 2>/dev/null || echo "[]")
  if [[ -n "$PR_INFO" && "$PR_INFO" != "[]" ]]; then
    # Fix jq syntax by properly escaping the shell commands
    PR_NUMBER=$(echo "$PR_INFO" | jq -r '.[0].number // "unknown"')
    PR_TITLE=$(echo "$PR_INFO" | jq -r '.[0].title // "unknown"')
    PR_MERGED_AT=$(echo "$PR_INFO" | jq -r '.[0].mergedAt // "unknown"')
    echo "Branch $BRANCH_NAME was merged via PR #$PR_NUMBER: $PR_TITLE (merged at $PR_MERGED_AT)"
    BRANCH_IS_MERGED=true
  else
    echo "No merged PRs found for branch $BRANCH_NAME"

    # Use Git to check if branch is fully merged into any protected branch
    for PROTECTED in $BRANCHES_TO_CHECK; do
      echo "DEBUG: Checking if $BRANCH_NAME is fully merged into $PROTECTED"
      # Use merge-base to compare the branch with protected branch
      BRANCH_TIP=$(git rev-parse "origin/$BRANCH_NAME" 2>/dev/null || echo "")
      if [[ -n "$BRANCH_TIP" ]]; then
        MERGE_BASE=$(git merge-base "origin/$BRANCH_NAME" "origin/$PROTECTED" 2>/dev/null || echo "")

        if [[ -n "$MERGE_BASE" && "$MERGE_BASE" = "$BRANCH_TIP" ]]; then
          echo "Branch $BRANCH_NAME is fully merged into protected branch $PROTECTED (fully contained)"
          BRANCH_IS_MERGED=true
          break
        fi
      fi
    done

    # Check for merge commits as fallback
    if ! $BRANCH_IS_MERGED; then
      for PROTECTED in $BRANCHES_TO_CHECK; do
        # Updated pattern to be more flexible in detecting different merge commit formats
        MERGE_PATTERN="Merge.*$BRANCH_NAME|Merge.*branch.*$BRANCH_NAME|Merge.*pull.*request.*$BRANCH_NAME|$BRANCH_NAME.*into"
        MERGE_COMMITS=$(git log "origin/$PROTECTED" --grep="$MERGE_PATTERN" -n 1 --oneline 2>/dev/null || echo "")

        if [[ -n "$MERGE_COMMITS" ]]; then
          echo "Branch $BRANCH_NAME appears to be merged into $PROTECTED based on commit messages"
          BRANCH_IS_MERGED=true
          break
        fi

        # Additional check using git branch --merged
        if git branch -r --merged "origin/$PROTECTED" | grep -q "origin/$BRANCH_NAME"; then
          echo "Branch $BRANCH_NAME is merged into $PROTECTED according to git branch --merged"
          BRANCH_IS_MERGED=true
          break
        fi
      done
    fi

    # Check the primary merge target (default branch)
    if ! $BRANCH_IS_MERGED && git branch -r --merged "origin/$DEFAULT_BRANCH" | grep -q "origin/$BRANCH_NAME"; then
      echo "DEBUG: Branch $BRANCH_NAME is merged into $DEFAULT_BRANCH according to git branch --merged"
      BRANCH_IS_MERGED=true
    fi

    # Also check each protected branch as they might be merge targets
    if ! $BRANCH_IS_MERGED; then
      for TARGET_BRANCH in $PROTECTED_BRANCHES; do
        if [[ "$TARGET_BRANCH" != "$DEFAULT_BRANCH" && $(git branch -r --merged "origin/$TARGET_BRANCH" | grep -q "origin/$BRANCH_NAME"; echo $?) -eq 0 ]]; then
          echo "DEBUG: Branch $BRANCH_NAME is merged into protected branch $TARGET_BRANCH"
          BRANCH_IS_MERGED=true
          break
        fi
      done
    fi

    # If still not identified as merged, check for merge commit messages
    if ! $BRANCH_IS_MERGED; then
      # Look for merge commits in all potential target branches
      for TARGET_BRANCH in $DEFAULT_BRANCH $PROTECTED_BRANCHES; do
        # More flexible merge commit detection patterns
        declare -a MERGE_PATTERNS=(
          "Merge.*${BRANCH_NAME}"
          "Merge.*branch.*${BRANCH_NAME}"
          "Merge.*pull.*request.*${BRANCH_NAME}"
          "${BRANCH_NAME}.*into"
        )

        # Enhanced pattern matching with error handling
        for PATTERN in "${MERGE_PATTERNS[@]}"; do
          if git log "origin/$TARGET_BRANCH" --grep="$PATTERN" -n 1 --pretty=format:"%h %s" 2>/dev/null | grep -q "${BRANCH_NAME}"; then
            echo "DEBUG: Found merge commit for $BRANCH_NAME in $TARGET_BRANCH with pattern: $PATTERN"
            BRANCH_IS_MERGED=true
            break 2
          elif [ $? -ne 1 ]; then
            echo "WARNING: Error occurred while checking pattern: $PATTERN against $TARGET_BRANCH"
          fi
        done
      done
    fi
  fi

  # Function to delete branch with proper verification
  delete_branch() {
    local branch="$1"
    local age="$2"
    local reason="$3"
    
    echo "Attempting to delete branch: $branch ($reason: $age)"
    
    # Store initial branch existence state
    branch_exists "$branch"
    local existed_before=$?
    
    if [[ "$DRY_RUN" = "true" ]]; then
      echo "[DRY RUN] Would delete branch: $branch ($reason: $age) - not actually deleting in dry run mode"
      DELETED_BRANCHES+=("$branch ($reason: $age) - [NOT ACTUALLY DELETED - DRY RUN]")
      return 0
    fi
    
    # Check if branch exists before trying to delete
    if [[ $existed_before -ne 0 ]]; then
      echo "Branch $branch doesn't exist anymore, marking as already deleted"
      DELETED_BRANCHES+=("$branch ($reason: $age) - [ALREADY DELETED]")
      return 0
    fi
    
    # Try to delete the branch
    if ! git push origin --delete "$branch"; then
      echo "::warning::Initial deletion command failed for branch: $branch"
    fi
    
    # Verify deletion by checking if the branch still exists with polling
    max_attempts=5
    attempt=1
    while [[ $attempt -le $max_attempts ]]; do
      echo "Verifying deletion (attempt $attempt/$max_attempts)..."
      git fetch origin --prune >/dev/null 2>&1 || true
      
      if ! branch_exists "$branch"; then
        # Branch is confirmed deleted
        echo "Successfully deleted branch: $branch"
        DELETED_BRANCHES+=("$branch ($reason: $age)")
        return 0
      fi
      
      # If this is the last attempt, don't wait
      if [[ $attempt -eq $max_attempts ]]; then
        break
      fi
      
      # Exponential backoff: 1s, 2s, 4s, 8s
      wait_time=$((2**(attempt-1)))
      echo "Branch still exists, waiting ${wait_time}s before retry..."
      sleep $wait_time
      ((attempt++))
    done
    
    # If we get here, deletion failed after all attempts
    echo "::warning::Failed to delete branch after $max_attempts attempts: $branch"
    SKIPPED_BRANCHES+=("$branch (deletion failed after $max_attempts attempts)")
    return 1
  }

  BRANCH_AGE=$(date -d @"$COMMIT_DATE" '+%Y-%m-%d')

  if $BRANCH_IS_MERGED; then
    # Branch is properly merged, check if it's stale
    if [[ "$COMMIT_DATE" -lt "$CUTOFF_DATE" ]]; then
      delete_branch "$BRANCH_NAME" "$BRANCH_AGE" "merged & stale"
    else
      echo "Branch is merged but not stale yet: $BRANCH_NAME (last activity: $BRANCH_AGE)"
      SKIPPED_BRANCHES+=("$BRANCH_NAME (merged but not stale)")
    fi
  else
    # Branch is not merged
    NOT_MERGED_BRANCHES+=("$BRANCH_NAME")
    echo "Branch is not merged: $BRANCH_NAME"
    
    # Check if it's very old (older than a month)
    if [[ "$COMMIT_DATE" -lt "$MONTH_CUTOFF_DATE" ]]; then
      delete_branch "$BRANCH_NAME" "$BRANCH_AGE" "older than a month"
    elif [[ "$COMMIT_DATE" -lt "$CUTOFF_DATE" ]]; then
      # It's stale but not old enough for auto-deletion
      STALE_UNMERGED_BRANCHES+=("$BRANCH_NAME (last activity: $BRANCH_AGE)")
    fi
  fi

done < <(git for-each-ref --format='%(refname:short) %(committerdate:unix)' refs/remotes/origin/)

# Create summary report
{
  echo "## Branch Cleanup Summary"
  if [[ "$DRY_RUN" = "true" ]]; then
    echo "- Mode: Dry Run"
  else
    echo "- Mode: Actual Deletion"
  fi
  echo "- Threshold: ${WEEKS_THRESHOLD} weeks (before $(date -d @"$CUTOFF_DATE" '+%Y-%m-%d'))"
  echo "- Default branch: $DEFAULT_BRANCH"
  echo "- Protected branches: $PROTECTED_BRANCHES"
  echo ""

  echo "### Deleted Branches"
  if [[ "${#DELETED_BRANCHES[@]}" -eq 0 ]]; then
    echo "- No branches deleted"
  else
    for branch in "${DELETED_BRANCHES[@]}"; do
      echo "- $branch"
    done
  fi
  echo ""

  echo "### Skipped Branches"
  if [[ "${#SKIPPED_BRANCHES[@]}" -eq 0 ]]; then
    echo "- No branches skipped"
  else
    for branch in "${SKIPPED_BRANCHES[@]}"; do
      echo "- $branch"
    done
  fi
  echo ""
} >summary.md

cat summary.md
