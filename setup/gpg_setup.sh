#!/bin/bash

# GitHub GPG Key Setup Script for Linux
# Version: 2.0
# Author: Enhanced by GitHub Copilot
# Description: Sets up GPG keys for GitHub commit signing with improved UX and features
# Usage: ./github_gpg_setup.sh [OPTIONS]

set -e

# Script version and configuration
VERSION="2.0"
SCRIPT_NAME="GitHub GPG Setup"
DEFAULT_KEY_LENGTH="4096"
DEFAULT_KEY_TYPE="RSA"

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
KEY_LENGTH="$DEFAULT_KEY_LENGTH"
EMAIL=""
FULL_NAME=""
COMMENT=""
EXPIRE_DATE="0"
FORCE_OVERWRITE=false
PASSPHRASE=""

# Error codes
readonly ERR_GENERAL=1
readonly ERR_DEPENDENCY=2
readonly ERR_USER_INPUT=3
readonly ERR_GPG_SETUP=4
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
    -t, --key-type TYPE     GPG key type (RSA, ECC) [default: RSA]
    -l, --key-length LEN    Key length for RSA (2048, 4096) [default: 4096]
    -e, --email EMAIL       Email address for the GPG key
    -f, --full-name NAME    Your full name (first and last name)
    -c, --comment TEXT      Comment for the GPG key (optional)
    -x, --expire-date DATE  Expiration date (0 for no expiration, or YYYY-MM-DD)
    -p, --passphrase PASS   Passphrase for the GPG key (recommended)
    --force                 Force overwrite existing keys without prompting

${BOLD}EXAMPLES:${NC}
    Interactive mode (default):
        $0

    Non-interactive mode:
        $0 -n -e "user@example.com" -f "John Doe" -t "RSA" -l "4096"

    Generate ECC key with comment:
        $0 -t ECC -c "Work laptop key"

    Generate key with expiration:
        $0 -x "2026-12-31" -p "my_secure_passphrase"

${BOLD}SUPPORTED KEY TYPES:${NC}
    RSA        - RSA keys (2048 or 4096 bit) - widely compatible
    ECC        - Elliptic Curve keys (faster, smaller) - modern

${BOLD}KEY EXPIRATION:${NC}
    0          - No expiration (default)
    YYYY-MM-DD - Specific expiration date (e.g., 2026-12-31)
    Nd         - Expire in N days (e.g., 365d)
    Nw         - Expire in N weeks (e.g., 52w)
    Nm         - Expire in N months (e.g., 12m)
    Ny         - Expire in N years (e.g., 2y)

${BOLD}SECURITY NOTES:${NC}
    - Using a passphrase is highly recommended for security
    - Key expiration helps maintain good security hygiene
    - RSA 4096-bit keys provide excellent security
    - ECC keys are faster and smaller but require modern GPG

${BOLD}TROUBLESHOOTING:${NC}
    If GPG key generation fails:
    1. Ensure you have sufficient entropy: ls -la /dev/random
    2. Install rng-tools if needed: sudo apt-get install rng-tools
    3. Check GPG version: gpg --version
    4. Verify GPG agent is running: gpg-connect-agent /bye
    
    If Git signing fails:
    1. Verify GPG key exists: gpg --list-secret-keys
    2. Check Git configuration: git config --list | grep gpg
    3. Test signing: echo "test" | gpg --clearsign
    4. Verify GPG agent: echo RELOADAGENT | gpg-connect-agent

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
    local required_commands=("gpg" "git")
    
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
            print_info "Try: sudo apt-get install gnupg git"
        elif command -v yum &> /dev/null; then
            print_info "Try: sudo yum install gnupg2 git"
        elif command -v pacman &> /dev/null; then
            print_info "Try: sudo pacman -S gnupg git"
        fi
        
        exit $ERR_DEPENDENCY
    fi
    
    print_success "All dependencies found"
    
    # Check GPG and Git versions
    local gpg_version=$(gpg --version | head -1)
    local git_version=$(git --version)
    print_info "GPG: $gpg_version"
    print_info "Git: $git_version"
    
    # Check GPG agent
    if pgrep -x "gpg-agent" > /dev/null; then
        print_success "GPG agent is running"
    else
        print_warning "GPG agent not detected - will be started automatically"
    fi
}

# Check entropy for key generation
check_entropy() {
    if [[ -r /proc/sys/kernel/random/entropy_avail ]]; then
        local entropy=$(cat /proc/sys/kernel/random/entropy_avail)
        print_info "System entropy: $entropy bits"
        
        if [[ $entropy -lt 1000 ]]; then
            print_warning "Low system entropy detected ($entropy bits)"
            print_info "Key generation may be slow. Consider:"
            echo "  - Moving the mouse and typing randomly"
            echo "  - Installing rng-tools: sudo apt-get install rng-tools"
            echo "  - Using hardware RNG if available"
        else
            print_success "Sufficient entropy available"
        fi
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
    
    print_header "=== GitHub GPG Key Setup for Linux ==="
    echo
    
    print_info "This script will help you set up GPG key signing for GitHub commits"
    echo
    
    # Get full name
    while [[ -z "$FULL_NAME" ]]; do
        read -p "Enter your full name (for GPG key, e.g., 'John Doe'): " FULL_NAME
        if [[ -z "$FULL_NAME" ]]; then
            print_error "Full name cannot be empty"
        fi
    done
    
    # Get email
    while [[ -z "$EMAIL" ]]; do
        read -p "Enter your email address (associated with GitHub): " EMAIL
        if [[ -z "$EMAIL" ]]; then
            print_error "Email address cannot be empty"
        fi
    done
    
    # Get optional comment
    read -p "Enter a comment for the GPG key (optional, e.g., 'Work laptop'): " COMMENT
    
    # Get key type
    echo
    print_info "Available GPG key types:"
    echo "  1) RSA (recommended - widely compatible)"
    echo "  2) ECC (modern - faster, smaller keys)"
    echo
    
    while true; do
        read -p "Select key type (1-2, default: 1): " key_choice
        case ${key_choice:-1} in
            1) KEY_TYPE="RSA"; break ;;
            2) KEY_TYPE="ECC"; break ;;
            *) print_error "Invalid choice. Please select 1 or 2." ;;
        esac
    done
    
    # Get key length for RSA
    if [[ "$KEY_TYPE" = "RSA" ]]; then
        echo
        print_info "Available RSA key lengths:"
        echo "  1) 4096 bits (recommended - high security)"
        echo "  2) 2048 bits (standard - good compatibility)"
        echo
        
        while true; do
            read -p "Select key length (1-2, default: 1): " length_choice
            case ${length_choice:-1} in
                1) KEY_LENGTH="4096"; break ;;
                2) KEY_LENGTH="2048"; break ;;
                *) print_error "Invalid choice. Please select 1 or 2." ;;
            esac
        done
    fi
    
    # Get expiration date
    echo
    print_info "Key expiration options:"
    echo "  1) No expiration (keys never expire)"
    echo "  2) 1 year from now"
    echo "  3) 2 years from now"
    echo "  4) Custom date/period"
    echo
    
    while true; do
        read -p "Select expiration (1-4, default: 1): " expire_choice
        case ${expire_choice:-1} in
            1) EXPIRE_DATE="0"; break ;;
            2) EXPIRE_DATE="1y"; break ;;
            3) EXPIRE_DATE="2y"; break ;;
            4) 
                read -p "Enter custom expiration (YYYY-MM-DD, Ny, Nm, Nw, Nd, or 0): " EXPIRE_DATE
                break 
                ;;
            *) print_error "Invalid choice. Please select 1-4." ;;
        esac
    done
    
    # Get passphrase
    echo
    print_info "Passphrase Protection:"
    print_info "A passphrase protects your private key from unauthorized use"
    read -s -p "Enter passphrase for GPG key (press Enter for no passphrase, NOT recommended): " PASSPHRASE
    echo
    
    if [[ -z "$PASSPHRASE" ]]; then
        print_warning "No passphrase set - your private key will be unprotected!"
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
    [[ -z "$FULL_NAME" ]] && missing_params+=("full-name (-f)")
    
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
# GPG Setup Functions
#==============================================================================

# Check for existing GPG keys
check_existing_keys() {
    print_info "Checking for existing GPG keys..."
    
    local existing_keys=$(gpg --list-secret-keys --keyid-format=long "$EMAIL" 2>/dev/null | grep 'sec' | wc -l)
    
    if [[ $existing_keys -gt 0 ]]; then
        print_warning "Found existing GPG key(s) for $EMAIL:"
        gpg --list-secret-keys --keyid-format=long "$EMAIL" 2>/dev/null | grep -A 1 'sec'
        echo
        
        if [[ "$FORCE_OVERWRITE" = true ]]; then
            print_info "Force overwrite enabled, continuing with new key generation..."
            return 0
        fi
        
        if [[ "$INTERACTIVE_MODE" = true ]]; then
            read -p "Do you want to create a new key anyway? (y/N): " create_new
            if [[ ! "$create_new" =~ ^[Yy]$ ]]; then
                print_info "Exiting without creating new key"
                exit 0
            fi
        else
            print_error "Existing key found and force overwrite not enabled"
            print_info "Use --force to create a new key anyway"
            exit $ERR_GPG_SETUP
        fi
    else
        print_success "No existing GPG keys found for $EMAIL"
    fi
}

# Generate GPG key configuration
generate_key_config() {
    local temp_config=$(mktemp)
    
    print_info "Creating GPG key configuration..."
    
    if [[ "$KEY_TYPE" = "RSA" ]]; then
        cat > "$temp_config" << EOF
%echo Generating GPG key...
Key-Type: RSA
Key-Length: $KEY_LENGTH
Subkey-Type: RSA
Subkey-Length: $KEY_LENGTH
Name-Real: $FULL_NAME
Name-Email: $EMAIL
$([ -n "$COMMENT" ] && echo "Name-Comment: $COMMENT")
Expire-Date: $EXPIRE_DATE
$([ -n "$PASSPHRASE" ] && echo "Passphrase: $PASSPHRASE" || echo "%no-protection")
%commit
%echo GPG key generation complete
EOF
    else  # ECC
        cat > "$temp_config" << EOF
%echo Generating ECC GPG key...
Key-Type: EDDSA
Key-Curve: Ed25519
Subkey-Type: ECDH
Subkey-Curve: Curve25519
Name-Real: $FULL_NAME
Name-Email: $EMAIL
$([ -n "$COMMENT" ] && echo "Name-Comment: $COMMENT")
Expire-Date: $EXPIRE_DATE
$([ -n "$PASSPHRASE" ] && echo "Passphrase: $PASSPHRASE" || echo "%no-protection")
%commit
%echo ECC GPG key generation complete
EOF
    fi
    
    echo "$temp_config"
}

# Generate GPG key
generate_gpg_key() {
    print_info "Generating $KEY_TYPE GPG key..."
    
    local key_config=$(generate_key_config)
    
    # Generate the key with progress indication
    {
        gpg --batch --generate-key "$key_config" 2>&1
    } &
    
    local keygen_pid=$!
    show_progress $keygen_pid "Generating GPG key (this may take a while)"
    
    if wait $keygen_pid; then
        print_success "GPG key generated successfully"
    else
        print_error "Failed to generate GPG key"
        rm -f "$key_config"
        exit $ERR_GPG_SETUP
    fi
    
    # Clean up temporary config file
    rm -f "$key_config"
}

# Get the generated key ID
get_key_id() {
    print_info "Finding generated GPG key..."
    
    local key_id=$(gpg --list-secret-keys --keyid-format=long "$EMAIL" 2>/dev/null | grep 'sec' | tail -1 | awk '{print $2}' | cut -d'/' -f2)
    
    if [[ -z "$key_id" ]]; then
        print_error "Failed to find generated GPG key"
        exit $ERR_GPG_SETUP
    fi
    
    print_success "GPG key ID: $key_id"
    echo "$key_id"
}

#==============================================================================
# GitHub Integration Functions
#==============================================================================

# Display public key for GitHub
display_public_key() {
    local key_id=$1
    
    echo
    print_header "=== Your GPG Public Key ==="
    print_info "Copy the following public key and add it to your GitHub account:"
    echo
    
    # Export and display the public key
    local public_key=$(gpg --armor --export "$key_id" 2>/dev/null)
    if [[ -n "$public_key" ]]; then
        print_color "$GREEN" "$public_key"
        
        # Try to copy to clipboard if xclip is available
        if command -v xclip &> /dev/null; then
            echo "$public_key" | xclip -selection clipboard 2>/dev/null || true
            print_success "Public key copied to clipboard!"
        elif command -v pbcopy &> /dev/null; then
            echo "$public_key" | pbcopy 2>/dev/null || true
            print_success "Public key copied to clipboard!"
        else
            print_info "Install xclip or pbcopy for automatic clipboard copying"
        fi
    else
        print_error "Failed to export public key"
        exit $ERR_GPG_SETUP
    fi
    
    echo
    print_header "=== Instructions to add key to GitHub ==="
    echo "1. Go to https://github.com/settings/keys"
    echo "2. Click 'New GPG key'"
    echo "3. Paste the public key above"
    echo "4. Click 'Add GPG key'"
    echo
}

# Test GPG signing
test_gpg_signing() {
    local key_id=$1
    
    if [[ "$INTERACTIVE_MODE" = true ]]; then
        read -p "Press Enter after you've added the key to GitHub..."
    else
        print_info "Waiting 5 seconds for key to be added to GitHub..."
        sleep 5
    fi
    
    echo
    print_info "Testing GPG signing..."
    
    # Test signing capability
    local test_message="Test GPG signing - $(date)"
    if echo "$test_message" | gpg --clearsign --default-key "$key_id" >/dev/null 2>&1; then
        print_success "GPG signing test successful!"
    else
        print_warning "GPG signing test failed"
        print_info "This might be due to:"
        echo "  - Missing or incorrect passphrase"
        echo "  - GPG agent not running properly"
        echo "  - Permission issues with GPG"
        
        if [[ "$INTERACTIVE_MODE" = true ]]; then
            read -p "Continue with Git configuration anyway? (y/N): " continue_setup
            if [[ ! "$continue_setup" =~ ^[Yy]$ ]]; then
                exit $ERR_GPG_SETUP
            fi
        fi
    fi
}

#==============================================================================
# Git Configuration Functions
#==============================================================================

# Configure Git for GPG signing
configure_git_signing() {
    local key_id=$1
    
    print_info "Configuring Git for GPG signing..."
    
    try {
        # Configure Git to use the GPG key
        git config --global user.signingkey "$key_id" || {
            print_error "Failed to set Git signing key"
            exit $ERR_GENERAL
        }
        
        # Enable automatic commit signing
        git config --global commit.gpgsign true || {
            print_error "Failed to enable commit signing"
            exit $ERR_GENERAL
        }
        
        # Configure user information
        git config --global user.name "$FULL_NAME" || {
            print_error "Failed to set Git user name"
            exit $ERR_GENERAL
        }
        
        git config --global user.email "$EMAIL" || {
            print_error "Failed to set Git email"
            exit $ERR_GENERAL
        }
        
        # Optional: Enable tag signing
        read -p "Enable automatic tag signing? (Y/n): " enable_tag_signing
        if [[ ! "$enable_tag_signing" =~ ^[Nn]$ ]]; then
            git config --global tag.gpgsign true || {
                print_warning "Failed to enable tag signing"
            }
        fi
        
        print_success "Git configuration completed"
        print_info "Git commits will be signed with key: $key_id"
        print_info "Git commits will be attributed to: $FULL_NAME <$EMAIL>"
    }
}

# Test Git signing with a sample commit
test_git_signing() {
    print_info "Testing Git commit signing..."
    
    # Create a temporary repository for testing
    local test_dir="/tmp/gpg_signing_test_$$"
    
    {
        mkdir -p "$test_dir"
        cd "$test_dir"
        git init --quiet
        echo "# GPG Signing Test" > README.md
        git add README.md
        git commit -m "Test GPG signing" --quiet
        
        # Check if the commit was signed
        local commit_signature=$(git log --show-signature -1 --pretty=format:"%G?" 2>/dev/null)
        cd - >/dev/null
        rm -rf "$test_dir"
        
        if [[ "$commit_signature" = "G" ]]; then
            echo "success"
        else
            echo "failed"
        fi
    } &
    
    local test_pid=$!
    show_progress $test_pid "Testing Git commit signing"
    local result=$(wait $test_pid; echo $?)
    
    if [[ $result -eq 0 ]]; then
        print_success "Git commit signing working correctly"
    else
        print_warning "Git commit signing test failed"
        print_info "Your commits may not show as verified on GitHub"
        print_info "Check GPG configuration with: git config --list | grep gpg"
    fi
}

#==============================================================================
# Summary and Cleanup Functions
#==============================================================================

# Display setup summary
show_summary() {
    local key_id=$1
    
    echo
    print_header "=== Setup Complete! ==="
    print_success "Your GPG key has been set up and Git is configured for signing"
    echo
    
    print_info "Configuration Summary:"
    echo "  • GPG Key Type: $KEY_TYPE"
    if [[ "$KEY_TYPE" = "RSA" ]]; then
        echo "  • Key Length: $KEY_LENGTH bits"
    fi
    echo "  • Key ID: $key_id"
    echo "  • Full Name: $FULL_NAME"
    echo "  • Email: $EMAIL"
    echo "  • Comment: ${COMMENT:-"(none)"}"
    echo "  • Expiration: $([ "$EXPIRE_DATE" = "0" ] && echo "Never" || echo "$EXPIRE_DATE")"
    echo "  • Passphrase: $([ -n "$PASSPHRASE" ] && echo "Yes" || echo "No")"
    echo
    
    print_info "Git Configuration:"
    echo "  • Signing Key: $key_id"
    echo "  • Commit Signing: Enabled"
    echo "  • Tag Signing: $(git config --global tag.gpgsign 2>/dev/null && echo "Enabled" || echo "Disabled")"
    echo "  • Author Name: $FULL_NAME"
    echo "  • Author Email: $EMAIL"
    echo
    
    print_info "Next Steps:"
    echo "  • Your commits will now be automatically signed"
    echo "  • Signed commits will show as 'Verified' on GitHub"
    echo "  • Back up your GPG key: gpg --export-secret-keys $key_id > backup.gpg"
    echo "  • Share your public key: gpg --armor --export $key_id"
    echo
    
    print_info "Useful Commands:"
    echo "  • List GPG keys: gpg --list-secret-keys"
    echo "  • Test signing: echo 'test' | gpg --clearsign"
    echo "  • Git config check: git config --list | grep gpg"
    echo "  • Verify last commit: git log --show-signature -1"
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
            -l|--key-length)
                KEY_LENGTH="$2"
                shift 2
                ;;
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            -f|--full-name)
                FULL_NAME="$2"
                shift 2
                ;;
            -c|--comment)
                COMMENT="$2"
                shift 2
                ;;
            -x|--expire-date)
                EXPIRE_DATE="$2"
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
        RSA|ECC) ;;
        *)
            print_error "Invalid key type: $KEY_TYPE"
            print_info "Supported types: RSA, ECC"
            exit $ERR_USER_INPUT
            ;;
    esac
    
    # Validate key length for RSA
    if [[ "$KEY_TYPE" = "RSA" ]]; then
        case "$KEY_LENGTH" in
            2048|4096) ;;
            *)
                print_error "Invalid RSA key length: $KEY_LENGTH"
                print_info "Supported lengths: 2048, 4096"
                exit $ERR_USER_INPUT
                ;;
        esac
    fi
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
    check_entropy
    
    # Get user input
    get_user_input
    
    # GPG key setup
    check_existing_keys
    generate_gpg_key
    local key_id=$(get_key_id)
    
    # GitHub integration
    display_public_key "$key_id"
    test_gpg_signing "$key_id"
    
    # Git configuration
    configure_git_signing "$key_id"
    test_git_signing
    
    # Show summary
    show_summary "$key_id"
}

# Run main function with all arguments
main "$@"
