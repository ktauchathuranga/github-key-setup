#!/bin/bash

# GitHub SSH Key Setup Script for Linux
# This script sets up SSH keys for GitHub authentication

set -e

echo "=== GitHub SSH Key Setup for Linux ==="
echo

# Check if Git is installed
if ! command -v git &> /dev/null; then
    echo "Error: Git is not installed. Please install Git first."
    exit 1
fi

# Get user information
echo "Please provide the following information:"
read -p "Enter your GitHub account name: " github_username
read -p "Enter your email address (associated with GitHub): " email
read -p "Enter a name for your SSH key (default: github_key): " key_name
key_name=${key_name:-github_key}
read -s -p "Enter passphrase for SSH key (press Enter for no passphrase): " passphrase
echo

echo

# Set SSH directory and key paths
ssh_dir="$HOME/.ssh"
private_key="$ssh_dir/$key_name"
public_key="$ssh_dir/$key_name.pub"

# Create .ssh directory if it doesn't exist
mkdir -p "$ssh_dir"
chmod 700 "$ssh_dir"

# Check if key already exists
if [[ -f "$private_key" ]]; then
    echo "SSH key '$key_name' already exists at $private_key"
    read -p "Do you want to overwrite it? (y/N): " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        echo "Exiting without changes."
        exit 0
    fi
fi

# Generate SSH key
echo "Generating SSH key..."
ssh-keygen -t ed25519 -C "$email" -f "$private_key" -N "$passphrase"

# Set proper permissions
chmod 600 "$private_key"
chmod 644 "$public_key"

# Start SSH agent and add key
echo "Starting SSH agent and adding key..."
eval "$(ssh-agent -s)"
ssh-add "$private_key"

# Add SSH config entry
ssh_config="$ssh_dir/config"
if [[ ! -f "$ssh_config" ]] || ! grep -q "Host github.com" "$ssh_config"; then
    echo "Adding GitHub configuration to SSH config..."
    cat >> "$ssh_config" << EOF

# GitHub configuration
Host github.com
    HostName github.com
    User git
    IdentityFile $private_key
    IdentitiesOnly yes
EOF
    chmod 600 "$ssh_config"
fi

# Display public key
echo
echo "=== Your SSH Public Key ==="
echo "Copy the following public key and add it to your GitHub account:"
echo
cat "$public_key"
echo
echo "=== Instructions to add key to GitHub ==="
echo "1. Go to https://github.com/settings/keys"
echo "2. Click 'New SSH key'"
echo "3. Give it a title (e.g., 'My Linux Machine')"
echo "4. Paste the public key above"
echo "5. Click 'Add SSH key'"
echo

# Wait for user to add key to GitHub
read -p "Press Enter after you've added the key to GitHub..."

# Test SSH connection
echo "Testing SSH connection to GitHub..."
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "✓ SSH connection to GitHub successful!"
else
    echo "⚠ SSH connection test failed. Please check:"
    echo "  - The public key was correctly added to GitHub"
    echo "  - Your internet connection is working"
    echo "  - Try running: ssh -T git@github.com"
fi

# Configure Git
echo
echo "Configuring Git..."
git config --global user.name "$github_username"
git config --global user.email "$email"

# Set up Git to use SSH for GitHub
git config --global url."git@github.com:".insteadOf "https://github.com/"

echo
echo "=== Setup Complete! ==="
echo "Your SSH key has been set up and Git is configured."
echo "You can now clone repositories using SSH URLs like:"
echo "  git clone git@github.com:username/repository.git"
echo
echo "Key files created:"
echo "  Private key: $private_key"
echo "  Public key: $public_key"
echo "  SSH config: $ssh_config"
