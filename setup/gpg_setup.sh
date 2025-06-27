#!/bin/bash

set -e

echo "=== GitHub GPG Key Setup for Linux ==="

# Check dependencies
command -v gpg >/dev/null 2>&1 || { echo >&2 "GPG is not installed. Please install it first."; exit 1; }
command -v git >/dev/null 2>&1 || { echo >&2 "Git is not installed. Please install it first."; exit 1; }

read -p "Enter your name: " name
read -p "Enter your email (GitHub email): " email
read -p "Enter a comment (optional): " comment

# Create key
echo "Generating GPG key..."

cat >key_config <<EOF
%no-protection
Key-Type: default
Key-Length: 4096
Subkey-Type: default
Name-Real: $name
Name-Email: $email
Name-Comment: $comment
Expire-Date: 0
%commit
EOF

gpg --batch --generate-key key_config
rm -f key_config

# Find key ID
key_id=$(gpg --list-secret-keys --keyid-format=long "$email" | grep 'sec' | awk '{print $2}' | cut -d'/' -f2)

if [ -z "$key_id" ]; then
    echo "Failed to find generated GPG key."
    exit 1
fi

# Show and copy public key
echo
echo "=== Your GPG Public Key ==="
gpg --armor --export "$key_id"
echo
echo "Copy the above key to GitHub > Settings > SSH and GPG Keys > New GPG Key"
echo

# Configure Git
git config --global user.signingkey "$key_id"
git config --global commit.gpgsign true
git config --global user.name "$name"
git config --global user.email "$email"

echo
echo "✓ GPG key created and Git configured to sign commits."

