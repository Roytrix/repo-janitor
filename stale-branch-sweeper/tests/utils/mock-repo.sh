#!/bin/bash
set -e

# Create a test repository with branches of various ages

setup_test_repo() {
  local test_dir="$1"
  
  # Create a fresh test directory
  rm -rf "$test_dir"
  mkdir -p "$test_dir"
  cd "$test_dir"
  
  # Initialize git
  git init
  git config --global user.name "Test User"
  git config --global user.email "test@example.com"
  
  # Create main branch with some content
  echo "# Test Repository" > README.md
  git add README.md
  git commit -m "Initial commit"
  
  # Rename branch to main if needed
  git branch -M main
  
  # Create some branches with different timestamps
  
  # 1. Recent branch (less than 2 weeks old)
  git checkout -b recent-branch
  echo "Recent branch content" > recent.txt
  git add recent.txt
  git commit -m "Add recent content"
  
  # 2. Stale branch (more than 2 weeks old)
  git checkout -b stale-branch
  echo "Stale branch content" > stale.txt
  git add stale.txt
  git commit -m "Add stale content"
  # Modify commit date to be more than 2 weeks old
  GIT_COMMITTER_DATE="3 weeks ago" git commit --amend --no-edit --date="3 weeks ago"
  
  # 3. Very old branch (more than a month old)
  git checkout -b old-branch
  echo "Old branch content" > old.txt
  git add old.txt
  git commit -m "Add old content"
  # Modify commit date to be more than a month old
  GIT_COMMITTER_DATE="5 weeks ago" git commit --amend --no-edit --date="5 weeks ago"
  
  # 4. Protected branch
  git checkout -b protected-branch
  echo "Protected branch content" > protected.txt
  git add protected.txt
  git commit -m "Add protected content"
  
  # Return to main branch
  git checkout main
  
  # Create a mock remote origin
  mkdir -p ../remote
  cd ../remote
  git init --bare
  cd ../repo
  git remote add origin ../remote
  
  # Push all branches
  git push origin --all
  
  # Return to the main branch
  git checkout main
  
  echo "Test repository setup complete"
}

# Export the setup function
export -f setup_test_repo
