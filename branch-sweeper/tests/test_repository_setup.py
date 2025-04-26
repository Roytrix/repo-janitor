#!/usr/bin/env python3
# filepath: /home/roytrix/Documents/source-code/repo-janitor/branch-sweeper/tests/test_repository_setup.py

import os
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path


class TestRepositorySetup:
    """Set up a test Git repository with various branch scenarios for testing."""
    
    def __init__(self, repo_dir="./repo-test"):
        """Initialize the test repository setup."""
        self.repo_dir = Path(repo_dir)
        
        # Calculate dates relative to today
        self.current_date = datetime.now()
        self.weeks_5_ago = (self.current_date - timedelta(weeks=5)).strftime("%Y-%m-%dT%H:%M:%S")
        self.weeks_6_ago = (self.current_date - timedelta(weeks=6)).strftime("%Y-%m-%dT%H:%M:%S")
        self.weeks_8_ago = (self.current_date - timedelta(weeks=8)).strftime("%Y-%m-%dT%H:%M:%S")
        self.weeks_10_ago = (self.current_date - timedelta(weeks=10)).strftime("%Y-%m-%dT%H:%M:%S")
        self.days_15_ago = (self.current_date - timedelta(days=15)).strftime("%Y-%m-%dT%H:%M:%S")
        self.days_2_ago = (self.current_date - timedelta(days=2)).strftime("%Y-%m-%dT%H:%M:%S")
    
    def _run_command(self, cmd, cwd=None):
        """Run a command and return the result."""
        if cwd is None:
            cwd = self.repo_dir if self.repo_dir.exists() else "."
            
        try:
            result = subprocess.run(
                cmd,
                cwd=cwd,
                capture_output=True,
                text=True,
                check=True,
                shell=isinstance(cmd, str)
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            print(f"Error executing command: {e}")
            print(f"Command output: {e.stdout}")
            print(f"Command error: {e.stderr}")
            if "already exists" not in e.stderr and "not found" not in e.stderr:
                raise
            return ""
    
    def configure_git(self):
        """Configure Git user identity."""
        self._run_command(["git", "config", "--global", "user.name", "GitHub Actions"], cwd=".")
        self._run_command(["git", "config", "--global", "user.email", "actions@github.com"], cwd=".")
        
    def create_merged_stale_branch(self, branch_name, commit_date):
        """Create a merged branch that's older than the threshold (stale)."""
        self._run_command(["git", "checkout", "-b", branch_name])
        with open(self.repo_dir / f"{branch_name}.md", "w") as f:
            f.write(f"# {branch_name} feature\n")
        self._run_command(["git", "add", f"{branch_name}.md"])
        
        # Use environment variables to set the commit date
        env = os.environ.copy()
        env["GIT_COMMITTER_DATE"] = commit_date
        
        subprocess.run(
            ["git", "commit", "-m", f"Add {branch_name} feature", "--date", commit_date],
            cwd=self.repo_dir,
            env=env,
            check=True
        )
        
        self._run_command(["git", "checkout", "main"])
        self._run_command(["git", "merge", "--no-ff", branch_name, "-m", f"Merge branch '{branch_name}'"])
        
    def create_old_unmerged_branch(self, branch_name, commit_date):
        """Create a non-merged branch that's older than a month."""
        self._run_command(["git", "checkout", "-b", branch_name])
        with open(self.repo_dir / f"{branch_name}.md", "w") as f:
            f.write(f"# {branch_name} feature\n")
        self._run_command(["git", "add", f"{branch_name}.md"])
        
        # Use environment variables to set the commit date
        env = os.environ.copy()
        env["GIT_COMMITTER_DATE"] = commit_date
        
        subprocess.run(
            ["git", "commit", "-m", f"Add {branch_name} feature", "--date", commit_date],
            cwd=self.repo_dir,
            env=env,
            check=True
        )
        
        self._run_command(["git", "checkout", "main"])
        
    def create_pr_merged_branch(self, branch_name, commit_date):
        """Create a branch that's merged via PR-style merge commit."""
        self._run_command(["git", "checkout", "-b", branch_name])
        with open(self.repo_dir / f"{branch_name}.md", "w") as f:
            f.write(f"# {branch_name} feature\n")
        self._run_command(["git", "add", f"{branch_name}.md"])
        
        # Use environment variables to set the commit date
        env = os.environ.copy()
        env["GIT_COMMITTER_DATE"] = commit_date
        
        subprocess.run(
            ["git", "commit", "-m", f"Add {branch_name} feature", "--date", commit_date],
            cwd=self.repo_dir,
            env=env,
            check=True
        )
        
        self._run_command(["git", "checkout", "main"])
        self._run_command(["git", "merge", "--no-ff", branch_name, "-m", f"Merge pull request #123 from user/{branch_name}"])
        
    def create_recent_branch(self, branch_name, commit_date):
        """Create a recent unmerged branch that should be kept."""
        self._run_command(["git", "checkout", "-b", branch_name])
        with open(self.repo_dir / f"{branch_name}.md", "w") as f:
            f.write(f"# {branch_name} feature\n")
        self._run_command(["git", "add", f"{branch_name}.md"])
        
        # Use environment variables to set the commit date
        env = os.environ.copy()
        env["GIT_COMMITTER_DATE"] = commit_date
        
        subprocess.run(
            ["git", "commit", "-m", f"Add {branch_name} feature", "--date", commit_date],
            cwd=self.repo_dir,
            env=env,
            check=True
        )
        
        self._run_command(["git", "checkout", "main"])
    
    def setup(self):
        """Set up the test repository with various branch scenarios."""
        # Create test directory if it doesn't exist
        self.repo_dir.mkdir(parents=True, exist_ok=True)
        
        # Configure git user identity 
        self.configure_git()
        
        # Initialize the repository
        self._run_command(["git", "init"], cwd=self.repo_dir)
        
        # Create the initial content
        with open(self.repo_dir / "README.md", "w") as f:
            f.write("# Test Repository\n")
        
        self._run_command(["git", "add", "README.md"])
        self._run_command(["git", "commit", "-m", "Initial commit"])
        
        # Ensure we're on main branch
        self._run_command(["git", "checkout", "-b", "main"])
        try:
            self._run_command(["git", "branch", "-D", "master"])
        except:
            # It's okay if master doesn't exist
            pass
        
        # Create a first protected branch: develop
        self._run_command(["git", "checkout", "-b", "develop"])
        with open(self.repo_dir / "DEVELOP.md", "w") as f:
            f.write("# Development Branch\n")
        self._run_command(["git", "add", "DEVELOP.md"])
        self._run_command(["git", "commit", "-m", "Add develop documentation"])
        self._run_command(["git", "checkout", "main"])
        
        # Create another protected branch: production
        self._run_command(["git", "checkout", "-b", "production"])
        with open(self.repo_dir / "PRODUCTION.md", "w") as f:
            f.write("# Production Branch\n")
        self._run_command(["git", "add", "PRODUCTION.md"])
        self._run_command(["git", "commit", "-m", "Add production documentation"])
        self._run_command(["git", "checkout", "main"])
        
        # Create various branches with different dates
        self.create_merged_stale_branch("feature-old-merged", self.weeks_6_ago)
        self.create_old_unmerged_branch("feature-ancient-unmerged", self.weeks_10_ago)
        self.create_pr_merged_branch("feature-pr-merged", self.weeks_5_ago)
        self.create_recent_branch("feature-recent", self.days_2_ago)
        self.create_old_unmerged_branch("feature-unmerged-stale", self.weeks_8_ago)
        self.create_merged_stale_branch("bugfix-old-merged", self.weeks_6_ago)
        self.create_recent_branch("bugfix-recent", self.days_15_ago)
        
        print(f"Test repository successfully set up at {self.repo_dir}")
        
        # List all branches
        branches = self._run_command(["git", "branch"])
        print(f"Branches created: {branches}")
        
        return 0


def main():
    """Run the test repository setup."""
    setup = TestRepositorySetup()
    return setup.setup()


if __name__ == "__main__":
    sys.exit(main())
