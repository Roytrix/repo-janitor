# GitHub Action with Bash Execution - Copilot Instructions

This document provides guidance for GitHub Copilot to assist with development of this GitHub Action project. It outlines the structure, conventions, and key components to help generate more accurate and helpful code suggestions.

## Project Structure

```
.
├── action.yml                 # Action definition file
├── entrypoint.sh              # Main entry point bash script
├── scripts/                   # Helper scripts directory
│   ├── setup.sh               # Environment setup script
│   ├── execute.sh             # Main execution script
│   └── cleanup.sh             # Post-execution cleanup script
├── tests/                     # Tests directory
│   ├── unit/                  # Unit tests
│   └── integration/           # Integration tests
└── README.md                  # Documentation
```

## Key Components

### 1. action.yml

- Defines the action name, description, inputs, outputs, and execution entry point
- Uses `using: 'composite'` with a bash script main entry point
- Follows the standard GitHub Action manifest format

Example pattern:
```yaml
name: 'Action Name'
description: 'Description of what the action does'
inputs:
  input-name:
    description: 'Description of input'
    required: true/false
    default: 'default value'
outputs:
  output-name:
    description: 'Description of output'
runs:
  using: 'composite'
  steps:
    - shell: bash
      run: ${{ github.action_path }}/entrypoint.sh
      env:
        INPUT_NAME: ${{ inputs.input-name }}
```

### 2. entrypoint.sh

- Acts as the main entry point called by action.yml
- Sources or executes scripts from the scripts/ directory
- Sets up proper environment variables from inputs
- Returns outputs as expected by GitHub Actions

Pattern:
```bash
#!/bin/bash
set -e

# Source helper functions
source "${GITHUB_ACTION_PATH}/scripts/setup.sh"

# Execute main functionality
"${GITHUB_ACTION_PATH}/scripts/execute.sh"

# Cleanup
source "${GITHUB_ACTION_PATH}/scripts/cleanup.sh"
```

### 3. Scripts Structure

#### setup.sh
- Sets up the environment
- Validates inputs
- Installs dependencies

#### execute.sh
- Contains the main action logic
- Uses GitHub CLI for API interactions
- Sets outputs using GitHub Actions workflow commands

#### cleanup.sh
- Performs any necessary cleanup
- Ensures resources are properly released

### 4. GitHub CLI Integration

- Uses GitHub CLI (`gh`) for API interactions
- Authenticates using the GITHUB_TOKEN

Pattern:
```bash
gh api \
  --method POST \
  -H "Accept: application/vnd.github.v3+json" \
  "/repos/${GITHUB_REPOSITORY}/issues" \
  -f title="Title" \
  -f body="Body"
```

### 5. Testing

#### Unit Tests
- Tests individual functions
- May use bats or similar bash testing frameworks
- Mocks external dependencies

#### Integration Tests
- Tests the entire action
- Uses Docker to simulate GitHub Actions environment
- Verifies expected outputs

## Coding Conventions

1. **Bash Best Practices**
   - Use `set -e` to exit on error
   - Use `set -u` to error on undefined variables
   - Use functions for reusable code
   - Quote all variables: `"${VAR}"`
   - Include helpful error messages

2. **Error Handling**
   - Validate all inputs
   - Provide descriptive error messages
   - Use proper exit codes

3. **GitHub Actions Conventions**
   - Set outputs using `echo "name=value" >> $GITHUB_OUTPUT`
   - Set environment variables using `echo "name=value" >> $GITHUB_ENV`
   - Use `debug`, `warning`, and `error` for logging

4. **Documentation**
   - Include docstrings for functions
   - Add comments for complex logic
   - Document expected inputs and outputs

## Common Patterns

### Setting Outputs
```bash
echo "output-name=${value}" >> $GITHUB_OUTPUT
```

### Error Handling
```bash
if [ -z "${INPUT_REQUIRED_VAR}" ]; then
  echo "::error::Required input 'required-var' is missing"
  exit 1
fi
```

### GitHub CLI Authentication
```bash
# GitHub CLI uses GITHUB_TOKEN automatically in Actions environment
# For local testing:
# export GITHUB_TOKEN="your-token"
```

### Running in Debug Mode
```bash
if [ "${INPUT_DEBUG}" = "true" ]; then
  set -x
fi
```

## Development Workflow

1. Make changes to scripts
2. Run unit tests: `./tests/unit/run-tests.sh`
3. Run integration tests: `./tests/integration/run-tests.sh`
4. Update documentation if needed
5. Commit and push changes
