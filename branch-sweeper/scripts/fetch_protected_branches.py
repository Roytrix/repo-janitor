#!/usr/bin/env python3
# filepath: /home/roytrix/Documents/source-code/repo-janitor/branch-sweeper/scripts/fetch_protected_branches.py

import argparse
import json
import os
import subprocess
import sys


def fetch_protected_branches(repo: str) -> str:
    """Fetch protected branches from GitHub repository."""
    # Run gh api command to get branches
    cmd = ["gh", "api", f"repos/{repo}/branches", "--jq", '.[] | select(.protected) | .name']
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"Error fetching protected branches: {result.stderr}")
        return ""
        
    # Convert newline-separated list to space-separated
    protected_branches = " ".join(result.stdout.strip().split("\n"))
    print(f"Protected branches: {protected_branches}")
    
    # Set GitHub environment variable if running in GitHub Actions
    if "GITHUB_ENV" in os.environ:
        github_env = os.environ["GITHUB_ENV"]
        with open(github_env, "a") as f:
            f.write(f"PROTECTED_BRANCHES={protected_branches}\n")
            
    return protected_branches


def main():
    """Parse arguments and run the fetcher."""
    parser = argparse.ArgumentParser(description="Fetch protected branches from GitHub repository")
    parser.add_argument("repo", help="Repository name (owner/repo)")
    
    args = parser.parse_args()
    return 0 if fetch_protected_branches(args.repo) else 1


if __name__ == "__main__":
    sys.exit(main())
