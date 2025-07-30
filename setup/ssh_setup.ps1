# GitHub SSH Key Setup Script for Windows PowerShell
# This script sets up SSH keys for GitHub authentication

# Ensure script stops on errors
$ErrorActionPreference = "Stop"

Write-Host "=== GitHub SSH Key Setup for Windows ===" -ForegroundColor Green
Write-Host

# Check if Git is installed
try {
    $null = Get-Command git -ErrorAction Stop
} catch {
    Write-Host "Error: Git is not installed. Please install Git first." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Get user information
Write-Host "Please provide the following information:"
$githubUsername = Read-Host "Enter your GitHub account name"
$email = Read-Host "Enter your email address (associated with GitHub)"
$keyName = Read-Host "Enter a name for your SSH key (default: github_key)"
if ([string]::IsNullOrWhiteSpace($keyName)) {
    $keyName = "github_key"
}
$passphrase = Read-Host "Enter passphrase for SSH key (press Enter for no passphrase)" -AsSecureString
$passphraseText = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($passphrase))

Write-Host

# Set SSH directory and key paths
$sshDir = "$env:USERPROFILE\.ssh"
$privateKey = "$sshDir\$keyName"
$publicKey = "$sshDir\$keyName.pub"

# Create .ssh directory if it doesn't exist
if (!(Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

# Check if key already exists
if (Test-Path $privateKey) {
    Write-Host "SSH key '$keyName' already exists at $privateKey" -ForegroundColor Yellow
    $overwrite = Read-Host "Do you want to overwrite it? (y/N)"
    if ($overwrite -notmatch '^[Yy]$') {
        Write-Host "Exiting without changes." -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 0
    }
}

# Generate SSH key
Write-Host "Generating SSH key..." -ForegroundColor Yellow
& ssh-keygen -t ed25519 -C $email -f $privateKey -N $passphraseText

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error generating SSH key." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Start SSH agent service
Write-Host "Starting SSH agent..." -ForegroundColor Yellow
$sshAgentService = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($sshAgentService) {
    if ($sshAgentService.Status -ne "Running") {
        Start-Service ssh-agent
    }
} else {
    # Fallback: start ssh-agent manually
    $env:SSH_AUTH_SOCK = $null
    $env:SSH_AGENT_PID = $null
    $sshAgentOutput = & ssh-agent
    $sshAgentOutput | ForEach-Object {
        if ($_ -match 'SSH_AUTH_SOCK=([^;]+);') {
            $env:SSH_AUTH_SOCK = $matches[1]
        }
        if ($_ -match 'SSH_AGENT_PID=([^;]+);') {
            $env:SSH_AGENT_PID = $matches[1]
        }
    }
}

# Add key to SSH agent
Write-Host "Adding key to SSH agent..." -ForegroundColor Yellow
& ssh-add $privateKey

# Add SSH config entry
$sshConfig = "$sshDir\config"
$githubConfigExists = $false
if (Test-Path $sshConfig) {
    $configContent = Get-Content $sshConfig -Raw
    if ($configContent -match "Host github\.com") {
        $githubConfigExists = $true
    }
}

if (!$githubConfigExists) {
    Write-Host "Adding GitHub configuration to SSH config..." -ForegroundColor Yellow
    $configEntry = @"

# GitHub configuration
Host github.com
    HostName github.com
    User git
    IdentityFile $privateKey
    IdentitiesOnly yes
"@
    Add-Content -Path $sshConfig -Value $configEntry
}

# Display public key
Write-Host
Write-Host "=== Your SSH Public Key ===" -ForegroundColor Green
Write-Host "Copy the following public key and add it to your GitHub account:" -ForegroundColor Yellow
Write-Host
Get-Content $publicKey | Write-Host -ForegroundColor Cyan
Write-Host
Write-Host "=== Instructions to add key to GitHub ===" -ForegroundColor Green
Write-Host "1. Go to https://github.com/settings/keys" -ForegroundColor White
Write-Host "2. Click 'New SSH key'" -ForegroundColor White
Write-Host "3. Give it a title (e.g., 'My Windows Machine')" -ForegroundColor White
Write-Host "4. Paste the public key above" -ForegroundColor White
Write-Host "5. Click 'Add SSH key'" -ForegroundColor White
Write-Host

# Copy public key to clipboard if possible
try {
    Get-Content $publicKey | Set-Clipboard
    Write-Host "✓ Public key has been copied to clipboard!" -ForegroundColor Green
} catch {
    Write-Host "Note: Could not copy to clipboard automatically." -ForegroundColor Yellow
}

# Wait for user to add key to GitHub
Read-Host "Press Enter after you've added the key to GitHub"

# Test SSH connection
Write-Host "Testing SSH connection to GitHub..." -ForegroundColor Yellow
try {
    $sshTest = & ssh -T git@github.com 2>&1
    if ($sshTest -match "successfully authenticated") {
        Write-Host "✓ SSH connection to GitHub successful!" -ForegroundColor Green
    } else {
        Write-Host "⚠ SSH connection test failed. Please check:" -ForegroundColor Yellow
        Write-Host "  - The public key was correctly added to GitHub" -ForegroundColor White
        Write-Host "  - Your internet connection is working" -ForegroundColor White
        Write-Host "  - Try running: ssh -T git@github.com" -ForegroundColor White
    }
} catch {
    Write-Host "⚠ SSH connection test failed. Error: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Configure Git
Write-Host
Write-Host "Configuring Git..." -ForegroundColor Yellow
& git config --global user.name $githubUsername
& git config --global user.email $email
& git config --global init.defaultBranch main
& git config --global alias.co checkout
& git config --global alias.br branch
& git config --global alias.ci commit
& git config --global alias.st status
& git config --global alias.sw switch # Alias for git switch
& git config --global alias.lg "log --oneline --decorate --all --graph" # A more detailed log alias
& git config --global alias.ps "push origin HEAD" # Push current branch to origin
& git config --global alias.pl "pull origin HEAD" # Pull current branch from origin
& git config --global alias.ad "add ." # Stage all changes
& git config --global alias.cm "commit -m" # Commit with a message
& git config --global alias.unstage "reset HEAD --" # Unstage changes
& git config --global alias.last "log -1 HEAD" # Show the last commit


# Set up Git to use SSH for GitHub
& git config --global url."git@github.com:".insteadOf "https://github.com/"

Write-Host
Write-Host "=== Setup Complete! ===" -ForegroundColor Green
Write-Host "Your SSH key has been set up and Git is configured." -ForegroundColor White
Write-Host "You can now clone repositories using SSH URLs like:" -ForegroundColor White
Write-Host "  git clone git@github.com:username/repository.git" -ForegroundColor Cyan
Write-Host
Write-Host "Key files created:" -ForegroundColor White
Write-Host "  Private key: $privateKey" -ForegroundColor Gray
Write-Host "  Public key: $publicKey" -ForegroundColor Gray
Write-Host "  SSH config: $sshConfig" -ForegroundColor Gray
Write-Host
Read-Host "Press Enter to exit"
