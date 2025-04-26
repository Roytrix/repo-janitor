#!/usr/bin/env python3
# filepath: /home/roytrix/Documents/source-code/repo-janitor/branch-sweeper/tests/github-repo-tests/test_github_sweeping_repo.py

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

# Add parent directories to sys.path
script_dir = Path(__file__).parent
project_root = script_dir.parent.parent.parent
sys.path.append(str(project_root / "branch-sweeper" / "scripts"))

# Import GitHub authentication helper and branch sweeper
import github_auth
from branch_sweeper import BranchSweeper


class TerminalColors:
    """ANSI color codes for terminal output."""
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    NC = '\033[0m'  # No Color


def run_command(cmd, cwd=None, capture_output=True):
    """Run a command and return the result."""
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
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


def ensure_repo_exists(repo_name, repo_owner):
    """Ensure that the test repository exists."""
    full_repo_name = f"{repo_owner}/{repo_name}"
    
    # Check if the repository exists
    check_result = run_command(["gh", "repo", "view", full_repo_name])
    
    if check_result.returncode != 0:
        print(f"Repository does not exist: {full_repo_name}")
        print("Creating the repository...")
        
        # Create the repository
        create_script = script_dir / "create_github_test_repo.py"
        create_result = run_command([sys.executable, str(create_script), repo_name, repo_owner], capture_output=False)
        
        if create_result.returncode != 0:
            print(f"Error creating repository: {full_repo_name}")
            return False
    
    print(f"Repository exists: {full_repo_name}")
    return True


def clone_repository(repo_name, repo_owner, work_dir):
    """Clone the repository for testing."""
    full_repo_name = f"{repo_owner}/{repo_name}"
    
    # Create working directory if it doesn't exist
    work_dir.mkdir(parents=True, exist_ok=True)
    
    # Clone the repository
    print(f"Cloning repository: {full_repo_name}")
    clone_result = run_command(["gh", "repo", "clone", full_repo_name, str(work_dir)], capture_output=False)
    
    if clone_result.returncode != 0:
        print(f"Error cloning repository: {full_repo_name}")
        return False
    
    print(f"Repository cloned successfully: {full_repo_name}")
    return True


def get_branches(work_dir):
    """Get a list of all branches in the repository."""
    # Fetch all branches
    run_command(["git", "fetch", "--all"], cwd=work_dir, capture_output=False)
    
    # Get all branches
    branch_result = run_command(["git", "branch", "-a"], cwd=work_dir)
    
    if branch_result.returncode != 0:
        print(f"Error getting branches: {branch_result.stderr}")
        return []
    
    branches = []
    for line in branch_result.stdout.splitlines():
        line = line.strip()
        if line.startswith("remotes/origin/") and not line.startswith("remotes/origin/HEAD"):
            branch = line.replace("remotes/origin/", "")
            branches.append(branch)
    
    return branches


def get_protected_branches(repo_name, repo_owner):
    """Get a list of protected branches in the repository."""
    full_repo_name = f"{repo_owner}/{repo_name}"
    
    # Get protected branches
    result = run_command(["gh", "api", f"repos/{full_repo_name}/branches", "--jq", '.[] | select(.protected) | .name'])
    
    if result.returncode != 0:
        print(f"Error getting protected branches: {result.stderr}")
        return []
    
    return result.stdout.strip().split("\n") if result.stdout.strip() else []


def run_branch_sweeper(repo_name, repo_owner, work_dir, dry_run=False, weeks_threshold=4):
    """Run the branch sweeper on the repository."""
    print(f"{TerminalColors.YELLOW}Running branch sweeper on repository: {repo_owner}/{repo_name}{TerminalColors.NC}")
    print(f"Dry run: {dry_run}")
    print(f"Weeks threshold: {weeks_threshold}")
    
    # Get protected branches
    protected_branches = get_protected_branches(repo_name, repo_owner)
    protected_branches_str = " ".join(protected_branches)
    print(f"Protected branches: {protected_branches_str}")
    
    # Get all branches before running the sweeper
    print(f"{TerminalColors.YELLOW}Branches before running sweeper:{TerminalColors.NC}")
    before_branches = get_branches(work_dir)
    for branch in before_branches:
        print(f"  {branch}")
    
    # Run branch sweeper
    sweeper = BranchSweeper(
        dry_run=dry_run,
        weeks_threshold=weeks_threshold,
        default_branch="main",
        protected_branches=protected_branches_str,
        repo=f"{repo_owner}/{repo_name}",
        verbose=True
    )
    
    result = sweeper.run()
    
    if result != 0:
        print(f"{TerminalColors.RED}Branch sweeper failed with code {result}{TerminalColors.NC}")
        return False
    
    # Get all branches after running the sweeper
    print(f"{TerminalColors.YELLOW}Branches after running sweeper:{TerminalColors.NC}")
    after_branches = get_branches(work_dir)
    for branch in after_branches:
        print(f"  {branch}")
    
    # Check if any branches were deleted
    deleted_branches = set(before_branches) - set(after_branches)
    print(f"{TerminalColors.YELLOW}Deleted branches:{TerminalColors.NC}")
    for branch in deleted_branches:
        print(f"  {branch}")
    
    # If this is not a dry run, we expect to see some branches deleted
    if not dry_run and not deleted_branches:
        print(f"{TerminalColors.RED}No branches were deleted!{TerminalColors.NC}")
        return False
    
    # If this is a dry run, we don't expect to see any branches deleted
    if dry_run and deleted_branches:
        print(f"{TerminalColors.RED}Branches were deleted in dry run mode!{TerminalColors.NC}")
        return False
    
    print(f"{TerminalColors.GREEN}Branch sweeper ran successfully{TerminalColors.NC}")
    return True


def create_summary_report(repo_name, repo_owner, test_results):
    """Create a summary report of the test results."""
    with open("github-test-summary.md", "w") as f:
        f.write("# GitHub Repository Branch Sweeper Test Results\n\n")
        f.write(f"Repository: {repo_owner}/{repo_name}\n\n")
        f.write("## Test Results\n\n")
        
        for test_name, success in test_results.items():
            status = "✅ Passed" if success else "❌ Failed"
            f.write(f"- {test_name}: {status}\n")
        
        f.write("\n")
        
        passed = sum(1 for success in test_results.values() if success)
        total = len(test_results)
        f.write(f"**Summary**: {passed}/{total} tests passed\n")
    
    print(f"{TerminalColors.YELLOW}Summary report created: github-test-summary.md{TerminalColors.NC}")
    
    # Display report
    with open("github-test-summary.md", "r") as f:
        print(f.read())


def run_github_tests(repo_name, repo_owner):
    """Run tests against a GitHub repository."""
    # Make sure GitHub authentication is set up
    if not github_auth.check_github_auth():
        print(f"{TerminalColors.RED}GitHub authentication failed{TerminalColors.NC}")
        return 1
    
    # Make sure the repository exists
    if not ensure_repo_exists(repo_name, repo_owner):
        return 1
    
    # Create a working directory for the tests
    work_dir = Path("/tmp/repo-janitor-github-test")
    if work_dir.exists():
        import shutil
        shutil.rmtree(work_dir)
    
    # Clone the repository
    if not clone_repository(repo_name, repo_owner, work_dir):
        return 1
    
    # Run tests
    test_results = {}
    
    # Test 1: Dry run mode
    print(f"{TerminalColors.YELLOW}========================================{TerminalColors.NC}")
    print(f"{TerminalColors.YELLOW}Test 1: Dry Run Mode{TerminalColors.NC}")
    print(f"{TerminalColors.YELLOW}========================================{TerminalColors.NC}")
    test_results["Dry Run Mode"] = run_branch_sweeper(repo_name, repo_owner, work_dir, dry_run=True, weeks_threshold=4)
    
    # Test 2: Normal mode (actual deletions)
    print(f"{TerminalColors.YELLOW}========================================{TerminalColors.NC}")
    print(f"{TerminalColors.YELLOW}Test 2: Normal Mode (Actual Deletions){TerminalColors.NC}")
    print(f"{TerminalColors.YELLOW}========================================{TerminalColors.NC}")
    test_results["Normal Mode"] = run_branch_sweeper(repo_name, repo_owner, work_dir, dry_run=False, weeks_threshold=4)
    
    # Test 3: Short age threshold
    print(f"{TerminalColors.YELLOW}========================================{TerminalColors.NC}")
    print(f"{TerminalColors.YELLOW}Test 3: Short Age Threshold (1 week){TerminalColors.NC}")
    print(f"{TerminalColors.YELLOW}========================================{TerminalColors.NC}")
    test_results["Short Age Threshold"] = run_branch_sweeper(repo_name, repo_owner, work_dir, dry_run=True, weeks_threshold=1)
    
    # Create summary report
    create_summary_report(repo_name, repo_owner, test_results)
    
    # Return success if all tests passed
    return 0 if all(test_results.values()) else 1


def main():
    """Run tests against a GitHub repository."""
    parser = argparse.ArgumentParser(description="Test branch sweeper against a GitHub repository")
    parser.add_argument("--repo-name", default="repo-janitor-testing", help="Repository name")
    parser.add_argument("--repo-owner", default=os.environ.get("GITHUB_REPOSITORY_OWNER", ""), 
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
            print("Error: Could not determine repository owner. Please specify with --repo-owner.")
            return 1
    
    return run_github_tests(repo_name, repo_owner)


if __name__ == "__main__":
    sys.exit(main())
