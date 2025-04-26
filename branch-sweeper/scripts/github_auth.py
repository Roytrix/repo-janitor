#!/usr/bin/env python3
# filepath: /home/roytrix/Documents/source-code/repo-janitor/branch-sweeper/scripts/github_auth.py

import base64
import json
import os
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Union


def b64_url_encode(data: str) -> str:
    """Base64 URL-safe encode a string."""
    return base64.urlsafe_b64encode(data.encode()).decode().rstrip("=")


def run_command(cmd: List[str], capture_output: bool = True, verbose: bool = False) -> subprocess.CompletedProcess:
    """Run a shell command and return the result."""
    if verbose:
        print(f"DEBUG: Running command: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(
            cmd,
            capture_output=capture_output,
            text=True,
            check=False  # We'll handle errors manually
        )
        return result
    except Exception as e:
        print(f"Error executing command: {e}")
        # Create a fake result object for error handling
        class FakeResult:
            def __init__(self):
                self.returncode = 1
                self.stdout = ""
                self.stderr = str(e)
        return FakeResult()


def get_operating_identity(verbose: bool = False) -> str:
    """Get the current operating identity (app or user)."""
    # When using a GitHub App, identify as the app
    if os.environ.get("RJ_APP_ID"):
        return "app/repo-janitor"
    
    # For GitHub Actions environment
    if os.environ.get("GITHUB_ACTIONS"):
        return "github-actions[bot]"
    
    # Only for personal access token user authentication
    if not os.environ.get("RJ_APP_ID"):
        try:
            result = run_command(["gh", "api", "user", "--jq", ".login"], verbose=verbose)
            if result.returncode == 0 and result.stdout:
                return result.stdout.strip()
        except Exception as e:
            if verbose:
                print(f"Error getting user identity: {e}")
    
    # Fallback for authenticated user with no API access
    return "github-user"


def create_jwt_token(app_id: str, private_key: str, verbose: bool = False) -> str:
    """Create a JWT token for GitHub App authentication."""
    now = int(time.time())
    expiry = now + 600  # 10 minutes expiry
    
    # Create JWT header and payload
    header = {"alg": "RS256", "typ": "JWT"}
    payload = {"iat": now, "exp": expiry, "iss": app_id}
    
    # Base64 encode header and payload
    b64_header = b64_url_encode(json.dumps(header))
    b64_payload = b64_url_encode(json.dumps(payload))
    
    # Create signature using private key
    sig_data = f"{b64_header}.{b64_payload}"
    
    # Write private key to temp file for OpenSSL
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as key_file:
        key_file.write(private_key)
        key_path = key_file.name
    
    try:
        os.chmod(key_path, 0o600)  # Ensure proper permissions
        
        # Use subprocess to run OpenSSL for better compatibility
        cmd = [
            "openssl", "dgst", "-sha256", "-sign", key_path
        ]
        
        result = subprocess.run(
            cmd,
            input=sig_data.encode(),
            capture_output=True,
            check=True
        )
        
        # Base64 URL-safe encode the signature
        signature = base64.urlsafe_b64encode(result.stdout).decode().rstrip("=")
        
    finally:
        # Clean up the temporary file
        os.unlink(key_path)
    
    # Combine to create JWT
    jwt = f"{b64_header}.{b64_payload}.{signature}"
    
    if verbose:
        print(f"JWT token generated successfully (last 4 chars: {jwt[-4:]})")
    
    return jwt


def get_installation_token(jwt_token: str, installation_id: str, verbose: bool = False) -> str:
    """Get an installation token using JWT token."""
    if verbose:
        print(f"Generating installation access token for installation ID: {installation_id}")
    
    # Use GitHub CLI for better error handling
    cmd = [
        "gh", "api", "--method", "POST", 
        f"/app/installations/{installation_id}/access_tokens",
        "--header", f"Authorization: Bearer {jwt_token}"
    ]
    
    result = run_command(cmd, verbose=verbose)
    
    if result.returncode == 0 and result.stdout:
        try:
            # Parse the JSON response to get the token
            response = json.loads(result.stdout)
            token = response.get("token")
            if token:
                if verbose:
                    print("Successfully received installation token")
                return token
        except json.JSONDecodeError:
            if verbose:
                print(f"Error parsing token response: {result.stdout[:100]}...")
    
    if verbose:
        print(f"Failed to get installation token: {result.stderr}")
        print("Falling back to JWT token")
    
    # Fallback to JWT token
    return jwt_token


def check_github_auth() -> bool:
    """Check GitHub authentication and set up tokens if needed."""
    verbose = os.environ.get("DEBUG") == "true"
    
    # Check if we're running in GitHub Actions
    if not os.environ.get("GITHUB_ACTIONS"):
        print("Warning: This script is designed to run in GitHub Actions environment")
    
    # Always prioritize GitHub App authentication
    app_id = os.environ.get("RJ_APP_ID")
    private_key = os.environ.get("RJ_APP_PRIVATE_KEY")
    private_key_path = os.environ.get("RJ_APP_PRIVATE_KEY_PATH")
    github_token = os.environ.get("GITHUB_TOKEN")
    rj_token = os.environ.get("RJ_TOKEN")
    
    if app_id and (private_key or private_key_path):
        print("Using GitHub App authentication (preferred method)")
    elif github_token:
        print("GITHUB_TOKEN detected but not using it - GitHub App authentication is preferred")
        print("Please set RJ_APP_ID and RJ_APP_PRIVATE_KEY/RJ_APP_PRIVATE_KEY_PATH to use GitHub App auth")
        print("Attempting to continue with GitHub App auth setup...")
    
    # GitHub App authentication
    if app_id and (private_key or private_key_path):
        print(f"Using GitHub App authentication with App ID: {app_id}")
        
        # Determine the private key source
        key_content = None
        
        if private_key_path and os.path.isfile(private_key_path):
            print(f"Using private key from path: {private_key_path}")
            with open(private_key_path, "r") as f:
                key_content = f.read()
        elif private_key:
            print("Using private key from environment variable")
            key_content = private_key
        else:
            print("Error: Neither RJ_APP_PRIVATE_KEY nor RJ_APP_PRIVATE_KEY_PATH contains a valid private key")
            return False
            
        # Generate JWT token
        jwt_token = create_jwt_token(app_id, key_content, verbose)
        
        # Use a hardcoded installation ID as in the original script
        installation_id = "64354788"
        print(f"Using fixed installation ID: {installation_id}")
        
        # Get installation token
        token = get_installation_token(jwt_token, installation_id, verbose)
        
        # Set token for GitHub CLI
        os.environ["GITHUB_TOKEN"] = token
        
        # Authenticate with GitHub CLI
        result = run_command(["gh", "auth", "login", "--with-token"], capture_output=False)
        if result.returncode != 0:
            print(f"Error authenticating with GitHub: {result.stderr}")
            return False
            
    # Personal Access Token authentication (fallback)
    elif rj_token:
        print("Using GitHub Personal Access Token authentication")
        os.environ["GITHUB_TOKEN"] = rj_token
        
        # Authenticate with GitHub CLI
        result = run_command(["gh", "auth", "login", "--with-token"], capture_output=False)
        if result.returncode != 0:
            print(f"Error authenticating with GitHub: {result.stderr}")
            return False
            
    else:
        print("Error: No GitHub authentication method available.")
        print("Please set either:")
        print("  - RJ_TOKEN environment variable for PAT authentication")
        print("  - RJ_APP_ID, RJ_PRIVATE_KEY_PATH, and RJ_INSTALLATION_ID for GitHub App authentication")
        return False
        
    # Verify authentication was successful
    result = run_command(["gh", "auth", "status"])
    if result.returncode != 0:
        print("GitHub authentication failed. Please check your credentials.")
        return False
        
    print("GitHub authentication successful.")
    return True


if __name__ == "__main__":
    # When run directly, check authentication
    if check_github_auth():
        print(f"Current identity: {get_operating_identity()}")
        print("Authentication successful")
    else:
        print("Authentication failed")
        exit(1)
