#!/usr/bin/env python3
# filepath: /home/roytrix/Documents/source-code/repo-janitor/branch-sweeper/scripts/set_variables.py

import argparse
import os
import sys


def set_variables(dry_run: str, weeks_threshold: str, default_branch: str, fallback_default_branch: str) -> int:
    """Set GitHub Actions environment variables."""
    github_env = os.environ.get("GITHUB_ENV")
    
    if not github_env:
        print("Warning: GITHUB_ENV is not set. Not running in GitHub Actions environment?")
    else:
        with open(github_env, "a") as f:
            f.write(f"DRY_RUN={dry_run}\n")
            f.write(f"WEEKS_THRESHOLD={weeks_threshold}\n")
            
    # Determine default branch
    effective_default_branch = default_branch if default_branch else fallback_default_branch
    
    if github_env:
        with open(github_env, "a") as f:
            f.write(f"DEFAULT_BRANCH={effective_default_branch}\n")
            
    # Print variables for debugging
    print(f"Running with weeks threshold: {weeks_threshold}")
    print(f"Dry run mode: {dry_run}")
    print(f"Default branch: {effective_default_branch}")
    
    return 0


def main():
    """Parse arguments and set variables."""
    parser = argparse.ArgumentParser(description="Set variables for branch sweeper")
    parser.add_argument("dry_run", help="Run in dry-run mode (true/false)")
    parser.add_argument("weeks_threshold", help="Age threshold in weeks")
    parser.add_argument("default_branch", help="Default branch name")
    parser.add_argument("fallback_default_branch", help="Fallback default branch name")
    
    args = parser.parse_args()
    
    return set_variables(
        args.dry_run,
        args.weeks_threshold,
        args.default_branch,
        args.fallback_default_branch
    )


if __name__ == "__main__":
    sys.exit(main())
