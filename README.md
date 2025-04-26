# Repo Janitor

Repository cleaning and maintenance tools for GitHub repositories.

## Branch Sweeper

Branch Sweeper is a tool that automatically cleans up stale branches in GitHub repositories. It identifies and removes:

1. Old branches that have been properly merged
2. Very old branches that were never merged

### Features

- Identifies branches that have been merged via Pull Requests
- Detects branches merged directly into protected branches
- Configurable age thresholds for deletion
- Dry-run mode for testing without making changes
- Respects protected branches
- Generates detailed summary reports

### Usage

Add this GitHub Action to your repository:

```yaml
name: Clean up stale branches

on:
  schedule:
    - cron: '0 0 * * 0'  # Run weekly
  workflow_dispatch:  # Allow manual triggering

jobs:
  cleanup-branches:
    runs-on: ubuntu-latest
    steps:
      - name: Run Branch Sweeper
        uses: github/repo-janitor/branch-sweeper@main
        with:
          # Run in dry-run mode (set to 'false' to actually delete branches)
          dry_run: 'true'
          # Age threshold in weeks
          weeks_threshold: '4'
          # Default branch (leave empty to auto-detect)
          default_branch: ''
          # GitHub token with repo permissions
          token: ${{ secrets.GITHUB_TOKEN }}
```

### Implementation

Branch Sweeper is implemented in Python, making it portable across different environments. It uses the GitHub API via the `gh` CLI tool to interact with repositories.

### Local Usage

You can run Branch Sweeper directly from your local machine:

1. Clone this repository:
   ```bash
   git clone https://github.com/github/repo-janitor.git
   cd repo-janitor
   ```

   > **Note:** The project has been fully migrated from Bash to Python.

2. Run the branch sweeper:
   ```bash
   # Using the Python wrapper script
   ./branch-sweeper/run_sweeper.py --dry-run=true --weeks-threshold=4 --default-branch="" --repo="owner/repo"
   
   # Or run the Python script directly
   python3 ./branch-sweeper/scripts/branch_sweeper.py [dry_run] [weeks_threshold] [default_branch] [protected_branches] [repo]
   ```

3. Alternatively, you can install it using pip:
   ```bash
   # Install from the repository
   pip install -e ./branch-sweeper
   
   # Then run it
   branch-sweeper [dry_run] [weeks_threshold] [default_branch] [protected_branches] [repo]
   ```

### Requirements

- Python 3.7 or later
- GitHub CLI (`gh`) installed and authenticated

### Testing

To run the test suite:

```bash
# Run all local tests
./branch-sweeper/run_tests.py

# Run GitHub repository tests (requires GitHub authentication)
./branch-sweeper/run_tests.py --github --repo-name="repo-janitor-testing" --repo-owner="your-username"
```