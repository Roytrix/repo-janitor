#!/bin/bash
set -e

# Performs cleanup after branch sweeper execution

echo "Performing cleanup..."

# Upload summary to step summary
if [ -f summary.md ]; then
  cat summary.md >> $GITHUB_STEP_SUMMARY
else
  echo "::warning::Summary file not found"
fi

# Remove temporary files
# ...existing cleanup logic...

echo "Cleanup completed successfully"
