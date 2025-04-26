#!/usr/bin/env python3
# filepath: /home/roytrix/Documents/source-code/repo-janitor/branch-sweeper/tests/test_sweeping.py

import argparse
import os
import subprocess
import sys
from pathlib import Path

# Add parent directory to sys.path
sys.path.append(str(Path(__file__).parent.parent))

# Import branch sweeper
from scripts.branch_sweeper import BranchSweeper


class TerminalColors:
    """ANSI color codes for terminal output."""
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    NC = '\033[0m'  # No Color


class BranchSweeperTester:
    """Test the Branch Sweeper with different configurations."""
    
    def __init__(self):
        """Initialize the branch sweeper tester."""
        # Determine script locations
        self.script_dir = Path(__file__).parent
        self.sweeper_script = self.script_dir.parent / "scripts" / "branch_sweeper.py"
        self.setup_script = self.script_dir / "test_repository_setup.py"
        self.cleanup_script = self.script_dir / "test_repository_cleanup.py"
        
        # Make sure the scripts are executable
        os.chmod(self.sweeper_script, 0o755)
        os.chmod(self.setup_script, 0o755)
        os.chmod(self.cleanup_script, 0o755)
    
    def _run_command(self, cmd, cwd=None, capture_output=True):
        """Run a command and return the result."""
        try:
            result = subprocess.run(
                cmd,
                cwd=cwd,
                capture_output=capture_output,
                text=True,
                check=False,
                shell=isinstance(cmd, str)
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

    def create_github_summary(self):
        """Create a GitHub summary file."""
        summary_file = "github-summary.md"
        
        with open(summary_file, "w") as f:
            f.write("# Branch Sweeper Test Results\n")
            import datetime
            f.write(f"{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
            f.write("## Test Scenarios\n")
        
        return summary_file

    def setup_test_repository(self):
        """Set up the test repository if it doesn't exist."""
        if not Path("./repo-test").exists():
            print("Setting up test repository first...")
            result = self._run_command([sys.executable, str(self.setup_script)], capture_output=False)
            if result.returncode != 0:
                print(f"{TerminalColors.RED}Error: Test repository setup failed.{TerminalColors.NC}")
                sys.exit(1)

    def check_branch_dates(self):
        """Check and display branch dates for debugging."""
        print(f"\n{TerminalColors.YELLOW}Checking branch dates before sweeping:{TerminalColors.NC}")
        
        # Get all branches
        branch_result = self._run_command(["git", "branch"], cwd="./repo-test")
        if branch_result.returncode != 0:
            print(f"{TerminalColors.RED}Error getting branches: {branch_result.stderr}{TerminalColors.NC}")
            return
        
        # Process each branch to get dates and merge status
        for branch_line in branch_result.stdout.splitlines():
            branch = branch_line.strip().replace("* ", "")
            if not branch:
                continue
                
            # Get last commit date
            date_result = self._run_command(
                ["git", "log", "-1", "--format=%ci", branch],
                cwd="./repo-test"
            )
            last_commit_date = date_result.stdout.strip() if date_result.returncode == 0 else "unknown"
            
            # Check merge status
            merged_result = self._run_command(
                ["git", "branch", "--merged", "main"],
                cwd="./repo-test"
            )
            if merged_result.returncode == 0 and branch in merged_result.stdout:
                merged_status = "merged"
            else:
                merged_status = "not merged"
                
            print(f"Branch {branch}: Last commit: {last_commit_date}, Status: {merged_status}")

    def run_test(self, test_name, dry_run, weeks, default_branch, protected_branches, repo):
        """Run a branch sweeper test."""
        # Make sure test repository is set up
        self.setup_test_repository()
        
        print(f"\n{TerminalColors.YELLOW}===================================={TerminalColors.NC}")
        print(f"{TerminalColors.YELLOW}Running Test: {test_name}{TerminalColors.NC}")
        print(f"{TerminalColors.YELLOW}===================================={TerminalColors.NC}")
        print("Parameters:")
        print(f"  - Dry Run: {dry_run}")
        print(f"  - Weeks Threshold: {weeks}")
        print(f"  - Default Branch: {default_branch}")
        print(f"  - Protected Branches: {protected_branches}")
        print(f"  - Repository: {repo}")
        print(f"{TerminalColors.YELLOW}------------------------------------{TerminalColors.NC}")
        
        # Check branch dates before sweeping
        self.check_branch_dates()
        
        # Enable verbose mode for debugging
        os.environ["DEBUG"] = "true"
        os.environ["GITHUB_TEST_MODE"] = "true"  # Use test mode to avoid API calls
        
        # Run the branch sweeper directly
        print(f"\n{TerminalColors.YELLOW}Running branch sweeper:{TerminalColors.NC}")
        
        # Create a BranchSweeper instance
        try:
            sweeper = BranchSweeper(
                dry_run=dry_run.lower() == "true",
                weeks_threshold=int(weeks),
                default_branch=default_branch,
                protected_branches=protected_branches,
                repo=repo,
                verbose=True,
                test_mode=True
            )
            
            # Run the sweeper
            result = sweeper.run()
            
            if result == 0:
                print(f"{TerminalColors.GREEN}Branch sweeper completed successfully{TerminalColors.NC}")
            else:
                print(f"{TerminalColors.RED}Branch sweeper failed with code {result}{TerminalColors.NC}")
                
            # Check results in summary.md
            if Path("summary.md").exists():
                print(f"\n{TerminalColors.YELLOW}Summary:{TerminalColors.NC}")
                with open("summary.md", "r") as f:
                    print(f.read())
            
            # Check branch dates after sweeping
            print(f"\n{TerminalColors.YELLOW}Checking branch dates after sweeping:{TerminalColors.NC}")
            self.check_branch_dates()
            
            return result == 0
            
        except Exception as e:
            print(f"{TerminalColors.RED}Error running branch sweeper: {e}{TerminalColors.NC}")
            return False
    
    def run_all_tests(self):
        """Run all branch sweeper tests."""
        # Create GitHub summary
        summary_file = self.create_github_summary()
        
        # Set up test repository
        self.setup_test_repository()
        
        # List of test cases to run
        test_cases = [
            {
                "name": "Dry Run Test",
                "dry_run": "true",
                "weeks": "4",
                "default_branch": "main",
                "protected_branches": "develop production",
                "repo": "test/repo"
            },
            {
                "name": "Actual Deletion Test",
                "dry_run": "false",
                "weeks": "4",
                "default_branch": "main",
                "protected_branches": "develop production",
                "repo": "test/repo"
            },
            {
                "name": "Short Age Threshold Test",
                "dry_run": "true", 
                "weeks": "1",
                "default_branch": "main",
                "protected_branches": "develop",
                "repo": "test/repo"
            }
        ]
        
        # Run all test cases
        results = []
        for test in test_cases:
            success = self.run_test(**test)
            results.append((test["name"], success))
            
            # Clean up after each test and recreate test repo
            self._run_command([sys.executable, str(self.cleanup_script)], capture_output=False)
            if test != test_cases[-1]:  # If not the last test
                self.setup_test_repository()
        
        # Add results to summary
        with open(summary_file, "a") as f:
            f.write("\n## Test Results\n")
            for name, success in results:
                status = "✅ Passed" if success else "❌ Failed"
                f.write(f"- {name}: {status}\n")
        
        # Final cleanup
        self._run_command([sys.executable, str(self.cleanup_script)], capture_output=False)
        
        # Print overall result
        passed = sum(1 for _, success in results if success)
        total = len(results)
        print(f"\n{TerminalColors.GREEN}Tests completed: {passed}/{total} passed{TerminalColors.NC}")
        
        # Display summary content
        if Path(summary_file).exists():
            print(f"\n{TerminalColors.YELLOW}Summary from {summary_file}:{TerminalColors.NC}")
            with open(summary_file, "r") as f:
                print(f.read())
        
        # Return success if all tests passed
        return passed == total


def main():
    """Run the branch sweeper tests."""
    parser = argparse.ArgumentParser(description="Test the Branch Sweeper with different configurations")
    parser.add_argument("--test-name", help="Name of the test to run")
    parser.add_argument("--dry-run", help="Run in dry-run mode (true/false)", default="true")
    parser.add_argument("--weeks", help="Age threshold in weeks", default="4")
    parser.add_argument("--default-branch", help="Default branch name", default="main")
    parser.add_argument("--protected-branches", help="Protected branches (space-separated)", default="develop production")
    parser.add_argument("--repo", help="Repository name", default="test/repo")
    parser.add_argument("--run-all", help="Run all tests", action="store_true")
    
    args = parser.parse_args()
    
    tester = BranchSweeperTester()
    
    if args.run_all:
        return 0 if tester.run_all_tests() else 1
    elif args.test_name:
        return 0 if tester.run_test(
            args.test_name,
            args.dry_run,
            args.weeks,
            args.default_branch,
            args.protected_branches,
            args.repo
        ) else 1
    else:
        # Default to running all tests if no specific test is requested
        return 0 if tester.run_all_tests() else 1


if __name__ == "__main__":
    sys.exit(main())
