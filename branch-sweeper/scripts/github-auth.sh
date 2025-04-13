#!/bin/bash
# filepath: github-auth.sh
# Helper script to handle GitHub authentication with GitHub App for GitHub Actions

# Function to check if GitHub CLI is authenticated
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
  
  # Always check for GitHub App credentials first
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
    
    # Use gh CLI to get installations (avoids SSL issues)
    if installations_json=$(gh api app/installations --header "Authorization: Bearer ${jwt}" 2>/dev/null); then
      # Check if we got valid JSON with installations
      if [ -n "${installations_json}" ] && [ "$(echo "${installations_json}" | jq 'length' 2>/dev/null)" -gt 0 ]; then
        installation_id=$(echo "${installations_json}" | jq -r '.[0].id' 2>/dev/null)
        echo "Successfully retrieved installation data using gh CLI"
        echo "Found $(echo "${installations_json}" | jq 'length') installation(s)"
      else
        echo "No installations found or invalid response from gh CLI"
      fi
    else
      echo "Could not get installations using gh CLI, falling back to direct API call"
    fi
    
    # Fall back to direct API call if gh CLI method failed
    if [ -z "${installation_id}" ]; then
      echo "Fetching GitHub App installation ID directly from API..."
      local installations_response
      local curl_exit_code
      
      # Debug output to show the JWT token is being used (masked for security)
      echo "Using JWT token for authentication: ${jwt:0:10}...${jwt: -10}"
      
      echo "Calling GitHub API: https://api.github.com/app/installations"
    
      # Use GH CLI API command for reliable communication with GitHub API
    # This avoids SSL issues that direct curl can encounter
    echo "Trying gh api command for installation retrieval..."
    installations_response=$(gh api --method GET \
      --header "Authorization: Bearer ${jwt}" \
      --header "Accept: application/vnd.github+json" \
      --header "X-GitHub-Api-Version: 2022-11-28" \
      "app/installations" 2>/dev/null || echo '{"error":"gh api command failed"}')
    
    # Check if gh api command succeeded
    if echo "${installations_response}" | grep -q '"error":'; then
      # Fall back to curl but with better SSL handling
      echo "GH CLI API call failed, falling back to curl with improved SSL handling..."
      
      # Check for CA certificates and install if needed
      if [ -f "/etc/ssl/certs/ca-certificates.crt" ]; then
        echo "Using system CA certificates"
        installations_response=$(curl --cacert /etc/ssl/certs/ca-certificates.crt -s -w "\nHTTP_STATUS:%{http_code}" \
          -H "Authorization: Bearer ${jwt}" \
          -H "Accept: application/vnd.github+json" \
          -H "X-GitHub-Api-Version: 2022-11-28" \
          "https://api.github.com/app/installations")
      else
        echo "Using curl's default CA certificate store"
        installations_response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
          -H "Authorization: Bearer ${jwt}" \
          -H "Accept: application/vnd.github+json" \
          -H "X-GitHub-Api-Version: 2022-11-28" \
          "https://api.github.com/app/installations")
      fi
      curl_exit_code=$?
      
      # If still failing with SSL issues, try GitHub's public key pinning
      if [ ${curl_exit_code} -eq 43 ] || [ ${curl_exit_code} -eq 60 ]; then
        echo "Standard SSL validation still failing. Using GitHub's API directly through gh CLI..."
        # Use gh with raw mode and bare minimum options
        gh_response=$(gh api --method GET \
          --header "Authorization: Bearer ${jwt}" \
          "app/installations" --raw 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "${gh_response}" ]; then
          echo "Successfully retrieved data via gh CLI raw mode"
          installations_response="${gh_response}"$'\n'"HTTP_STATUS:200"
          curl_exit_code=0
        else
          echo "All SSL-based approaches failed. This is likely a network or certificate issue in your environment."
          return 1
        fi
      fi
    else
      # GH API command succeeded, format response to match curl's expected format
      installations_response="${installations_response}"$'\n'"HTTP_STATUS:200"
      curl_exit_code=0
    fi
    
    # Check if curl command still failed after retry
    if [ ${curl_exit_code} -ne 0 ]; then
      echo "Error: curl command failed with exit code ${curl_exit_code}"
      echo "This might indicate network issues or other connection problems"
      return 1
    fi
    
    # Extract HTTP status and response body
    local http_status
    http_status=$(echo "${installations_response}" | grep "HTTP_STATUS:" | cut -d':' -f2)
    installations_response=$(echo "${installations_response}" | sed '/HTTP_STATUS:/d')
    
    echo "HTTP Status: ${http_status}"
    
    # Check HTTP status for common errors
    if [ "${http_status}" = "401" ]; then
      echo "Error: Authentication failed (HTTP 401). Your App ID or private key might be invalid."
      echo "Check that RJ_APP_ID and RJ_APP_PRIVATE_KEY are correctly set."
      echo "First few characters of API response: ${installations_response:0:200}..."
      return 1
    elif [ "${http_status}" != "200" ]; then
      echo "Error: GitHub API returned HTTP ${http_status}"
      echo "First few characters of API response: ${installations_response:0:200}..."
      return 1
    fi
    
    # Check if response is empty
    if [ -z "${installations_response}" ]; then
      echo "Error: Empty response from GitHub API"
      return 1
    fi
    
    # Check if response contains 'message' field (usually error message)
    if echo "${installations_response}" | grep -q '"message"'; then
      local error_message
      error_message=$(echo "${installations_response}" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
      echo "GitHub API error: ${error_message}"
      return 1
    fi
    
    # In GitHub Actions, jq should be available
    installation_id=$(echo "${installations_response}" | jq -r '.[0].id' 2>/dev/null)
    
    # Show number of installations found
    local installations_count
    installations_count=$(echo "${installations_response}" | jq -r 'length' 2>/dev/null || echo "unknown")
    echo "Found ${installations_count} installation(s) of your GitHub App"
    
    # Fallback to grep if jq fails
    if [ -z "${installation_id}" ] || [ "${installation_id}" = "null" ]; then
      echo "Falling back to grep for parsing response"
      installation_id=$(echo "${installations_response}" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
    fi
    
    if [ -z "${installation_id}" ]; then
      echo "Failed to get installation ID for GitHub App."
      echo "This usually happens when:"
      echo "1. The GitHub App is not installed on any accounts/organizations"
      echo "2. The App ID or private key is incorrect"
      echo "3. The API response format has changed"
      echo "First 200 characters of API response: ${installations_response:0:200}..."
      return 1
    fi
    
    echo "Found installation ID: ${installation_id}"
    
    fi  # This closes the outer if [ -z "${installation_id}" ] from line 90
    
    # Use JWT to get installation access token as per GitHub documentation
    echo "Generating installation access token for installation ID: ${installation_id}"
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
