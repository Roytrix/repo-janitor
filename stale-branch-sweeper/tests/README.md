# Integration Tests for Stale Branch Sweeper

This directory contains integration tests for the stale-branch-sweeper action.

## Test Structure

- `integration/`: Contains test scripts for different scenarios
- `utils/`: Contains utility scripts for mocking GitHub environment and repositories
- `run-tests.sh`: Main script to run all tests
- `results/`: Directory where test logs are stored

## Running the Tests

To run all tests:

```bash
./run-tests.sh
```

## Test Cases

1. **Dry Run Mode** - Tests that branches are correctly identified but not deleted when in dry run mode
2. **Actual Delete Mode** - Tests that stale branches are correctly deleted while protected branches are preserved
3. **Protected Branches** - Tests that protected branches are never deleted
4. **Branch Age Threshold** - Tests that only branches older than the specified threshold are deleted

## Adding New Tests

Add new test scripts to the `integration/` directory and make them executable. The main test runner will automatically discover and run them.
