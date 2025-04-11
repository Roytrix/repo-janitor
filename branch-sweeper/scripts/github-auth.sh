#!/bin/bash
# filepath: github-auth.sh
# Helper script to handle GitHub authentication with GitHub App for GitHub Actions

# Function to check if GitHub CLI is authenticated
check_github_auth() {
  # Check if we're running in GitHub Actions
  if [ -z "${GITHUB_ACTIONS}" ]; then
    echo "Warning: This script is designed to run in GitHub Actions environment"
  fi
  
  # Check for GitHub token from Actions
  if [ -n "${GITHUB_TOKEN}" ]; then
    echo "Using GITHUB_TOKEN from GitHub Actions"
    # GitHub Actions automatically provides GITHUB_TOKEN, we just need to login with it
    echo "${GITHUB_TOKEN}" | gh auth login --with-token
    return 0
  fi
  
  # Check if we have app credentials as fallback
  if [ -n "${RJ_APP_ID}" ] && { [ -n "${RJ_APP_PRIVATE_KEY}" ] || [ -n "${RJ_APP_PRIVATE_KEY_PATH}" ]; }; then
    # GitHub App authentication
    echo "Using GitHub App authentication with App ID: ${RJ_APP_ID}"
    
    # Determine the private key source
    local private_key_content
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
    if [ "${private_key_path}" != "${RJ_PRIVATE_KEY}" ]; then
      rm "${private_key_path}"
    fi
    
    echo "JWT token generated successfully"
    
    # Get installation ID if not provided
    local installation_id="${RJ_APP_INSTALLATION_ID}"
    if [ -z "${installation_id}" ]; then
      echo "Installation ID not provided, fetching from API..."
      
      # Get installation ID from GitHub API
      local installations_response
      installations_response=$(curl -s -H "Authorization: Bearer ${jwt}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/app/installations")
      
      # In GitHub Actions, jq should be available
      installation_id=$(echo "${installations_response}" | jq -r '.[0].id' 2>/dev/null)
      
      # Fallback to grep if jq fails
      if [ -z "${installation_id}" ] || [ "${installation_id}" = "null" ]; then
        installation_id=$(echo "${installations_response}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
      fi
      
      if [ -z "${installation_id}" ]; then
        echo "Failed to get installation ID for GitHub App."
        echo "API Response: ${installations_response}"
        echo "Set RJ_INSTALLATION_ID in your GitHub Actions secrets."
        return 1
      fi
      
      echo "Found installation ID: ${installation_id}"
    fi
    
    # Use JWT to get installation token
    local token_response
    token_response=$(curl -s -X POST \
      -H "Authorization: Bearer ${jwt}" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/app/installations/${installation_id}/access_tokens")
    
    # Extract token from response
    local token
    token=$(echo "${token_response}" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "${token}" ]; then
      echo "Failed to get installation token for GitHub App."
      echo "API Response:"
      echo "${token_response}"
      return 1
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
    user=$(gh api user --jq '.login' 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$user" ]; then
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
