#!/usr/bin/env python3
# filepath: /home/roytrix/Documents/source-code/repo-janitor/branch-sweeper/run_tests.py

"""
Script to run the branch sweeper tests.
This is a wrapper script that provides a convenient way to run the tests.
"""

import argparse
import sys
from pathlib import Path

# Add current directory to Python path
script_dir = Path(__file__).parent
sys.path.append(str(script_dir))


def main():
    """Run the branch sweeper tests."""
    parser = argparse.ArgumentParser(description="Run branch sweeper tests")
    parser.add_argument("--github", action="store_true", help="Run GitHub repository tests")
    parser.add_argument("--repo-name", default="repo-janitor-testing", help="Repository name for GitHub tests")
    parser.add_argument("--repo-owner", default="", help="Repository owner for GitHub tests")
    parser.add_argument("--run-all", action="store_true", help="Run all local tests")
    
    args = parser.parse_args()
    
    if args.github:
        print("Running GitHub repository tests...")
        # Import here to avoid import errors if GitHub CLI is not installed
        from tests.github_repo_tests.test_github_sweeping_repo import main as github_test_main
        return github_test_main(args.repo_name, args.repo_owner)
    else:
        print("Running local tests...")
        from tests.test_sweeping import main as local_test_main
        # Pass --run-all to ensure all tests are run
        sys.argv = [sys.argv[0], "--run-all"]
        return local_test_main()


if __name__ == "__main__":
    sys.exit(main())
