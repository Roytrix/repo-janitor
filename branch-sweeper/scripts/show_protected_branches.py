#!/usr/bin/env python3
# filepath: /home/roytrix/Documents/source-code/repo-janitor/branch-sweeper/scripts/show_protected_branches.py

import argparse
import sys


def show_protected_branches(branches: str) -> int:
    """Display protected branches."""
    print(f"Protected branches in the repository: {branches}")
    return 0


def main():
    """Parse arguments and show protected branches."""
    parser = argparse.ArgumentParser(description="Show protected branches")
    parser.add_argument("branches", help="Space-separated list of protected branches")
    
    args = parser.parse_args()
    return show_protected_branches(args.branches)


if __name__ == "__main__":
    sys.exit(main())
