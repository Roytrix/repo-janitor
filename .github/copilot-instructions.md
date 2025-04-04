# GitHub Action with Bash Execution - Copilot Instructions

PRIORITIZE CODEBASE FOR SUGGESTIONS

## Project Structure

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

## Coding Standards

YAML (action.yml)
Use clear input/output names with descriptions
Specify default values where appropriate
Use composite actions with bash steps
Bash Scripts
Always include shebang line: #!/usr/bin/env bash
Use set -euo pipefail for strict error handling
Quote all variables: "${VAR}"
Use functions for reusable code blocks
Add comments for complex logic
Follow shellcheck recommendations
Testing Approach
Create test workflows in workflows
Test action against multiple OS environments
Include unit tests for bash functions
Test with various input combinations
Validate all outputs
GitHub Actions Patterns
Set outputs: echo "name=value" >> $GITHUB_OUTPUT
Set environment variables: echo "name=value" >> $GITHUB_ENV
Log messages: echo "::debug/warning/error::message"
Handle input validation with clear error messages
Bash Best Practices (shellcheck compliant)
Avoid common shellcheck warnings (SC2086, SC2046)
Parameter expansions can't start with {. Double check syntax.
Use arrays for lists instead of space-separated strings
Properly handle file paths with spaces
Check command success: if ! command; then
Use shellcheck inline directives only when necessary: # shellcheck disable=SC2034
GitHub Environment
Use ${{ github.token }} for authentication when possible
Access inputs via environment variables: $INPUT_NAME
Use GitHub-provided environment variables like GITHUB_WORKSPACE
