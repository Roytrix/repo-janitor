#!/usr/bin/env python3
# filepath: /home/roytrix/Documents/source-code/repo-janitor/branch-sweeper/scripts/validate_inputs.py

import argparse
import re
import sys


def validate_weeks_threshold(weeks_threshold: str) -> int:
    """Validate that weeks_threshold is a positive number."""
    if not re.match(r'^[0-9]+$', weeks_threshold) or int(weeks_threshold) <= 0:
        print("::error::weeks_threshold must be a positive number")
        return 1
    return 0


def main():
    """Parse arguments and validate inputs."""
    parser = argparse.ArgumentParser(description="Validate inputs for branch sweeper")
    parser.add_argument("weeks_threshold", help="Age threshold in weeks")
    
    args = parser.parse_args()
    return validate_weeks_threshold(args.weeks_threshold)


if __name__ == "__main__":
    sys.exit(main())
