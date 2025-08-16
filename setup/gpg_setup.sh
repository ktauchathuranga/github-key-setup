#!/bin/bash

# GitHub GPG Key Setup Script for Linux - Simplified Version
# Version: 2.5-simplified
# Based on the working Windows PowerShell version
# Description: Simple and reliable GPG key setup for GitHub
# Usage: ./gpg_setup_simple.sh

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Helper functions
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${CYAN}ℹ $1${NC}"; }
print_header() { echo -e "${GREEN}$1${NC}"; }

# Check dependencies
print_info "Checking dependencies..."
if ! command -v git &> /dev/null; then
    print_error "Git is not installed. Please install Git first."
    exit 1
fi

if ! command -v gpg &> /dev/null; then
    print_error "GPG is not installed. Please install GPG first."
    if command -v apt-get &> /dev/null; then
        print_info "Try: sudo apt-get install gnupg"
    elif command -v yum &> /dev/null; then
        print_info "Try: sudo yum install gnupg2"
    elif command -v pacman &> /dev/null; then
        print_info "Try: sudo pacman -S gnupg"
    fi
    exit 1
fi

print_success "Dependencies found"

# Get user information (simplified like Windows version)
echo
print_info "Please provide the following information:"
read -p "Enter your full name (for GPG key, e.g., 'John Doe'): " name
read -p "Enter your email address (associated with GitHub): " email
read -p "Enter a comment for the GPG key (optional): " comment

# Validate input
if [[ -z "$name" ]]; then
    print_error "Name cannot be empty"
    exit 1
fi

if [[ -z "$email" ]]; then
    print_error "Email cannot be empty"
    exit 1
fi

# Get keys before generation (like Windows version)
print_warning "Checking existing keys..."
keys_before=$(gpg --list-secret-keys --keyid-format=long --with-colons 2>/dev/null | grep '^sec:' || true)

# Create GPG batch config file (exactly like Windows version)
temp_file="/tmp/gpg-key-config-$$.txt"
cat > "$temp_file" << EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Name-Real: $name
Name-Email: $email
$([ -n "$comment" ] && echo "Name-Comment: $comment")
Expire-Date: 0
%commit
EOF

# Generate the key
print_warning "Generating GPG key..."
gpg --batch --generate-key "$temp_file"
rm -f "$temp_file"

# Get keys after generation and find the new one (like Windows version)
print_warning "Detecting newly generated key..."
sleep 2  # Brief pause to ensure key is fully processed

keys_after=$(gpg --list-secret-keys --keyid-format=long --with-colons 2>/dev/null | grep '^sec:')

# Find the difference (new key)
if [[ -n "$keys_before" ]]; then
    new_key_line=$(comm -13 <(echo "$keys_before" | sort) <(echo "$keys_after" | sort) | head -1)
else
    new_key_line=$(echo "$keys_after" | head -1)
fi

key_id=""
if [[ -n "$new_key_line" ]]; then
    key_id=$(echo "$new_key_line" | cut -d: -f5)
    print_success "Automatically detected new key ID: $key_id"
else
    # Fallback: Get the most recent key for the email (like Windows version)
    print_warning "Could not detect new key automatically. Finding most recent key for $email..."
    
    # Simple approach: find keys containing our email and get the first one
    key_id=$(gpg --list-secret-keys --keyid-format=long 2>/dev/null | \
        grep -B2 "$email" | \
        grep '^sec' | \
        head -1 | \
        sed -n 's/.*rsa[0-9]*\/\([A-F0-9]*\).*/\1/p')
    
    if [[ -n "$key_id" ]]; then
        print_success "Using most recent key for $email: $key_id"
    fi
fi

# Final fallback (like Windows version)
if [[ -z "$key_id" ]]; then
    print_warning "Could not automatically detect key. Please select manually:"
    gpg --list-secret-keys --keyid-format=long
    echo
    read -p "Enter the key ID (the part after rsa4096/): " key_id
fi

if [[ -z "$key_id" ]]; then
    print_error "Could not find generated key."
    exit 1
fi

print_success "Using Key ID: $key_id"

# Configure Git to use the GPG key (exactly like Windows version)
print_warning "Configuring Git..."
git config --global user.signingkey "$key_id"
git config --global commit.gpgsign true
git config --global user.name "$name"
git config --global user.email "$email"

# Export public key (like Windows version)
echo
print_header "=== Your GPG Public Key ==="
pub_key=$(gpg --armor --export "$key_id" 2>/dev/null)

if [[ -n "$pub_key" ]]; then
    echo -e "${CYAN}$pub_key${NC}"
    
    # Copy to clipboard if possible
    if command -v xclip &> /dev/null; then
        echo "$pub_key" | xclip -selection clipboard 2>/dev/null && \
            print_success "Public GPG key copied to clipboard!" || \
            print_info "Note: Could not copy to clipboard."
    elif command -v pbcopy &> /dev/null; then
        echo "$pub_key" | pbcopy 2>/dev/null && \
            print_success "Public GPG key copied to clipboard!" || \
            print_info "Note: Could not copy to clipboard."
    fi
    
    # Save to file
    echo "$pub_key" > "github_gpg_key_${key_id: -8}.asc"
    print_info "Public key saved to: github_gpg_key_${key_id: -8}.asc"
else
    print_error "Failed to export public key. Please check the key ID: $key_id"
    exit 1
fi

echo
print_info "Go to https://github.com/settings/keys -> New GPG key -> Paste and save."
read -p "Press Enter once done..."

echo
print_success "GPG key setup complete and Git configured."
print_info "Key ID: $key_id"
print_success "You can now sign your commits!"

# Test signing (bonus)
echo
print_info "Testing GPG signing..."
if echo "test" | gpg --clear-sign --default-key "$key_id" >/dev/null 2>&1; then
    print_success "GPG signing test successful!"
else
    print_warning "GPG signing test failed, but key should still work for Git commits"
fi

# Show final configuration
echo
print_header "=== Final Configuration ==="
print_info "Git user name: $(git config --global user.name)"
print_info "Git user email: $(git config --global user.email)"
print_info "Git signing key: $(git config --global user.signingkey)"
print_info "Git commit signing: $(git config --global commit.gpgsign)"
