#!/bin/bash
# filepath: github-auth.sh
# Helper script to handle GitHub authentication with GitHub App for GitHub Actions
check_github_auth() {
  # Check if we're running in GitHub Actions
  if [ -z "${GITHUB_ACTIONS}" ]; then
    echo "Warning: This script is designed to run in GitHub Actions environment"
  fi
  
  # Always prioritize GitHub App authentication
  if [ -n "${RJ_APP_ID}" ] && { [ -n "${RJ_APP_PRIVATE_KEY}" ] || [ -n "${RJ_APP_PRIVATE_KEY_PATH}" ]; }; then
    echo "Using GitHub App authentication (preferred method)"
  elif [ -n "${GITHUB_TOKEN}" ]; then
    echo "GITHUB_TOKEN detected but not using it - GitHub App authentication is preferred"
    echo "Please set RJ_APP_ID and RJ_APP_PRIVATE_KEY/RJ_APP_PRIVATE_KEY_PATH to use GitHub App auth"
    echo "Attempting to continue with GitHub App auth setup..."
  fi
  
  # Authentication logic - single conditional block to avoid nesting issues
  if [ -n "${RJ_APP_ID}" ] && { [ -n "${RJ_APP_PRIVATE_KEY}" ] || [ -n "${RJ_APP_PRIVATE_KEY_PATH}" ]; }; then
    # GitHub App authentication
    echo "Using GitHub App authentication with App ID: ${RJ_APP_ID}"
    
    # Determine the private key source
    local private_key_path
    
    if [ -n "${RJ_APP_PRIVATE_KEY_PATH}" ] && [ -f "${RJ_APP_PRIVATE_KEY_PATH}" ]; then
      # Use the provided path to private key
      private_key_path="${RJ_APP_PRIVATE_KEY_PATH}"
      echo "Using private key from path: ${private_key_path}"
    elif [ -n "${RJ_APP_PRIVATE_KEY}" ]; then
      # Create temporary private key file from the provided key content
      private_key_path=$(mktemp)
      echo "${RJ_APP_PRIVATE_KEY}" > "${private_key_path}"
      echo "Created temporary private key file from RJ_APP_PRIVATE_KEY"
    else
      echo "Error: Neither RJ_APP_PRIVATE_KEY nor RJ_APP_PRIVATE_KEY_PATH contains a valid private key"
      return 1
    fi
    # Ensure proper permissions for the private key
    chmod 600 "${private_key_path}"
    
    # Generate JWT for GitHub App
    local now
    now=$(date +%s)
    local expiry
    expiry=$((now + 600)) # 10 minutes expiry
    
    # Create JWT header and payload
    local header='{"alg":"RS256","typ":"JWT"}'
    local payload="{\"iat\":${now},\"exp\":${expiry},\"iss\":\"${RJ_APP_ID}\"}"
    
    # Base64 encode header and payload
    local b64_header
    b64_header=$(echo -n "${header}" | base64 | tr -d '=' | tr '/+' '_-')
    local b64_payload
    b64_payload=$(echo -n "${payload}" | base64 | tr -d '=' | tr '/+' '_-')
    
    # Create signature using private key
    local signature
    signature=$(echo -n "${b64_header}.${b64_payload}" | openssl dgst -sha256 -sign "${private_key_path}" | base64 | tr -d '=' | tr '/+' '_-')
    
    # Create JWT
    local jwt="${b64_header}.${b64_payload}.${signature}"
    
    # Clean up temporary file if created
    if [ -n "${private_key_path}" ] && [ "${private_key_path}" != "${RJ_APP_PRIVATE_KEY_PATH}" ]; then
      rm "${private_key_path}"
    fi
    
    echo "JWT token generated successfully"
    
    # Try to use gh CLI to get installations (preferred method)
    echo "Getting GitHub App installations using gh CLI..."
    local installation_id
    local installations_json
    
    # Use the hardcoded installation ID instead of trying to retrieve it dynamically
    local installation_id="64354788"
    echo "Using fixed installation ID: ${installation_id}"
    
    # Skip the dynamic installation ID retrieval process entirely
    if false; then
      # This block will never execute but keeps the structure intact
      echo "This code is skipped - using hardcoded installation ID instead"
      
      # Skip installation ID retrieval and directly use the JWT token for authentication
      echo "Using JWT token for authentication (last 4 chars: ${jwt: -4})"
      
      # Authenticate directly with the JWT token
      echo "${jwt}" | gh auth login --with-token
      
      if ! gh auth status &>/dev/null; then
        echo "Error: Failed to authenticate with GitHub using JWT token"
        echo "This is likely an authentication issue with your App ID or private key"
        return 1
      fi
      
      echo "Successfully authenticated directly with JWT token"
      
      # Setting a dummy value so following code still works
      local installation_id="not_needed"
    fi
    
    # Use JWT to get installation access token as per GitHub documentation
    echo "Generating installation access token for installation ID: ${installation_id}"
    
    # First try using gh CLI directly to get token (more reliable in GitHub Actions)
    echo "Using GitHub CLI to generate installation token..."
    local token=""
    local token_response=""
    
    # Use gh CLI to get installation token - this avoids SSL and other HTTP issues
    # gh api doesn't have a --raw flag, using correct syntax
    if token_response=$(gh api --method POST "/app/installations/${installation_id}/access_tokens" \
      --header "Authorization: Bearer ${jwt}" 2>&1); then
      
      echo "Successfully received response from GitHub API"
      # Extract token from the API response
      token=$(echo "$token_response" | jq -r '.token' 2>/dev/null)
      
      if [ -z "$token" ] || [ "$token" = "null" ]; then
        echo "Could not extract token from response using jq, trying grep fallback"
        token=$(echo "$token_response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
      fi
    else
      echo "GitHub CLI failed to get installation token:"
      echo "$token_response"
      echo "Trying alternative method..."
      
      # Try to extract error message for better diagnostics
      if [[ "$token_response" == *"message"* ]]; then
        echo "Error message: $(echo "$token_response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)"
      fi
      
      # Try direct curl call with very verbose output for debugging
      echo "Using curl with verbose output..."
      token_response=$(curl -v -X POST \
        -H "Authorization: Bearer ${jwt}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/app/installations/${installation_id}/access_tokens" 2>&1)
        
      # Try to extract token from response
      token=$(echo "${token_response}" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    else
      # Extract token from GitHub CLI response
      token=$(echo "${token_response}" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    fi
    
    if [ -z "${token}" ]; then
      echo "Failed to get installation token for GitHub App."
      echo "API Response (partial):"
      # Only show a limited portion of the response for security
      echo "${token_response:0:500}"
      
      echo "Trying to use JWT directly as a fallback..."
      token="${jwt}"
    fi
    
    # Set token for GitHub CLI
    export GITHUB_TOKEN="${token}"
    echo "${GITHUB_TOKEN}" | gh auth login --with-token
    
  elif [ -n "${RJ_TOKEN}" ]; then
    # Personal Access Token authentication (fallback)
    echo "Using GitHub Personal Access Token authentication"
    echo "${RJ_TOKEN}" | gh auth login --with-token
  else
    echo "Error: No GitHub authentication method available."
    echo "Please set either:"
    echo "  - RJ_TOKEN environment variable for PAT authentication"
    echo "  - RJ_APP_ID, RJ_PRIVATE_KEY_PATH, and RJ_INSTALLATION_ID for GitHub App authentication"
    return 1
  fi
  
  # Verify authentication was successful
  if ! gh auth status &>/dev/null; then
    echo "GitHub authentication failed. Please check your credentials."
    return 1
  fi
  
  echo "GitHub authentication successful."
  return 0
}

# Function to get operating identity (app or user)
get_operating_identity() {
  # When using a GitHub App, identify as the app
  if [ -n "${RJ_APP_ID}" ]; then
    # Explicitly using app identity for GitHub App authentication
    echo "app/repo-janitor"
    return 0
  fi

  # For GitHub Actions environment
  if [ -n "${GITHUB_ACTIONS}" ]; then
    echo "github-actions[bot]"
    return 0
  fi
  
  # Only for personal access token user authentication
  # Attempt to get actual username (not for GitHub Apps)
  if [ -z "${RJ_APP_ID}" ] && gh auth status &>/dev/null; then
    local user
    if user=$(gh api user --jq '.login' 2>/dev/null) && [ -n "$user" ]; then
      echo "$user"
      return 0
    fi
    # Fallback for authenticated user with no API access
    echo "github-user"
    return 0
  fi
  
  echo "Unknown identity - authentication may have failed"
  return 1
}

# Maintain backward compatibility
get_github_user() {
  get_operating_identity "$@"
}
