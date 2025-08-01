#!/bin/bash

# GitHub SSH Key Setup Script for Linux
# Version: 2.0
# Author: Enhanced by GitHub Copilot
# Description: Sets up SSH keys for GitHub authentication with improved UX and features
# Usage: ./github_ssh_setup.sh [OPTIONS]

set -e

# Script version and configuration
VERSION="2.0"
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
        $0 -n -e "user@example.com" -u "ktauchathuranga" -f "Kasun Tharindu" -t "ed25519"

    Generate RSA key with custom name:
        $0 -t rsa -k "my_github_key"

${BOLD}SUPPORTED KEY TYPES:${NC}
    ed25519    - Recommended (fast, secure, small keys)
    rsa        - 4096-bit RSA keys (widely compatible)
    ecdsa      - ECDSA P-256 keys (good balance)

${BOLD}NOTE:${NC}
    Two different names are used:
    - GitHub Username: The unique identifier in your GitHub URL (github.com/username)
    - Full Name: Your actual name used for Git commit attribution (e.g., "John Doe")

${BOLD}TROUBLESHOOTING:${NC}
    If SSH connection fails:
    1. Verify the public key was added to GitHub correctly
    2. Check your internet connection
    3. Run: ssh -T git@github.com -v (for verbose output)
    4. Ensure SSH agent is running: ssh-agent -s
    
    If Git operations fail:
    1. Verify Git is configured: git config --list
    2. Test with: git clone git@github.com:octocat/Hello-World.git /tmp/test
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
        read -p "Enter your full name (for Git commits, e.g., 'John Doe'): " USER_FULL_NAME
        if [[ -z "$USER_FULL_NAME" ]]; then
            print_error "Full name cannot be empty"
        fi
    done
    
    # Get GitHub username with clear explanation
    print_info "GitHub Username Information:"
    print_info "Your GitHub username is the unique identifier in your profile URL"
    print_info "Example: If your profile is github.com/ktauchathuranga, your username is 'ktauchathuranga'"
    print_info "This is different from your full name and display name"
    echo
    
    while [[ -z "$GITHUB_USERNAME" ]]; do
        read -p "Enter your GitHub username (from your profile URL): " GITHUB_USERNAME
        if [[ -z "$GITHUB_USERNAME" ]]; then
            print_error "GitHub username cannot be empty"
        else
            print_info "You entered: $GITHUB_USERNAME"
            print_info "Your repositories will be accessed as: git@github.com:$GITHUB_USERNAME/repository.git"
            read -p "Is this correct? (Y/n): " confirm_username
            if [[ "$confirm_username" =~ ^[Nn]$ ]]; then
                GITHUB_USERNAME=""
            fi
        fi
    done
    
    # Get email
    while [[ -z "$EMAIL" ]]; do
        read -p "Enter your email address (associated with GitHub): " EMAIL
        if [[ -z "$EMAIL" ]]; then
            print_error "Email address cannot be empty"
        fi
    done
    
    # Get key name
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
    read -s -p "Enter passphrase for SSH key (press Enter for no passphrase): " PASSPHRASE
    echo
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
    print_header "=== Instructions to add key to GitHub ==="
    echo "1. Go to https://github.com/settings/keys"
    echo "2. Click 'New SSH key'"
    echo "3. Give it a title (e.g., 'My Linux Machine - $(hostname)')"
    echo "4. Select 'Authentication Key' as the key type"
    echo "5. Paste the public key above"
    echo "6. Click 'Add SSH key'"
    echo
}

# Test GitHub SSH connection
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
                print_warning "Authenticated username ($authenticated_user) differs from provided username ($GITHUB_USERNAME)"
                print_info "This could mean:"
                echo "  • You entered the wrong username initially"
                echo "  • You're using a different SSH key"
                echo "  • Your GitHub username has changed"
                
                if [[ "$INTERACTIVE_MODE" = true ]]; then
                    read -p "Continue with the authenticated username ($authenticated_user)? (Y/n): " use_auth_user
                    if [[ ! "$use_auth_user" =~ ^[Nn]$ ]]; then
                        print_info "Updating username to: $authenticated_user"
                        GITHUB_USERNAME="$authenticated_user"
                    fi
                fi
            fi
        fi
    else
        print_error "SSH connection test failed"
        print_info "Output: $ssh_test_output"
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
}

# Test Git operations
test_git_operations() {
    print_info "Testing Git operations with SSH..."
    
    # Create a temporary directory for testing
    local test_dir="/tmp/github_ssh_test_$$"
    
    {
        # Test cloning a public repository
        git clone git@github.com:octocat/Hello-World.git "$test_dir" &>/dev/null
        rm -rf "$test_dir"
    } &
    
    local git_test_pid=$!
    show_progress $git_test_pid "Testing Git clone operation"
    
    if wait $git_test_pid; then
        print_success "Git operations working correctly with SSH"
    else
        print_warning "Git SSH test failed - this might be normal if the test repository is unavailable"
        print_info "Try cloning your own repository to verify: git clone git@github.com:$GITHUB_USERNAME/repository.git"
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
    
    print_info "Next Steps:"
    echo "  • Clone repositories: git clone git@github.com:$GITHUB_USERNAME/repository.git"
    echo "  • Push to repositories: git push origin main"
    echo "  • Check SSH agent: ssh-add -l"
    echo
    
    print_info "Useful Commands:"
    echo "  • Test GitHub connection: ssh -T git@github.com"
    echo "  • View Git configuration: git config --global --list"
    echo "  • Add key to agent: ssh-add $private_key"
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
