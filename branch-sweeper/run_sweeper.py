#!/usr/bin/env python3
# filepath: /home/roytrix/Documents/source-code/repo-janitor/branch-sweeper/run_sweeper.py

"""
Script to run the branch sweeper in Python.
This is a wrapper script that provides a convenient way to run the branch sweeper.
"""

import argparse
import os
import sys
from pathlib import Path

# Add current directory to Python path
script_dir = Path(__file__).parent
sys.path.append(str(script_dir))

# Import the BranchSweeper
from scripts.branch_sweeper import BranchSweeper


def main():
    """Run the branch sweeper."""
    parser = argparse.ArgumentParser(description="Clean up stale branches in GitHub repositories")
    parser.add_argument("--dry-run", default="true", help="Run in dry-run mode (no actual deletions)")
    parser.add_argument("--weeks-threshold", default="4", help="Age threshold in weeks")
    parser.add_argument("--default-branch", default="", help="Default branch name")
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY", ""), 
                        help="Repository name (owner/repo)")
    
    args = parser.parse_args()
    
    # Convert arguments to appropriate types
    dry_run = args.dry_run.lower() == "true"
    
    try:
        weeks_threshold = int(args.weeks_threshold)
        if weeks_threshold <= 0:
            print("Error: weeks_threshold must be a positive number")
            return 1
    except ValueError:
        print("Error: weeks_threshold must be a positive number")
        return 1
        
    # Create and run the branch sweeper
    sweeper = BranchSweeper(
        dry_run=dry_run,
        weeks_threshold=weeks_threshold,
        default_branch=args.default_branch,
        protected_branches="",
        repo=args.repo,
        verbose=os.environ.get("DEBUG") == "true",
        test_mode=os.environ.get("GITHUB_TEST_MODE") == "true",
    )
    
    return sweeper.run()


if __name__ == "__main__":
    sys.exit(main())
