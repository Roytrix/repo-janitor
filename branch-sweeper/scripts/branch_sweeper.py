#!/usr/bin/env python3
# filepath: /home/roytrix/Documents/source-code/repo-janitor/branch-sweeper/scripts/branch_sweeper.py

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple, Union


class BranchSweeper:
    """
    BranchSweeper: A Python class for cleaning up old and stale Git branches in GitHub repositories.
    This is a Python port of the original Bash sweeping.sh script.
    """

    def __init__(
        self,
        dry_run: bool = False,
        weeks_threshold: int = 2,
        default_branch: str = "",
        protected_branches: str = "",
        repo: str = "",
        verbose: bool = False,
        test_mode: bool = False,
    ):
        """Initialize the BranchSweeper with configuration parameters."""
        self.dry_run = dry_run
        self.weeks_threshold = weeks_threshold
        self.repo = repo
        self.verbose = verbose or os.environ.get("DEBUG") == "true"
        self.test_mode = test_mode or os.environ.get("GITHUB_TEST_MODE") == "true"
        
        # Calculate date thresholds
        self.current_date = int(time.time())
        self.cutoff_date = int(
            (datetime.now() - timedelta(weeks=weeks_threshold)).timestamp()
        )
        self.month_cutoff_date = int(
            (datetime.now() - timedelta(days=30)).timestamp()
        )
        
        # Set default branch if not provided
        self.default_branch = default_branch
        if not self.default_branch:
            self.default_branch = self._get_default_branch()
            
        # Set protected branches
        self.protected_branches = set(protected_branches.split() if protected_branches else [])
        if self.default_branch not in self.protected_branches:
            self.protected_branches.add(self.default_branch)
            
        # Branches to check for merge status (includes default branch and all protected branches)
        self.branches_to_check = self.protected_branches.copy()
        
        # Arrays to track results
        self.deleted_branches = []
        self.skipped_branches = []
        self.not_merged_branches = []
        self.stale_unmerged_branches = []

    def _run_command(self, cmd: List[str], capture_output: bool = True) -> subprocess.CompletedProcess:
        """Run a shell command and return the result."""
        if self.verbose:
            print(f"DEBUG: Running command: {' '.join(cmd)}")
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=capture_output,
                text=True,
                check=False  # We'll handle errors manually
            )
            return result
        except Exception as e:
            print(f"Error executing command: {e}")
            # Create a fake result object for error handling
            class FakeResult:
                def __init__(self):
                    self.returncode = 1
                    self.stdout = ""
                    self.stderr = str(e)
            return FakeResult()

    def _get_default_branch(self) -> str:
        """Determine the default branch of the repository."""
        cmd = ["git", "remote", "show", "origin"]
        result = self._run_command(cmd)
        
        if result.returncode != 0:
            print(f"Error getting default branch: {result.stderr}")
            return "main"  # Fallback to 'main' if we can't determine
            
        # Extract the default branch from the output
        default_branch = "main"  # Default fallback
        for line in result.stdout.splitlines():
            if "HEAD branch" in line:
                default_branch = line.split(":")[-1].strip()
                break
                
        return default_branch

    def _configure_git(self) -> None:
        """Configure Git with the GitHub Actions Bot identity."""
        self._run_command(["git", "config", "--global", "user.name", "GitHub Actions Bot"])
        self._run_command(["git", "config", "--global", "user.email", "actions@github.com"])

    def _branch_exists(self, branch_name: str) -> bool:
        """Check if a branch exists in the remote repository."""
        cmd = ["git", "ls-remote", "--exit-code", "--heads", "origin", branch_name]
        result = self._run_command(cmd, capture_output=True)
        return result.returncode == 0

    def _fetch_all_branches(self) -> None:
        """Fetch all branches from the remote repository."""
        print("Fetching all branches...")
        self._run_command(["git", "fetch", "--all"])

    def _get_branch_info(self) -> Dict[str, Dict[str, Union[str, int, bool]]]:
        """Get information about all remote branches."""
        cmd = ["git", "for-each-ref", "--format='%(refname:short) %(committerdate:unix)'", "refs/remotes/origin/"]
        result = self._run_command(cmd)
        
        if result.returncode != 0:
            print(f"Error getting branch info: {result.stderr}")
            return {}
            
        branch_info = {}
        
        for line in result.stdout.splitlines():
            if not line or line.isspace():
                continue
                
            # Parse each line (format: 'origin/branch_name timestamp')
            line = line.strip("'")
            parts = line.split()
            
            if not parts or len(parts) < 2:
                continue
                
            ref_name = parts[0]
            
            # Skip non-branch references
            if ref_name == "origin" or not ref_name.startswith("origin/"):
                if self.verbose:
                    print(f"Skipping non-branch reference: {ref_name}")
                continue
                
            branch_name = ref_name[len("origin/"):]
            
            # Skip empty branch names and origin/HEAD
            if not branch_name or branch_name == "HEAD":
                continue
                
            try:
                commit_date = int(parts[1])
            except (ValueError, IndexError):
                print(f"Error parsing commit date for {branch_name}, skipping")
                continue
                
            # Calculate branch age as a human-readable date string
            branch_age = datetime.fromtimestamp(commit_date).strftime('%Y-%m-%d')
            
            # Store branch information
            branch_info[branch_name] = {
                "ref_name": ref_name,
                "commit_date": commit_date,
                "branch_age": branch_age,
                "is_merged": False,  # Will be determined later
            }
            
        return branch_info

    def _check_if_branch_is_merged(self, branch_name: str) -> bool:
        """Check if a branch is merged into any protected branch."""
        if self.verbose:
            print(f"DEBUG: Looking for merge evidence for {branch_name}")
            
        # First check for merged PRs using GitHub CLI
        if not self.test_mode:
            cmd = ["gh", "pr", "list", "--head", branch_name, "--state", "merged", "--json", "number,title,mergedAt", "--limit", "1"]
            result = self._run_command(cmd)
            
            if result.returncode == 0 and result.stdout.strip() and result.stdout.strip() != "[]":
                try:
                    pr_info = json.loads(result.stdout)
                    if pr_info and len(pr_info) > 0:
                        pr_number = pr_info[0].get("number", "unknown")
                        pr_title = pr_info[0].get("title", "unknown")
                        pr_merged_at = pr_info[0].get("mergedAt", "unknown")
                        print(f"Branch {branch_name} was merged via PR #{pr_number}: {pr_title} (merged at {pr_merged_at})")
                        return True
                except json.JSONDecodeError:
                    print(f"Error parsing PR info for {branch_name}")
        
        # Check if branch is fully merged into any protected branch using git merge-base
        for protected in self.branches_to_check:
            if self.verbose:
                print(f"DEBUG: Checking if {branch_name} is fully merged into {protected}")
                
            # Get branch tip commit
            cmd = ["git", "rev-parse", f"origin/{branch_name}"]
            branch_tip_result = self._run_command(cmd)
            
            if branch_tip_result.returncode != 0 or not branch_tip_result.stdout:
                continue
                
            branch_tip = branch_tip_result.stdout.strip()
            
            # Get merge base
            cmd = ["git", "merge-base", f"origin/{branch_name}", f"origin/{protected}"]
            merge_base_result = self._run_command(cmd)
            
            if merge_base_result.returncode == 0 and merge_base_result.stdout:
                merge_base = merge_base_result.stdout.strip()
                
                if merge_base == branch_tip:
                    print(f"Branch {branch_name} is fully merged into protected branch {protected} (fully contained)")
                    return True
                    
        # Additional checks for merge commits in protected branches
        for protected in self.branches_to_check:
            # Check for merge commit messages
            merge_pattern = f"Merge.*{branch_name}|Merge.*branch.*{branch_name}|Merge.*pull.*request.*{branch_name}|{branch_name}.*into"
            cmd = ["git", "log", f"origin/{protected}", f"--grep={merge_pattern}", "-n", "1", "--oneline"]
            merge_result = self._run_command(cmd)
            
            if merge_result.returncode == 0 and merge_result.stdout:
                print(f"Branch {branch_name} appears to be merged into {protected} based on commit messages")
                return True
                
            # Check using git branch --merged
            cmd = ["git", "branch", "-r", "--merged", f"origin/{protected}"]
            merged_result = self._run_command(cmd)
            
            if merged_result.returncode == 0 and f"origin/{branch_name}" in merged_result.stdout:
                print(f"Branch {branch_name} is merged into {protected} according to git branch --merged")
                return True
                
        return False

    def _delete_branch(self, branch_name: str, branch_age: str, reason: str) -> bool:
        """Delete a branch and verify the deletion."""
        print(f"Attempting to delete branch: {branch_name} ({reason}: {branch_age})")
        
        # Check if branch exists
        existed_before = self._branch_exists(branch_name)
        
        if self.verbose:
            print(f"DEBUG: Checking branch: {branch_name}")
            print(f"DEBUG: Last commit date: {branch_age}")
            print(f"DEBUG: Cutoff date: {datetime.fromtimestamp(self.cutoff_date).strftime('%Y-%m-%d')}")
            
        # If this is a dry run, just log what would happen
        if self.dry_run:
            print(f"[DRY RUN] Would delete branch: {branch_name} ({reason}: {branch_age}) - not actually deleting in dry run mode")
            self.deleted_branches.append(f"{branch_name} ({reason}: {branch_age}) - [NOT ACTUALLY DELETED - DRY RUN]")
            return True
            
        # If the branch no longer exists, mark as already deleted
        if not existed_before:
            print(f"Branch {branch_name} doesn't exist anymore, marking as already deleted")
            self.deleted_branches.append(f"{branch_name} ({reason}: {branch_age}) - [ALREADY DELETED]")
            return True
            
        # Attempt to delete the branch
        cmd = ["git", "push", "origin", "--delete", branch_name]
        result = self._run_command(cmd)
        
        if result.returncode != 0:
            print(f"::warning::Initial deletion command failed for branch: {branch_name}")
            
        # Verify deletion with polling
        max_attempts = 5
        for attempt in range(1, max_attempts + 1):
            print(f"Verifying deletion (attempt {attempt}/{max_attempts})...")
            
            # Fetch with prune to update local refs
            self._run_command(["git", "fetch", "origin", "--prune"], capture_output=not self.verbose)
            
            if not self._branch_exists(branch_name):
                print(f"Successfully deleted branch: {branch_name}")
                self.deleted_branches.append(f"{branch_name} ({reason}: {branch_age})")
                return True
                
            # If this is the last attempt, don't wait
            if attempt == max_attempts:
                break
                
            # Exponential backoff: 1s, 2s, 4s, 8s
            wait_time = 2 ** (attempt - 1)
            print(f"Branch still exists, waiting {wait_time}s before retry...")
            time.sleep(wait_time)
            
        print(f"::warning::Failed to delete branch after {max_attempts} attempts: {branch_name}")
        self.skipped_branches.append(f"{branch_name} (deletion failed after {max_attempts} attempts)")
        return False

    def _process_branches(self) -> None:
        """Process all branches and delete the stale ones."""
        # Get information about all branches
        branch_info = self._get_branch_info()
        
        if self.verbose:
            print(f"Found {len(branch_info)} branches to process")
            
        for branch_name, info in branch_info.items():
            if self.verbose:
                print(f"DEBUG: Processing ref={info['ref_name']}, branch={branch_name}")
                
            # Skip protected branches
            if branch_name in self.protected_branches:
                print(f"Skipping protected branch: {branch_name}")
                self.skipped_branches.append(f"{branch_name} (protected)")
                continue
                
            # Check if branch is merged
            info["is_merged"] = self._check_if_branch_is_merged(branch_name)
            
            branch_age = info["branch_age"]
            commit_date = info["commit_date"]
            
            if info["is_merged"]:
                # Branch is properly merged, check if it's stale
                if commit_date < self.cutoff_date:
                    self._delete_branch(branch_name, branch_age, "merged & stale")
                else:
                    print(f"Branch is merged but not stale yet: {branch_name} (last activity: {branch_age})")
                    self.skipped_branches.append(f"{branch_name} (merged but not stale)")
            else:
                # Branch is not merged
                self.not_merged_branches.append(branch_name)
                print(f"Branch is not merged: {branch_name}")
                
                # Check if it's very old (older than a month)
                if commit_date < self.month_cutoff_date:
                    self._delete_branch(branch_name, branch_age, "older than a month")
                elif commit_date < self.cutoff_date:
                    # It's stale but not old enough for auto-deletion
                    self.stale_unmerged_branches.append(f"{branch_name} (last activity: {branch_age})")

    def _process_test_mode(self) -> None:
        """Process branches in test mode without using GitHub API."""
        print("Processing branches in test mode")
        
        # Create a summary file
        summary_file = "summary.md"
        with open(summary_file, "w") as f:
            f.write("# Branch Cleanup Summary\n")
            f.write(f"Generated on: {datetime.now()}\n\n")
            f.write("## Configuration\n")
            f.write(f"- Dry run: {self.dry_run}\n")
            f.write(f"- Weeks threshold: {self.weeks_threshold}\n")
            f.write(f"- Default branch: {self.default_branch}\n")
            f.write(f"- Protected branches: {' '.join(self.protected_branches)}\n\n")
            f.write("## Results\n")
            
        # Get local branches (excluding default branch)
        cmd = ["git", "branch"]
        result = self._run_command(cmd)
        
        if result.returncode != 0:
            print(f"Error getting branches: {result.stderr}")
            return
            
        for line in result.stdout.splitlines():
            branch = line.strip()
            
            # Skip current branch indicator and default branch
            if branch.startswith("*") or branch == self.default_branch:
                branch = branch[2:] if branch.startswith("* ") else branch
                if branch == self.default_branch:
                    continue
                    
            if self.verbose:
                print(f"DEBUG: Processing branch {branch}")
                
            # Skip protected branches
            if branch in self.protected_branches:
                print(f"Branch {branch} is protected, skipping")
                with open(summary_file, "a") as f:
                    f.write(f"- {branch}: Protected (skipped)\n")
                continue
                
            # Get last commit date
            cmd = ["git", "log", "-1", "--format=%ct", branch]
            date_result = self._run_command(cmd)
            
            if date_result.returncode != 0 or not date_result.stdout:
                print(f"Error getting commit date for {branch}, skipping")
                continue
                
            commit_date = int(date_result.stdout.strip())
            branch_age = self.current_date - commit_date
            branch_age_days = branch_age // 86400  # Convert seconds to days
            
            # Check if branch is merged
            cmd = ["git", "branch", "--merged", self.default_branch]
            merged_result = self._run_command(cmd)
            branch_is_merged = branch in merged_result.stdout if merged_result.returncode == 0 else False
            
            delete_reason = ""
            should_delete = False
            
            # Check deletion criteria
            if branch_is_merged and commit_date < self.cutoff_date:
                delete_reason = f"Merged and older than {self.weeks_threshold} weeks"
                should_delete = True
            elif not branch_is_merged and commit_date < self.month_cutoff_date:
                delete_reason = "Unmerged but older than 1 month"
                should_delete = True
                
            if should_delete:
                if self.dry_run:
                    print(f"Would delete branch {branch}: {delete_reason} (dry run)")
                    with open(summary_file, "a") as f:
                        f.write(f"- {branch}: {delete_reason} (would be deleted - dry run)\n")
                else:
                    print(f"Deleting branch {branch}: {delete_reason}")
                    with open(summary_file, "a") as f:
                        f.write(f"- {branch}: {delete_reason} (deleted)\n")
                    # Delete the branch
                    self._run_command(["git", "branch", "-D", branch])
                    self.deleted_branches.append(branch)
            else:
                print(f"Keeping branch {branch}: Age {branch_age_days} days, Merged: {branch_is_merged}")
                with open(summary_file, "a") as f:
                    f.write(f"- {branch}: Keeping (Age: {branch_age_days} days, Merged: {branch_is_merged})\n")
                    
        # Write summary footer
        with open(summary_file, "a") as f:
            f.write("\n## Summary\n")
            if self.dry_run:
                f.write(f"Dry run completed. Would have deleted {len(self.deleted_branches)} branches.\n")
            else:
                f.write(f"Deleted {len(self.deleted_branches)} branches.\n")

    def _create_summary_report(self) -> None:
        """Create a Markdown summary report of the branch cleanup."""
        with open("summary.md", "w") as f:
            f.write("## Branch Cleanup Summary\n")
            
            # Mode
            if self.dry_run:
                f.write("- Mode: Dry Run\n")
            else:
                f.write("- Mode: Actual Deletion\n")
                
            # Configuration details
            cutoff_date_str = datetime.fromtimestamp(self.cutoff_date).strftime('%Y-%m-%d')
            f.write(f"- Threshold: {self.weeks_threshold} weeks (before {cutoff_date_str})\n")
            f.write(f"- Default branch: {self.default_branch}\n")
            f.write(f"- Protected branches: {' '.join(self.protected_branches)}\n\n")
            
            # Deleted branches
            f.write("### Deleted Branches\n")
            if not self.deleted_branches:
                f.write("- No branches deleted\n")
            else:
                for branch in self.deleted_branches:
                    f.write(f"- {branch}\n")
            f.write("\n")
            
            # Skipped branches
            f.write("### Skipped Branches\n")
            if not self.skipped_branches:
                f.write("- No branches skipped\n")
            else:
                for branch in self.skipped_branches:
                    f.write(f"- {branch}\n")
            f.write("\n")
            
            # Stale unmerged branches
            if self.stale_unmerged_branches:
                f.write("### Stale Unmerged Branches\n")
                for branch in self.stale_unmerged_branches:
                    f.write(f"- {branch}\n")
                f.write("\n")

    def _set_github_outputs(self) -> None:
        """Set GitHub Actions outputs for use in subsequent steps."""
        # Check if we're running in GitHub Actions
        github_output = os.environ.get("GITHUB_OUTPUT")
        if github_output:
            with open(github_output, "a") as f:
                f.write(f"deleted_count={len(self.deleted_branches)}\n")

    def run(self) -> int:
        """Run the branch sweeper process."""
        print(f"Running BranchSweeper with: dry_run={self.dry_run}, weeks_threshold={self.weeks_threshold}")
        print(f"Default branch: {self.default_branch}")
        print(f"Protected branches: {' '.join(self.protected_branches)}")
        
        # Calculate and print date thresholds
        cutoff_date_str = datetime.fromtimestamp(self.cutoff_date).strftime('%Y-%m-%d')
        month_cutoff_date_str = datetime.fromtimestamp(self.month_cutoff_date).strftime('%Y-%m-%d')
        
        print(f"Deleting branches merged before: {cutoff_date_str}")
        print(f"Deleting branches older than a month: {month_cutoff_date_str}")
        
        # Configure git
        self._configure_git()
        
        # Fetch branches
        self._fetch_all_branches()
        
        # Process branches based on mode
        if self.test_mode:
            self._process_test_mode()
        else:
            self._process_branches()
            
        # Create summary report
        self._create_summary_report()
        
        # Set GitHub outputs
        self._set_github_outputs()
        
        # Print completion message
        print(f"Branch cleanup completed. Deleted {len(self.deleted_branches)} branches.")
        return 0


def main():
    """Parse command-line arguments and run the branch sweeper."""
    parser = argparse.ArgumentParser(description="Clean up stale branches in GitHub repositories")
    parser.add_argument("dry_run", help="Run in dry-run mode (no actual deletions)")
    parser.add_argument("weeks_threshold", help="Age threshold in weeks")
    parser.add_argument("default_branch", help="Default branch name")
    parser.add_argument("protected_branches", help="Space-separated list of protected branches")
    parser.add_argument("repo", help="Repository name (owner/repo)")
    
    args = parser.parse_args()
    
    # Convert arguments to appropriate types
    dry_run = args.dry_run.lower() == "true"
    
    try:
        weeks_threshold = int(args.weeks_threshold)
        if weeks_threshold <= 0:
            print("::error::weeks_threshold must be a positive number")
            return 1
    except ValueError:
        print("::error::weeks_threshold must be a positive number")
        return 1
        
    # Create and run the branch sweeper
    sweeper = BranchSweeper(
        dry_run=dry_run,
        weeks_threshold=weeks_threshold,
        default_branch=args.default_branch,
        protected_branches=args.protected_branches,
        repo=args.repo,
        verbose=os.environ.get("DEBUG") == "true",
        test_mode=os.environ.get("GITHUB_TEST_MODE") == "true",
    )
    
    return sweeper.run()


if __name__ == "__main__":
    sys.exit(main())
