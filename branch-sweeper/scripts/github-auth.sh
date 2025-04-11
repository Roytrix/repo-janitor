#!/bin/bash
# filepath: github-auth.sh
# Helper script to handle GitHub authentication with GitHub App

# Function to check if GitHub CLI is authenticated
check_github_auth() {
  # First check if we have app credentials
  if [ -n "${RJ_APP_ID}" ] && [ -n "${RJ_PRIVATE_KEY}" ]; then
    # GitHub App authentication
    echo "Using GitHub App authentication with App ID: ${RJ_APP_ID}"
    
    # Create temporary private key file if we have the key content
    local private_key_path
    if [ -f "${RJ_PRIVATE_KEY}" ]; then
      # Use the provided file path
      private_key_path="${RJ_PRIVATE_KEY}"
    else
      # Create a temporary file for the private key content
      private_key_path=$(mktemp)
      echo "${RJ_PRIVATE_KEY}" > "${private_key_path}"
      # Ensure proper permissions for the private key
      chmod 600 "${private_key_path}"
    fi
    
    # Generate JWT for GitHub App
    local now=$(date +%s)
    local expiry=$((now + 600)) # 10 minutes expiry
    
    # Create JWT header and payload
    local header='{"alg":"RS256","typ":"JWT"}'
    local payload="{\"iat\":${now},\"exp\":${expiry},\"iss\":${RJ_APP_ID}}"
    
    # Base64 encode header and payload
    local b64_header=$(echo -n "${header}" | base64 | tr -d '=' | tr '/+' '_-')
    local b64_payload=$(echo -n "${payload}" | base64 | tr -d '=' | tr '/+' '_-')
    
    # Create signature using private key
    local signature=$(echo -n "${b64_header}.${b64_payload}" | openssl dgst -sha256 -sign "${private_key_path}" | base64 | tr -d '=' | tr '/+' '_-')
    
    # Create JWT
    local jwt="${b64_header}.${b64_payload}.${signature}"
    
    # Clean up temporary file if created
    if [ "${private_key_path}" != "${RJ_PRIVATE_KEY}" ]; then
      rm "${private_key_path}"
    fi
    
    echo "JWT token generated successfully"
    
    # Get installation ID if not provided
    local installation_id="${RJ_INSTALLATION_ID}"
    if [ -z "${installation_id}" ]; then
      echo "Installation ID not provided, fetching from API..."
      
      # Get installation ID from GitHub API
      local installations_response=$(curl -s -H "Authorization: Bearer ${jwt}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/app/installations")
      
      # Extract first installation ID
      installation_id=$(echo "${installations_response}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
      
      if [ -z "${installation_id}" ]; then
        echo "Failed to get installation ID for GitHub App."
        echo "API Response:"
        echo "${installations_response}"
        return 1
      fi
      
      echo "Found installation ID: ${installation_id}"
    fi
    
    # Use JWT to get installation token
    local token_response=$(curl -s -X POST \
      -H "Authorization: Bearer ${jwt}" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/app/installations/${installation_id}/access_tokens")
    
    # Extract token from response
    local token=$(echo "${token_response}" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    
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

# Function to get current GitHub user/app
get_github_user() {
  if ! check_github_auth; then
    return 1
  fi
  
  # For GitHub Apps, we might be operating as the app
  local user
  if [ -n "${GITHUB_APP_NAME}" ]; then
    user="${GITHUB_APP_NAME}"
  else
    user=$(gh api user --jq '.login' 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$user" ]; then
      echo "Failed to get GitHub user information."
      return 1
    fi
  fi
  
  echo "$user"
  return 0
}
