#!/bin/bash

# GitHub SSH Key Setup Script for Linux
# Version: 2.1
# Author: Enhanced by GitHub Copilot
# Description: Sets up SSH keys for GitHub authentication with improved UX and username handling
# Usage: ./github_ssh_setup.sh [OPTIONS]

set -e

# Script version and configuration
VERSION="2.1"
SCRIPT_NAME="GitHub SSH Setup"
DEFAULT_KEY_TYPE="ed25519"
DEFAULT_KEY_NAME="github_key"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Global variables
INTERACTIVE_MODE=true
KEY_TYPE="$DEFAULT_KEY_TYPE"
KEY_NAME="$DEFAULT_KEY_NAME"
EMAIL=""
GITHUB_USERNAME=""
USER_FULL_NAME=""
PASSPHRASE=""
FORCE_OVERWRITE=false

# Error codes
readonly ERR_GENERAL=1
readonly ERR_DEPENDENCY=2
readonly ERR_USER_INPUT=3
readonly ERR_SSH_SETUP=4
readonly ERR_GITHUB_CONNECTION=5

#==============================================================================
# Helper Functions
#==============================================================================

# Print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Print status messages
print_success() { print_color "$GREEN" "✓ $1"; }
print_error() { print_color "$RED" "✗ $1"; }
print_warning() { print_color "$YELLOW" "⚠ $1"; }
print_info() { print_color "$BLUE" "ℹ $1"; }
print_header() { print_color "$BOLD" "$1"; }

# Progress indicator
show_progress() {
    local pid=$1
    local message=$2
    local spinner='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    echo -n "$message "
    while kill -0 $pid 2>/dev/null; do
        printf "\b${spinner:$i:1}"
        i=$(((i+1) % ${#spinner}))
        sleep 0.1
    done
    printf "\b"
}

# Display help
show_help() {
    cat << EOF
${BOLD}${SCRIPT_NAME} v${VERSION}${NC}

${BOLD}USAGE:${NC}
    $0 [OPTIONS]

${BOLD}OPTIONS:${NC}
    -h, --help              Show this help message
    -v, --version           Show version information
    -n, --non-interactive   Run in non-interactive mode (requires all options)
    -t, --key-type TYPE     SSH key type (ed25519, rsa, ecdsa) [default: ed25519]
    -k, --key-name NAME     SSH key name [default: github_key]
    -e, --email EMAIL       Email address for the SSH key
    -u, --username USER     GitHub username (the one in your profile URL)
    -f, --full-name NAME    Your full name (first and last name for Git commits)
    -p, --passphrase PASS   Passphrase for the SSH key (empty for no passphrase)
    --force                 Force overwrite existing keys without prompting

${BOLD}EXAMPLES:${NC}
    Interactive mode (default):
        $0

    Non-interactive mode:
        $0 -n -e "user@example.com" -u "ktauchathuranga" -f "Ashen Chathuranga" -t "ed25519"

    Generate RSA key with custom name:
        $0 -t rsa -k "my_github_key"

${BOLD}SUPPORTED KEY TYPES:${NC}
    ed25519    - Recommended (fast, secure, small keys)
    rsa        - 4096-bit RSA keys (widely compatible)
    ecdsa      - ECDSA P-256 keys (good balance)

${BOLD}IMPORTANT - TWO DIFFERENT NAMES:${NC}
    GitHub Username: Your unique identifier in GitHub URLs
    • Example: If your profile is github.com/ktauchathuranga, username is "ktauchathuranga"
    • Used for: Repository URLs, authentication, cloning
    • Format: git@github.com:USERNAME/repository.git
    
    Full Name: Your actual name for Git commit attribution
    • Example: "Ashen Chathuranga" (your real name)
    • Used for: Git commit author information
    • Shows up in: Git history, GitHub commit displays

${BOLD}TROUBLESHOOTING:${NC}
    If SSH connection fails:
    1. Verify the public key was added to GitHub correctly
    2. Check your internet connection
    3. Run: ssh -T git@github.com -v (for verbose output)
    4. Ensure SSH agent is running: ssh-agent -s
    
    If Git operations fail:
    1. Verify Git is configured: git config --list
    2. Test with: git clone git@github.com:USERNAME/repository.git
    3. Check SSH config: cat ~/.ssh/config

EOF
}

# Display version
show_version() {
    echo "${SCRIPT_NAME} v${VERSION}"
}

#==============================================================================
# System Check Functions
#==============================================================================

# Check if running on supported system
check_system() {
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        print_warning "This script is optimized for Linux systems"
        print_info "Detected system: $OSTYPE"
    fi
    
    # Check for common Linux distributions
    if [[ -f /etc/os-release ]]; then
        local distro=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
        print_info "Detected Linux distribution: $distro"
    fi
}

# Check dependencies
check_dependencies() {
    print_info "Checking system dependencies..."
    
    local missing_deps=()
    
    # Check for required commands
    local required_commands=("git" "ssh-keygen" "ssh" "ssh-add")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_info "Please install the missing packages and try again"
        
        # Suggest installation commands for common distributions
        if command -v apt-get &> /dev/null; then
            print_info "Try: sudo apt-get install git openssh-client"
        elif command -v yum &> /dev/null; then
            print_info "Try: sudo yum install git openssh-clients"
        elif command -v pacman &> /dev/null; then
            print_info "Try: sudo pacman -S git openssh"
        fi
        
        exit $ERR_DEPENDENCY
    fi
    
    print_success "All dependencies found"
    
    # Check SSH client version
    local ssh_version=$(ssh -V 2>&1 | head -1)
    print_info "SSH client: $ssh_version"
}

# Check SSH agent
check_ssh_agent() {
    print_info "Checking SSH agent status..."
    
    if [[ -z "$SSH_AUTH_SOCK" ]]; then
        print_warning "SSH agent not detected"
        return 1
    fi
    
    if ! ssh-add -l &>/dev/null; then
        print_warning "SSH agent not responding properly"
        return 1
    fi
    
    print_success "SSH agent is running"
    return 0
}

#==============================================================================
# GitHub Username Validation Functions
#==============================================================================

# Validate GitHub username format
validate_github_username() {
    local username=$1
    
    # GitHub username rules:
    # - Only alphanumeric characters and hyphens
    # - Cannot start or end with hyphen
    # - Cannot have consecutive hyphens
    # - Maximum 39 characters
    # - Minimum 1 character
    
    if [[ ! "$username" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
        return 1
    fi
    
    if [[ ${#username} -gt 39 || ${#username} -lt 1 ]]; then
        return 1
    fi
    
    if [[ "$username" == *"--"* ]]; then
        return 1
    fi
    
    return 0
}

# Check if GitHub username exists (basic check)
check_github_username_exists() {
    local username=$1
    
    print_info "Verifying GitHub username exists..."
    
    # Try to access the GitHub user profile
    if command -v curl &> /dev/null; then
        local response=$(curl -s -o /dev/null -w "%{http_code}" "https://api.github.com/users/$username" 2>/dev/null)
        if [[ "$response" = "200" ]]; then
            print_success "GitHub username '$username' verified"
            return 0
        elif [[ "$response" = "404" ]]; then
            print_warning "GitHub username '$username' not found"
            return 1
        else
            print_warning "Could not verify username (network issue or rate limit)"
            return 0  # Don't fail setup due to network issues
        fi
    elif command -v wget &> /dev/null; then
        if wget -q --spider "https://api.github.com/users/$username" 2>/dev/null; then
            print_success "GitHub username '$username' verified"
            return 0
        else
            print_warning "Could not verify GitHub username (may not exist or network issue)"
            return 1
        fi
    else
        print_warning "Cannot verify username - curl or wget not available"
        return 0  # Don't fail setup due to missing tools
    fi
}

# Suggest username based on current user or email
suggest_github_username() {
    local suggestions=()
    
    # Get current system username
    local current_user=$(whoami 2>/dev/null || echo "")
    if [[ -n "$current_user" && "$current_user" != "root" ]]; then
        suggestions+=("$current_user")
    fi
    
    # Extract from email if provided
    if [[ -n "$EMAIL" ]]; then
        local email_user=$(echo "$EMAIL" | cut -d'@' -f1)
        if [[ "$email_user" != "$current_user" ]]; then
            suggestions+=("$email_user")
        fi
    fi
    
    # Add some variations
    if [[ -n "$current_user" ]]; then
        suggestions+=("${current_user}-dev" "${current_user}dev")
    fi
    
    if [[ ${#suggestions[@]} -gt 0 ]]; then
        echo
        print_info "Suggested GitHub usernames based on your system:"
        for i in "${!suggestions[@]}"; do
            echo "  $((i+1))) ${suggestions[$i]}"
        done
        echo
    fi
}

#==============================================================================
# User Input Functions
#==============================================================================

# Get user input with validation
get_user_input() {
    if [[ "$INTERACTIVE_MODE" = false ]]; then
        validate_required_params
        return 0
    fi
    
    print_header "=== GitHub SSH Key Setup for Linux ==="
    echo
    
    print_info "This script will help you set up SSH authentication for GitHub"
    echo
    
    # Get full name first
    while [[ -z "$USER_FULL_NAME" ]]; do
        read -p "Enter your full name (for Git commits, e.g., 'Ashen Chathuranga'): " USER_FULL_NAME
        if [[ -z "$USER_FULL_NAME" ]]; then
            print_error "Full name cannot be empty"
        fi
    done
    
    # Get email
    while [[ -z "$EMAIL" ]]; do
        read -p "Enter your email address (associated with GitHub): " EMAIL
        if [[ -z "$EMAIL" ]]; then
            print_error "Email address cannot be empty"
        elif [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_error "Please enter a valid email address"
            EMAIL=""
        fi
    done
    
    # Get GitHub username with enhanced validation
    echo
    print_header "=== GitHub Username Setup ==="
    print_info "Your GitHub username is the unique identifier in your profile URL"
    print_info "Example: If your profile is github.com/ktauchathuranga, your username is 'ktauchathuranga'"
    print_info "This is different from your full name and display name"
    
    # Suggest usernames
    suggest_github_username
    
    while [[ -z "$GITHUB_USERNAME" ]]; do
        read -p "Enter your GitHub username (from your profile URL): " GITHUB_USERNAME
        
        if [[ -z "$GITHUB_USERNAME" ]]; then
            print_error "GitHub username cannot be empty"
            continue
        fi
        
        # Validate format
        if ! validate_github_username "$GITHUB_USERNAME"; then
            print_error "Invalid GitHub username format"
            print_info "GitHub usernames must:"
            echo "  • Only contain alphanumeric characters and hyphens"
            echo "  • Not start or end with a hyphen"
            echo "  • Not contain consecutive hyphens"
            echo "  • Be 1-39 characters long"
            GITHUB_USERNAME=""
            continue
        fi
        
        # Check if username exists
        if check_github_username_exists "$GITHUB_USERNAME"; then
            print_info "You entered: $GITHUB_USERNAME"
            print_info "Your repositories will be accessed as: git@github.com:$GITHUB_USERNAME/repository.git"
            
            read -p "Is this correct? (Y/n): " confirm_username
            if [[ "$confirm_username" =~ ^[Nn]$ ]]; then
                GITHUB_USERNAME=""
                continue
            fi
            break
        else
            print_warning "The username '$GITHUB_USERNAME' may not exist on GitHub"
            read -p "Do you want to continue anyway? (y/N): " continue_anyway
            if [[ "$continue_anyway" =~ ^[Yy]$ ]]; then
                break
            else
                GITHUB_USERNAME=""
            fi
        fi
    done
    
    # Get key name
    echo
    read -p "Enter a name for your SSH key (default: $DEFAULT_KEY_NAME): " input_key_name
    KEY_NAME=${input_key_name:-$DEFAULT_KEY_NAME}
    
    # Get key type
    echo
    print_info "Available SSH key types:"
    echo "  1) ed25519 (recommended - fast, secure, small)"
    echo "  2) rsa (4096-bit - widely compatible)"
    echo "  3) ecdsa (P-256 - good balance)"
    echo
    
    while true; do
        read -p "Select key type (1-3, default: 1): " key_choice
        case ${key_choice:-1} in
            1) KEY_TYPE="ed25519"; break ;;
            2) KEY_TYPE="rsa"; break ;;
            3) KEY_TYPE="ecdsa"; break ;;
            *) print_error "Invalid choice. Please select 1, 2, or 3." ;;
        esac
    done
    
    # Get passphrase
    echo
    print_info "SSH Key Passphrase:"
    print_info "A passphrase adds an extra layer of security to your SSH key"
    read -s -p "Enter passphrase for SSH key (press Enter for no passphrase): " PASSPHRASE
    echo
    
    if [[ -z "$PASSPHRASE" ]]; then
        print_warning "No passphrase set - your SSH key will be unprotected"
        read -p "Are you sure you want to continue without a passphrase? (y/N): " confirm_no_pass
        if [[ ! "$confirm_no_pass" =~ ^[Yy]$ ]]; then
            print_info "Please run the script again and set a passphrase"
            exit 0
        fi
    fi
    
    echo
}

# Validate required parameters for non-interactive mode
validate_required_params() {
    local missing_params=()
    
    [[ -z "$EMAIL" ]] && missing_params+=("email (-e)")
    [[ -z "$GITHUB_USERNAME" ]] && missing_params+=("username (-u)")
    [[ -z "$USER_FULL_NAME" ]] && missing_params+=("full-name (-f)")
    
    if [[ ${#missing_params[@]} -gt 0 ]]; then
        print_error "Missing required parameters for non-interactive mode:"
        for param in "${missing_params[@]}"; do
            echo "  - $param"
        done
        echo
        show_help
        exit $ERR_USER_INPUT
    fi
    
    # Validate username format in non-interactive mode
    if ! validate_github_username "$GITHUB_USERNAME"; then
        print_error "Invalid GitHub username format: $GITHUB_USERNAME"
        print_info "GitHub usernames must only contain alphanumeric characters and hyphens"
        exit $ERR_USER_INPUT
    fi
}

#==============================================================================
# SSH Setup Functions
#==============================================================================

# Set up SSH directory and paths
setup_ssh_paths() {
    ssh_dir="$HOME/.ssh"
    private_key="$ssh_dir/$KEY_NAME"
    public_key="$ssh_dir/$KEY_NAME.pub"
    
    # Create .ssh directory if it doesn't exist
    if [[ ! -d "$ssh_dir" ]]; then
        print_info "Creating SSH directory: $ssh_dir"
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
    fi
}

# Check and handle existing keys
handle_existing_keys() {
    if [[ -f "$private_key" ]]; then
        print_warning "SSH key '$KEY_NAME' already exists at $private_key"
        
        if [[ "$FORCE_OVERWRITE" = true ]]; then
            print_info "Force overwrite enabled, proceeding..."
            return 0
        fi
        
        if [[ "$INTERACTIVE_MODE" = true ]]; then
            read -p "Do you want to overwrite it? (y/N): " overwrite
            if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
                print_info "Exiting without changes"
                exit 0
            fi
        else
            print_error "Key exists and force overwrite not enabled"
            print_info "Use --force to overwrite existing keys"
            exit $ERR_SSH_SETUP
        fi
    fi
}

# Generate SSH key based on type
generate_ssh_key() {
    print_info "Generating $KEY_TYPE SSH key..."
    
    local key_opts=()
    
    case "$KEY_TYPE" in
        "ed25519")
            key_opts=("-t" "ed25519" "-C" "$EMAIL")
            ;;
        "rsa")
            key_opts=("-t" "rsa" "-b" "4096" "-C" "$EMAIL")
            ;;
        "ecdsa")
            key_opts=("-t" "ecdsa" "-b" "256" "-C" "$EMAIL")
            ;;
        *)
            print_error "Unsupported key type: $KEY_TYPE"
            exit $ERR_SSH_SETUP
            ;;
    esac
    
    # Generate the key
    {
        ssh-keygen "${key_opts[@]}" -f "$private_key" -N "$PASSPHRASE"
    } &
    
    local keygen_pid=$!
    show_progress $keygen_pid "Generating SSH key"
    wait $keygen_pid
    
    if [[ $? -eq 0 ]]; then
        print_success "SSH key generated successfully"
    else
        print_error "Failed to generate SSH key"
        exit $ERR_SSH_SETUP
    fi
    
    # Set proper permissions
    chmod 600 "$private_key"
    chmod 644 "$public_key"
}

# Setup SSH agent and add key
setup_ssh_agent() {
    print_info "Setting up SSH agent..."
    
    # Start SSH agent if not running
    if ! check_ssh_agent; then
        print_info "Starting SSH agent..."
        eval "$(ssh-agent -s)" || {
            print_error "Failed to start SSH agent"
            exit $ERR_SSH_SETUP
        }
        print_success "SSH agent started"
    fi
    
    # Add key to SSH agent
    print_info "Adding key to SSH agent..."
    if ssh-add "$private_key" 2>/dev/null; then
        print_success "Key added to SSH agent"
    else
        print_error "Failed to add key to SSH agent"
        exit $ERR_SSH_SETUP
    fi
}

# Configure SSH config file
configure_ssh_config() {
    local ssh_config="$ssh_dir/config"
    
    print_info "Configuring SSH client..."
    
    # Check if GitHub config already exists
    if [[ -f "$ssh_config" ]] && grep -q "Host github.com" "$ssh_config"; then
        print_warning "GitHub SSH configuration already exists in $ssh_config"
        
        if [[ "$INTERACTIVE_MODE" = true ]] && [[ "$FORCE_OVERWRITE" = false ]]; then
            read -p "Do you want to update it? (y/N): " update_config
            if [[ ! "$update_config" =~ ^[Yy]$ ]]; then
                print_info "Skipping SSH config update"
                return 0
            fi
        fi
    fi
    
    # Add GitHub configuration
    print_info "Adding GitHub configuration to SSH config..."
    cat >> "$ssh_config" << EOF

# GitHub configuration (added by $SCRIPT_NAME v$VERSION)
Host github.com
    HostName github.com
    User git
    IdentityFile $private_key
    IdentitiesOnly yes
    AddKeysToAgent yes
EOF
    
    chmod 600 "$ssh_config"
    print_success "SSH configuration updated"
}

#==============================================================================
# GitHub Integration Functions
#==============================================================================

# Display public key for GitHub
display_public_key() {
    echo
    print_header "=== Your SSH Public Key ==="
    print_info "Copy the following public key and add it to your GitHub account:"
    echo
    print_color "$GREEN" "$(cat "$public_key")"
    echo
    
    # Try to copy to clipboard if available
    if command -v xclip &> /dev/null; then
        cat "$public_key" | xclip -selection clipboard 2>/dev/null && print_success "Public key copied to clipboard!"
    elif command -v pbcopy &> /dev/null; then
        cat "$public_key" | pbcopy 2>/dev/null && print_success "Public key copied to clipboard!"
    else
        print_info "Install xclip or pbcopy for automatic clipboard copying"
    fi
    
    echo
    print_header "=== Instructions to add key to GitHub ==="
    echo "1. Go to https://github.com/settings/keys"
    echo "2. Click 'New SSH key'"
    echo "3. Give it a title (e.g., 'My Linux Machine - $(hostname)')"
    echo "4. Select 'Authentication Key' as the key type"
    echo "5. Paste the public key above"
    echo "6. Click 'Add SSH key'"
    echo
}

# Test GitHub SSH connection with improved username detection
test_github_connection() {
    if [[ "$INTERACTIVE_MODE" = true ]]; then
        read -p "Press Enter after you've added the key to GitHub..."
    else
        print_info "Waiting 5 seconds for key to be added to GitHub..."
        sleep 5
    fi
    
    echo
    print_info "Testing SSH connection to GitHub..."
    
    # Test SSH connection with timeout
    local ssh_test_output
    ssh_test_output=$(timeout 10 ssh -T git@github.com 2>&1) || true
    
    if echo "$ssh_test_output" | grep -q "successfully authenticated"; then
        print_success "SSH connection to GitHub successful!"
        
        # Extract username from output
        local authenticated_user=$(echo "$ssh_test_output" | grep -o "Hi [^!]*" | cut -d' ' -f2)
        if [[ -n "$authenticated_user" ]]; then
            print_success "Authenticated as: $authenticated_user"
            
            # Verify username matches
            if [[ "$authenticated_user" != "$GITHUB_USERNAME" ]]; then
                print_warning "Authenticated username differs from provided username"
                print_info "  • Provided username: $GITHUB_USERNAME"
                print_info "  • Authenticated as: $authenticated_user"
                print_info "This could mean:"
                echo "    • You entered the wrong username initially"
                echo "    • You're using a different SSH key"
                echo "    • Your GitHub username has changed"
                echo
                
                if [[ "$INTERACTIVE_MODE" = true ]]; then
                    read -p "Update to use the authenticated username ($authenticated_user)? (Y/n): " use_auth_user
                    if [[ ! "$use_auth_user" =~ ^[Nn]$ ]]; then
                        print_info "Updating username to: $authenticated_user"
                        GITHUB_USERNAME="$authenticated_user"
                    fi
                else
                    print_info "Non-interactive mode: keeping original username"
                fi
            fi
        fi
    else
        print_error "SSH connection test failed"
        print_info "SSH output: $ssh_test_output"
        print_warning "Please check:"
        echo "  - The public key was correctly added to GitHub"
        echo "  - Your internet connection is working"
        echo "  - GitHub is accessible from your network"
        echo "  - Try running: ssh -T git@github.com -v"
        echo
        
        if [[ "$INTERACTIVE_MODE" = true ]]; then
            read -p "Continue with Git configuration anyway? (y/N): " continue_setup
            if [[ ! "$continue_setup" =~ ^[Yy]$ ]]; then
                exit $ERR_GITHUB_CONNECTION
            fi
        else
            exit $ERR_GITHUB_CONNECTION
        fi
    fi
}

#==============================================================================
# Git Configuration Functions
#==============================================================================

# Configure Git settings
configure_git() {
    print_info "Configuring Git..."
    
    # Basic Git configuration - Use full name for commits, not username
    git config --global user.name "$USER_FULL_NAME" || {
        print_error "Failed to set Git user name"
        exit $ERR_GENERAL
    }
    
    git config --global user.email "$EMAIL" || {
        print_error "Failed to set Git email"
        exit $ERR_GENERAL
    }
    
    git config --global init.defaultBranch main || {
        print_warning "Failed to set default branch (older Git version?)"
    }
    
    # Git aliases
    print_info "Setting up Git aliases..."
    git config --global alias.co checkout
    git config --global alias.br branch
    git config --global alias.ci commit
    git config --global alias.st status
    git config --global alias.sw switch
    git config --global alias.lg "log --oneline --decorate --all --graph"
    git config --global alias.ps "push origin HEAD"
    git config --global alias.pl "pull origin HEAD"
    git config --global alias.ad "add ."
    git config --global alias.cm "commit -m"
    git config --global alias.unstage "reset HEAD --"
    git config --global alias.last "log -1 HEAD"
    
    # Configure Git to use SSH for GitHub
    git config --global url."git@github.com:".insteadOf "https://github.com/" || {
        print_warning "Failed to configure Git SSH URL rewriting"
    }
    
    print_success "Git configuration completed"
    print_info "Git commits will be attributed to: $USER_FULL_NAME <$EMAIL>"
    print_info "GitHub repositories will use SSH with username: $GITHUB_USERNAME"
}

# Test Git operations
test_git_operations() {
    print_info "Testing Git operations with SSH..."
    
    # Create a temporary directory for testing
    local test_dir="/tmp/github_ssh_test_$$"
    
    {
        # Test cloning a public repository using the verified username
        local test_repo="git@github.com:octocat/Hello-World.git"
        if [[ "$GITHUB_USERNAME" != "octocat" ]]; then
            # Use a known public repo for testing
            test_repo="git@github.com:octocat/Hello-World.git"
        fi
        
        git clone "$test_repo" "$test_dir" &>/dev/null
        rm -rf "$test_dir"
    } &
    
    local git_test_pid=$!
    show_progress $git_test_pid "Testing Git clone operation"
    
    if wait $git_test_pid; then
        print_success "Git operations working correctly with SSH"
    else
        print_warning "Git SSH test failed - this might be normal if the test repository is unavailable"
        print_info "Try cloning your own repository to verify:"
        print_info "  git clone git@github.com:$GITHUB_USERNAME/repository.git"
    fi
}

#==============================================================================
# Summary and Cleanup Functions
#==============================================================================

# Display setup summary
show_summary() {
    echo
    print_header "=== Setup Complete! ==="
    print_success "Your SSH key has been set up and Git is configured"
    echo
    
    print_info "Configuration Summary:"
    echo "  • SSH Key Type: $KEY_TYPE"
    echo "  • Key Name: $KEY_NAME"
    echo "  • GitHub Username: $GITHUB_USERNAME"
    echo "  • Full Name (for commits): $USER_FULL_NAME"
    echo "  • Email: $EMAIL"
    echo "  • Passphrase: $([ -n "$PASSPHRASE" ] && echo "Yes" || echo "No")"
    echo
    
    print_info "Files Created:"
    echo "  • Private key: $private_key"
    echo "  • Public key: $public_key"
    echo "  • SSH config: $ssh_dir/config"
    echo
    
    print_info "Git Configuration:"
    echo "  • Author Name: $USER_FULL_NAME"
    echo "  • Author Email: $EMAIL"
    echo "  • Default Branch: main"
    echo "  • SSH URL Rewriting: Enabled"
    echo
    
    print_info "Repository Access:"
    echo "  • Clone repositories: git clone git@github.com:$GITHUB_USERNAME/repository.git"
    echo "  • Push to repositories: git push origin main"
    echo "  • Your commits will show as: $USER_FULL_NAME"
    echo
    
    print_info "Useful Commands:"
    echo "  • Test GitHub connection: ssh -T git@github.com"
    echo "  • View Git configuration: git config --global --list"
    echo "  • Add key to agent: ssh-add $private_key"
    echo "  • List loaded keys: ssh-add -l"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -n|--non-interactive)
                INTERACTIVE_MODE=false
                shift
                ;;
            -t|--key-type)
                KEY_TYPE="$2"
                shift 2
                ;;
            -k|--key-name)
                KEY_NAME="$2"
                shift 2
                ;;
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            -u|--username)
                GITHUB_USERNAME="$2"
                shift 2
                ;;
            -f|--full-name)
                USER_FULL_NAME="$2"
                shift 2
                ;;
            -p|--passphrase)
                PASSPHRASE="$2"
                shift 2
                ;;
            --force)
                FORCE_OVERWRITE=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit $ERR_USER_INPUT
                ;;
        esac
    done
    
    # Validate key type
    case "$KEY_TYPE" in
        ed25519|rsa|ecdsa) ;;
        *)
            print_error "Invalid key type: $KEY_TYPE"
            print_info "Supported types: ed25519, rsa, ecdsa"
            exit $ERR_USER_INPUT
            ;;
    esac
}

#==============================================================================
# Main Function
#==============================================================================

main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # System checks
    check_system
    check_dependencies
    
    # Get user input
    get_user_input
    
    # Setup SSH
    setup_ssh_paths
    handle_existing_keys
    generate_ssh_key
    setup_ssh_agent
    configure_ssh_config
    
    # GitHub integration
    display_public_key
    test_github_connection
    
    # Git configuration
    configure_git
    test_git_operations
    
    # Show summary
    show_summary
}

# Run main function with all arguments
main "$@"
