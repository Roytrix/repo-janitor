#!/usr/bin/env python3
# filepath: /home/roytrix/Documents/source-code/repo-janitor/branch-sweeper/tests/github-repo-tests/delete_github_test_repo.py

import argparse
import os
import subprocess
import sys
from pathlib import Path

# Add parent directories to sys.path
script_dir = Path(__file__).parent
project_root = script_dir.parent.parent.parent
sys.path.append(str(project_root / "branch-sweeper" / "scripts"))

# Import GitHub authentication helper
import github_auth


def run_command(cmd, capture_output=True):
    """Run a command and return the result."""
    try:
        result = subprocess.run(
            cmd,
            capture_output=capture_output,
            text=True,
            check=False
        )
        return result
    except Exception as e:
        print(f"Error executing command: {e}")
        class FakeResult:
            def __init__(self):
                self.returncode = 1
                self.stdout = ""
                self.stderr = str(e)
        return FakeResult()


def delete_github_repository(repo_name, repo_owner):
    """Delete a GitHub repository if it exists."""
    full_repo_name = f"{repo_owner}/{repo_name}"
    
    print(f"Checking if repository exists: {full_repo_name}")
    
    # Check if the repository exists
    check_result = run_command(["gh", "repo", "view", full_repo_name])
    
    if check_result.returncode != 0:
        print(f"Repository does not exist: {full_repo_name}")
        return True
    
    print(f"Repository exists: {full_repo_name}")
    print(f"Deleting repository: {full_repo_name}")
    
    # Delete the repository
    delete_result = run_command(["gh", "repo", "delete", full_repo_name, "--yes"], capture_output=False)
    
    if delete_result.returncode != 0:
        print(f"Error deleting repository: {full_repo_name}")
        return False
    
    print(f"Repository deleted successfully: {full_repo_name}")
    return True


def main():
    """Delete a GitHub test repository."""
    parser = argparse.ArgumentParser(description="Delete a GitHub test repository")
    parser.add_argument("repo_name", nargs="?", default="repo-janitor-testing", help="Repository name")
    parser.add_argument("repo_owner", nargs="?", default=os.environ.get("GITHUB_REPOSITORY_OWNER", ""), 
                        help="Repository owner (organization or user)")
    
    args = parser.parse_args()
    
    repo_name = args.repo_name
    repo_owner = args.repo_owner
    
    # If repo_owner is not set, try to get it from the current GitHub identity
    if not repo_owner:
        print("Trying to determine repository owner from current identity")
        user_result = run_command(["gh", "api", "user", "--jq", ".login"])
        if user_result.returncode == 0 and user_result.stdout:
            repo_owner = user_result.stdout.strip()
            print(f"Determined repository owner: {repo_owner}")
        else:
            print("Error: Could not determine repository owner. Please specify as the second argument.")
            return 1
    
    # Make sure we have GitHub authentication
    if not github_auth.check_github_auth():
        print("Error: GitHub authentication failed")
        return 1
    
    # Delete GitHub repository
    if not delete_github_repository(repo_name, repo_owner):
        return 1
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
