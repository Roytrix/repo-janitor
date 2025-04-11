#!/bin/bash
# filepath: github-auth.sh
# Helper script to handle GitHub authentication with GitHub App

# Function to check if GitHub CLI is authenticated
check_github_auth() {
  # First check if we have app credentials
  if [ -n "${GITHUB_APP_ID}" ] && [ -n "${GITHUB_PRIVATE_KEY_PATH}" ] && [ -n "${GITHUB_INSTALLATION_ID}" ]; then
    # GitHub App authentication
    echo "Using GitHub App authentication"
    
    # Generate JWT for GitHub App
    local now=$(date +%s)
    local expiry=$((now + 600)) # 10 minutes expiry
    
    # Create JWT header and payload
    local header='{"alg":"RS256","typ":"JWT"}'
    local payload="{\"iat\":${now},\"exp\":${expiry},\"iss\":${GITHUB_APP_ID}}"
    
    # Base64 encode header and payload
    local b64_header=$(echo -n "${header}" | base64 | tr -d '=' | tr '/+' '_-')
    local b64_payload=$(echo -n "${payload}" | base64 | tr -d '=' | tr '/+' '_-')
    
    # Create signature using private key
    local signature=$(echo -n "${b64_header}.${b64_payload}" | openssl dgst -sha256 -sign "${GITHUB_PRIVATE_KEY_PATH}" | base64 | tr -d '=' | tr '/+' '_-')
    
    # Create JWT
    local jwt="${b64_header}.${b64_payload}.${signature}"
    
    # Use JWT to get installation token
    local token_response=$(curl -s -X POST \
      -H "Authorization: Bearer ${jwt}" \
      -H "Accept: application/vnd.github.v3+json" \
      "https://api.github.com/app/installations/${GITHUB_INSTALLATION_ID}/access_tokens")
    
    # Extract token from response
    local token=$(echo "${token_response}" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    
    if [ -z "${token}" ]; then
      echo "Failed to get installation token for GitHub App."
      return 1
    fi
    
    # Set token for GitHub CLI
    export GITHUB_TOKEN="${token}"
    echo "${GITHUB_TOKEN}" | gh auth login --with-token
    
  elif [ -n "${GITHUB_TOKEN}" ]; then
    # Personal Access Token authentication (fallback)
    echo "Using GitHub Personal Access Token authentication"
    echo "${GITHUB_TOKEN}" | gh auth login --with-token
  else
    echo "Error: No GitHub authentication method available."
    echo "Please set either:"
    echo "  - GITHUB_TOKEN environment variable for PAT authentication"
    echo "  - GITHUB_APP_ID, GITHUB_PRIVATE_KEY_PATH, and GITHUB_INSTALLATION_ID for GitHub App authentication"
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
