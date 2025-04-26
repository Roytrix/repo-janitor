#!/usr/bin/env python3
# filepath: /home/roytrix/Documents/source-code/repo-janitor/branch-sweeper/tests/test_repository_cleanup.py

import os
import shutil
import sys
from pathlib import Path


class TerminalColors:
    """ANSI color codes for terminal output."""
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[0;31m'
    NC = '\033[0m'  # No Color


class TestRepositoryCleanup:
    """Clean up the test repository created for testing."""
    
    def __init__(self, repo_dir="./repo-test"):
        """Initialize the test repository cleanup."""
        self.repo_dir = Path(repo_dir)
    
    def cleanup(self):
        """Clean up the test repository and related files."""
        print(f"{TerminalColors.YELLOW}Starting test repository cleanup...{TerminalColors.NC}")
        
        # Check if the repo-test directory exists
        if self.repo_dir.exists():
            print(f"Found repo-test directory, removing...")
            
            try:
                # Remove the entire directory
                shutil.rmtree(self.repo_dir)
                print(f"{TerminalColors.GREEN}Successfully removed repo-test directory{TerminalColors.NC}")
            except Exception as e:
                print(f"{TerminalColors.RED}Error removing repo-test directory: {e}{TerminalColors.NC}")
                return 1
        else:
            print(f"{TerminalColors.YELLOW}No repo-test directory found, nothing to clean up{TerminalColors.NC}")
        
        # Clean up fake remote if it exists
        fake_remote = Path("/tmp/fake-remote")
        if fake_remote.exists():
            print("Removing fake remote directory...")
            try:
                shutil.rmtree(fake_remote)
                print(f"{TerminalColors.GREEN}Successfully removed fake remote{TerminalColors.NC}")
            except Exception as e:
                print(f"{TerminalColors.RED}Error removing fake remote: {e}{TerminalColors.NC}")
        
        # Clean up any summary files
        summary_file = Path("summary.md")
        if summary_file.exists():
            print("Removing summary file...")
            try:
                summary_file.unlink()
                print(f"{TerminalColors.GREEN}Successfully removed summary file{TerminalColors.NC}")
            except Exception as e:
                print(f"{TerminalColors.RED}Error removing summary file: {e}{TerminalColors.NC}")
        
        print(f"{TerminalColors.GREEN}Test repository cleanup completed successfully{TerminalColors.NC}")
        print(f"{TerminalColors.YELLOW}You can now run new tests with a clean environment{TerminalColors.NC}")
        
        return 0


def main():
    """Run the test repository cleanup."""
    cleanup = TestRepositoryCleanup()
    return cleanup.cleanup()


if __name__ == "__main__":
    sys.exit(main())
