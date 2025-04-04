#!/usr/bin/env bash
set -euo pipefail
set -x

# Strict error handling
set -euo pipefail

if [ "$#" -ge 1 ]; then
  OLD_MERGED_BRANCH="$1"
else
  OLD_MERGED_BRANCH="${GITHUB_STEP_OLD_MERGED_BRANCH:-}"
fi

if [ "$#" -ge 2 ]; then
  WEEKS_THRESHOLD="$2"
else
  WEEKS_THRESHOLD="${GITHUB_INPUT_WEEKS_THRESHOLD:-2}"
fi

# Checkout the old branch
git checkout "${OLD_MERGED_BRANCH}"

# Calculate date in the past based on the threshold - make it clearly older
OLDER_WEEKS=$((WEEKS_THRESHOLD + 2))  # 2 extra weeks to ensure it's definitely older
PAST_DATE=$(date -d "${OLDER_WEEKS} weeks ago" +"%Y-%m-%d %H:%M:%S")
echo "Backdating branch to: ${PAST_DATE} (${OLDER_WEEKS} weeks ago, threshold is ${WEEKS_THRESHOLD} weeks)"

# Create a file with a timestamp
echo "This branch was properly backdated for testing" > backdated-test-file.txt
git add backdated-test-file.txt

# Use environment variables to set both author and committer dates
export GIT_AUTHOR_DATE="${PAST_DATE}"
export GIT_COMMITTER_DATE="${PAST_DATE}"
git commit -m "Backdated commit for testing branch cleaner"

# Force push to update the branch
git push -f origin "HEAD:${OLD_MERGED_BRANCH}"

# Print the commit date for verification
echo "Commit date is now:"
git log -1 --format="%ad" --date=iso