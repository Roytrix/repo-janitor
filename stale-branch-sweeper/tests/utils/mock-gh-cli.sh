#!/bin/bash

# Create a mock gh command for testing
export GH_MOCK_DIR=$(mktemp -d)

# Create a mock 'gh' command
cat > "$GH_MOCK_DIR/gh" << 'EOF'
#!/bin/bash

# Mock GitHub CLI responses

# Handle API calls to get protected branches
if [[ "$1" == "api" && "$2" == "repos/"*"/branches" ]]; then
  echo '["main", "protected-branch"]' | jq '.[] | select(.protected) | .name'
  exit 0
fi

# Handle PR list calls
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  # Check if we're looking for merged PRs
  if [[ "$*" == *"--state merged"* ]]; then
    branch_name=$(echo "$*" | grep -o "\--head [^ ]*" | cut -d " " -f2)
    
    # Return merged PR info for stale-branch
    if [[ "$branch_name" == "stale-branch" ]]; then
      echo '[{"number": 123, "title": "Stale branch PR", "mergedAt": "2023-01-01T00:00:00Z"}]'
      exit 0
    fi
  fi
  
  # Default empty response
  echo '[]'
  exit 0
fi

# Default to empty response for unknown commands
echo '[]'
exit 0
EOF

chmod +x "$GH_MOCK_DIR/gh"
export PATH="$GH_MOCK_DIR:$PATH"

cleanup_gh_mock() {
  rm -rf "$GH_MOCK_DIR"
}
trap cleanup_gh_mock EXIT
