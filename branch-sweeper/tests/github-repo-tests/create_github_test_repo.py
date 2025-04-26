#!/usr/bin/env python3
# filepath: /home/roytrix/Documents/source-code/repo-janitor/branch-sweeper/tests/github-repo-tests/create_github_test_repo.py

import argparse
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

# Add parent directories to sys.path
script_dir = Path(__file__).parent
project_root = script_dir.parent.parent.parent
sys.path.append(str(project_root / "branch-sweeper" / "scripts"))

# Import GitHub authentication helper
import github_auth


def log(message):
    """Log informational messages."""
    print(f"[INFO] {message}")


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


def delete_github_test_repo(repo_name, repo_owner):
    """Delete a GitHub test repository if it exists."""
    # Run the delete script
    delete_script = script_dir / "delete_github_test_repo.py"
    result = run_command([sys.executable, str(delete_script), repo_name, repo_owner], capture_output=False)
    return result.returncode == 0


def calculate_dates():
    """Calculate dates for test branches."""
    current_date = int(time.time())
    print(f"Current timestamp: {current_date} ({datetime.fromtimestamp(current_date).strftime('%Y-%m-%d')})")
    
    seconds_per_day = 86400
    seconds_per_week = seconds_per_day * 7
    
    # Calculate dates in the past
    dates = {
        "WEEKS_10_AGO": datetime.fromtimestamp(current_date - seconds_per_week * 10).strftime("%Y-%m-%d"),
        "WEEKS_8_AGO": datetime.fromtimestamp(current_date - seconds_per_week * 8).strftime("%Y-%m-%d"),
        "WEEKS_6_AGO": datetime.fromtimestamp(current_date - seconds_per_week * 6).strftime("%Y-%m-%d"),
        "WEEKS_5_AGO": datetime.fromtimestamp(current_date - seconds_per_week * 5).strftime("%Y-%m-%d"),
        "DAYS_2_AGO": datetime.fromtimestamp(current_date - seconds_per_day * 2).strftime("%Y-%m-%d"),
    }
    
    print("Date calculations:")
    for name, date in dates.items():
        print(f"  {name}: {date}")
        
    return dates


def verify_github_permissions(repo_owner):
    """Verify GitHub token permissions."""
    print("Verifying GitHub token permissions...")
    
    # Display authentication status
    auth_status = run_command(["gh", "auth", "status"], capture_output=True)
    print(auth_status.stdout)
    
    # Display information about auth context
    print("Authentication context:")
    operating_identity = github_auth.get_operating_identity()
    print(f"  User/app: {operating_identity}")
    
    token_type = "Unknown"
    if os.environ.get("GITHUB_TOKEN"):
        token_type = "GitHub Token"
    elif os.environ.get("GITHUB_APP_TOKEN"):
        token_type = "GitHub App Token"
    elif os.environ.get("GH_TOKEN"):
        token_type = "GH Token"
    print(f"  Token type: {token_type}")
    
    # Check if token has org admin permissions if needed
    gh_repo_owner = os.environ.get("GITHUB_REPOSITORY_OWNER", "")
    user_login_result = run_command(["gh", "api", "user", "--jq", ".login"])
    user_login = user_login_result.stdout.strip() if user_login_result.returncode == 0 else ""
    
    if repo_owner != gh_repo_owner and repo_owner != user_login:
        print(f"Testing if token has org admin permissions for {repo_owner}")
        org_perm_result = run_command(["gh", "api", f"orgs/{repo_owner}", "--jq", ".login"])
        
        if org_perm_result.returncode != 0:
            print(f"Warning: Token lacks permission to access organization {repo_owner}")
            print("Will attempt with current user's namespace instead")
            
            if user_login:
                repo_owner = user_login
                print(f"Updated repository owner: {repo_owner}")
            else:
                print("Error: Could not determine current user login")
                return None
    
    return repo_owner


def create_github_repository(repo_name, repo_owner):
    """Create a new GitHub repository."""
    print(f"Creating repository: {repo_owner}/{repo_name}")
    
    # Make sure the repository doesn't already exist
    delete_github_test_repo(repo_name, repo_owner)
    
    # Verify GitHub permissions
    verified_owner = verify_github_permissions(repo_owner)
    if not verified_owner:
        print("Error: Could not verify GitHub permissions")
        return False
    
    repo_owner = verified_owner
    full_repo_name = f"{repo_owner}/{repo_name}"
    print(f"Creating repository: {full_repo_name}")
    
    # Create the repository using gh cli
    create_result = run_command([
        "gh", "repo", "create", full_repo_name,
        "--private",
        "--description", "Test repository for branch-sweeper",
        "--confirm"
    ])
    
    if create_result.returncode != 0:
        print(f"Error creating repository: {create_result.stderr}")
        return False
    
    print(f"Repository created successfully: {full_repo_name}")
    return True


def clone_and_setup_repository(repo_name, repo_owner, dates):
    """Clone and set up the repository with test branches."""
    full_repo_name = f"{repo_owner}/{repo_name}"
    
    # Create a temporary directory for cloning
    temp_dir = Path("/tmp/repo-janitor-test")
    if temp_dir.exists():
        import shutil
        shutil.rmtree(temp_dir)
    temp_dir.mkdir(parents=True)
    
    # Clone the repository
    print(f"Cloning repository: {full_repo_name}")
    clone_result = run_command(["gh", "repo", "clone", full_repo_name, str(temp_dir)], capture_output=False)
    
    if clone_result.returncode != 0:
        print("Error cloning repository")
        return False
    
    # Set up Git identity
    run_command(["git", "config", "--global", "user.name", "GitHub Test Bot"], capture_output=False)
    run_command(["git", "config", "--global", "user.email", "test-bot@github.com"], capture_output=False)
    
    # Create initial commit
    with open(temp_dir / "README.md", "w") as f:
        f.write("# Test Repository\n\nThis is a test repository for branch-sweeper.\n")
    
    run_command(["git", "add", "README.md"], cwd=temp_dir, capture_output=False)
    run_command(["git", "commit", "-m", "Initial commit"], cwd=temp_dir, capture_output=False)
    
    # Create main branch
    run_command(["git", "branch", "-M", "main"], cwd=temp_dir, capture_output=False)
    
    # Push to remote
    run_command(["git", "push", "-u", "origin", "main"], cwd=temp_dir, capture_output=False)
    
    # Create protected branches
    for branch in ["develop", "production"]:
        run_command(["git", "checkout", "-b", branch], cwd=temp_dir, capture_output=False)
        with open(temp_dir / f"{branch.upper()}.md", "w") as f:
            f.write(f"# {branch.capitalize()} Branch\n\nThis is the {branch} branch.\n")
        run_command(["git", "add", f"{branch.upper()}.md"], cwd=temp_dir, capture_output=False)
        run_command(["git", "commit", "-m", f"Add {branch} documentation"], cwd=temp_dir, capture_output=False)
        run_command(["git", "push", "-u", "origin", branch], cwd=temp_dir, capture_output=False)
        run_command(["git", "checkout", "main"], cwd=temp_dir, capture_output=False)
    
    # Create test branches with specific dates
    
    # Helper function to create a branch with a specific date
    def create_branch(name, date, merge=False, pr_merge=False):
        run_command(["git", "checkout", "-b", name], cwd=temp_dir, capture_output=False)
        with open(temp_dir / f"{name}.md", "w") as f:
            f.write(f"# {name}\n\nThis is the {name} branch.\n")
        run_command(["git", "add", f"{name}.md"], cwd=temp_dir, capture_output=False)
        
        # Use environment variables to set the commit date
        env = os.environ.copy()
        env["GIT_COMMITTER_DATE"] = date
        env["GIT_AUTHOR_DATE"] = date
        
        subprocess.run(
            ["git", "commit", "-m", f"Add {name}", "--date", date],
            cwd=temp_dir,
            env=env,
            check=True
        )
        
        run_command(["git", "push", "-u", "origin", name], cwd=temp_dir, capture_output=False)
        
        if merge or pr_merge:
            run_command(["git", "checkout", "main"], cwd=temp_dir, capture_output=False)
            if pr_merge:
                run_command(["git", "merge", "--no-ff", name, "-m", f"Merge pull request #123 from {repo_owner}/{name}"], 
                           cwd=temp_dir, capture_output=False)
            else:
                run_command(["git", "merge", "--no-ff", name, "-m", f"Merge branch '{name}'"], 
                           cwd=temp_dir, capture_output=False)
            run_command(["git", "push", "origin", "main"], cwd=temp_dir, capture_output=False)
    
    # Create various branches with different dates
    create_branch("feature-old-merged", dates["WEEKS_6_AGO"], merge=True)
    create_branch("feature-ancient-unmerged", dates["WEEKS_10_AGO"])
    create_branch("feature-pr-merged", dates["WEEKS_5_AGO"], pr_merge=True)
    create_branch("feature-recent", dates["DAYS_2_AGO"])
    create_branch("feature-unmerged-stale", dates["WEEKS_8_AGO"])
    create_branch("bugfix-old-merged", dates["WEEKS_6_AGO"], merge=True)
    create_branch("bugfix-recent", dates["DAYS_2_AGO"])
    
    # Set protected branches
    for branch in ["main", "develop", "production"]:
        run_command([
            "gh", "api", f"repos/{full_repo_name}/branches/{branch}/protection",
            "--method", "PUT",
            "-f", "required_status_checks=null",
            "-f", "enforce_admins=true",
            "-f", "required_pull_request_reviews=null",
            "-f", "restrictions=null"
        ])
    
    print(f"Repository setup completed: {full_repo_name}")
    return True


def main():
    """Create a GitHub test repository for branch-sweeper testing."""
    parser = argparse.ArgumentParser(description="Create a GitHub test repository for branch-sweeper testing")
    parser.add_argument("repo_name", nargs="?", default="repo-janitor-testing", help="Repository name")
    parser.add_argument("repo_owner", nargs="?", default=os.environ.get("GITHUB_REPOSITORY_OWNER", ""), 
                        help="Repository owner (organization or user)")
    
    args = parser.parse_args()
    
    repo_name = args.repo_name
    repo_owner = args.repo_owner
    
    # If repo_owner is not set, try to get it from the current GitHub identity
    if not repo_owner:
        log("Trying to determine repository owner from current identity")
        user_result = run_command(["gh", "api", "user", "--jq", ".login"])
        if user_result.returncode == 0 and user_result.stdout:
            repo_owner = user_result.stdout.strip()
            log(f"Determined repository owner: {repo_owner}")
        else:
            print("Error: Could not determine repository owner. Please specify as the second argument.")
            return 1
    
    # Make sure we have GitHub authentication
    if not github_auth.check_github_auth():
        print("Error: GitHub authentication failed")
        return 1
    
    # Calculate dates for branches
    print("-------------------------------------------------------")
    print("STEP: Calculating dates for test branches")
    print("-------------------------------------------------------")
    dates = calculate_dates()
    
    # Create GitHub repository
    print("-------------------------------------------------------")
    print(f"STEP: Creating new repository: {repo_owner}/{repo_name}")
    print("-------------------------------------------------------")
    if not create_github_repository(repo_name, repo_owner):
        return 1
    
    # Clone and set up the repository
    print("-------------------------------------------------------")
    print("STEP: Setting up repository with test branches")
    print("-------------------------------------------------------")
    if not clone_and_setup_repository(repo_name, repo_owner, dates):
        return 1
    
    print("-------------------------------------------------------")
    print(f"Repository created and configured: {repo_owner}/{repo_name}")
    print("IMPORTANT: Don't forget to delete this repository when done testing!")
    print("-------------------------------------------------------")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
