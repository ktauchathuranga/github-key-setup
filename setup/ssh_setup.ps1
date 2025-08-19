<#
.SYNOPSIS
    GitHub SSH Key Setup Script for Windows PowerShell
.DESCRIPTION
    Sets up SSH keys for GitHub authentication with improved UX and features
.PARAMETER KeyType
    SSH key type (ed25519, rsa, ecdsa) [default: ed25519]
.PARAMETER KeyName
    SSH key name [default: github_key]
.PARAMETER Email
    Email address for the SSH key
.PARAMETER Username
    GitHub username (the one in your profile URL)
.PARAMETER FullName
    Your full name (first and last name for Git commits)
.PARAMETER Passphrase
    Passphrase for the SSH key (empty for no passphrase)
.PARAMETER Force
    Force overwrite existing keys without prompting
.PARAMETER NonInteractive
    Run in non-interactive mode (requires all parameters)
.EXAMPLE
    .\ssh_setup.ps1
    Interactive mode (default)
.EXAMPLE
    .\ssh_setup.ps1 -NonInteractive -Email "user@example.com" -Username "ktauchathuranga" -FullName "Kasun Tharindu" -KeyType "ed25519"
    Non-interactive mode
.EXAMPLE
    .\ssh_setup.ps1 -KeyType rsa -KeyName "my_github_key"
    Generate RSA key with custom name
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "SSH key type (ed25519, rsa, ecdsa)")]
    [ValidateSet("ed25519", "rsa", "ecdsa")]
    [string]$KeyType = "ed25519",
    
    [Parameter(HelpMessage = "SSH key name")]
    [string]$KeyName = "github_key",
    
    [Parameter(HelpMessage = "Email address for the SSH key")]
    [string]$Email = "",
    
    [Parameter(HelpMessage = "GitHub username (the one in your profile URL)")]
    [string]$Username = "",
    
    [Parameter(HelpMessage = "Your full name (first and last name for Git commits)")]
    [string]$FullName = "",
    
    [Parameter(HelpMessage = "Passphrase for the SSH key")]
    [string]$Passphrase = "",
    
    [Parameter(HelpMessage = "Force overwrite existing keys without prompting")]
    [switch]$Force,
    
    [Parameter(HelpMessage = "Run in non-interactive mode")]
    [switch]$NonInteractive,
    
    [Parameter(HelpMessage = "Show help message")]
    [switch]$Help
)

# Script configuration
$Script:Version = "2.3"
$Script:ScriptName = "GitHub SSH Setup"
$ErrorActionPreference = "Stop"

# Helper Functions
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Success { param([string]$Message) Write-ColorOutput "✓ $Message" "Green" }
function Write-Error { param([string]$Message) Write-ColorOutput "✗ $Message" "Red" }
function Write-Warning { param([string]$Message) Write-ColorOutput "⚠ $Message" "Yellow" }
function Write-Info { param([string]$Message) Write-ColorOutput "ℹ $Message" "Cyan" }
function Write-Header { param([string]$Message) Write-ColorOutput $Message "Green" }

function Write-FileWithoutBOM {
    param(
        [string]$Path,
        [string]$Content
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

# Check dependencies
Write-Info "Checking dependencies..."
try { 
    $null = Get-Command git -ErrorAction Stop 
    Write-Success "Git found"
} catch {
    Write-Error "Git is not installed. Please install Git from https://git-scm.com/download/win"
    exit 1
}

try { 
    $null = Get-Command ssh-keygen -ErrorAction Stop 
    Write-Success "SSH found"
} catch {
    Write-Error "SSH is not installed. Please install OpenSSH."
    exit 1
}

# Create SSH directory
$sshDir = "$env:USERPROFILE\.ssh"
if (!(Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    Write-Success "Created SSH directory: $sshDir"
}

# Get user information interactively
Write-Header "=== GitHub SSH Key Setup for Windows ==="
Write-Info "This script will help you set up SSH authentication for GitHub"
Write-Host

# Use current user login as default GitHub username
$defaultUsername = $env:USERNAME
if ($defaultUsername -eq "DELL") {
    $defaultUsername = "ktauchathuranga"  # Use known GitHub username
}

$name = Read-Host "Enter your full name (for Git commits, e.g., 'Ashen Chathuranga')"
$githubUsernamePrompt = "Enter your GitHub username (default: $defaultUsername)"
$githubUsernameInput = Read-Host $githubUsernamePrompt
$githubUsername = if ([string]::IsNullOrWhiteSpace($githubUsernameInput)) { $defaultUsername } else { $githubUsernameInput }
$email = Read-Host "Enter your email address (associated with GitHub)"

$keyNameInput = Read-Host "Enter a name for your SSH key (default: github_key)"
if ([string]::IsNullOrWhiteSpace($keyNameInput)) {
    $keyName = "github_key"
} else {
    $keyName = $keyNameInput
}

# Get passphrase securely
Write-Info "A passphrase adds extra security to your SSH key (recommended)"
$passphraseSecure = Read-Host "Enter passphrase for SSH key (press Enter for no passphrase)" -AsSecureString
$passphraseText = ""
if ($passphraseSecure.Length -gt 0) {
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passphraseSecure)
    try {
        $passphraseText = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    }
}

# Define file paths
$privateKey = "$sshDir\$keyName"
$publicKey = "$sshDir\$keyName.pub"
$sshConfig = "$sshDir\config"

# Check if key already exists
if (Test-Path $privateKey) {
    Write-Warning "SSH key '$keyName' already exists at $privateKey"
    if (-not $Force) {
        $overwrite = Read-Host "Do you want to overwrite it? (y/N)"
        if ($overwrite -notmatch '^[Yy]$') {
            Write-Info "Exiting without changes."
            exit 0
        }
    }
    Write-Info "Overwriting existing key..."
}

# Generate SSH key
Write-Info "Generating $KeyType SSH key..."
try {
    if ([string]::IsNullOrEmpty($passphraseText)) {
        & ssh-keygen -t $KeyType -C $email -f $privateKey -q -N """"
    } else {
        & ssh-keygen -t $KeyType -C $email -f $privateKey -q -N $passphraseText
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "SSH key generated successfully"
    } else {
        Write-Error "Failed to generate SSH key"
        exit 1
    }
} catch {
    Write-Error "Error generating SSH key: $($_.Exception.Message)"
    exit 1
}

# Start SSH agent service
Write-Info "Setting up SSH agent..."
try {
    $sshAgentService = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if ($sshAgentService) {
        if ($sshAgentService.Status -ne "Running") {
            Start-Service ssh-agent
            Write-Success "SSH agent service started"
        } else {
            Write-Success "SSH agent service already running"
        }
    } else {
        Write-Warning "SSH agent service not found, trying to start manually..."
        try {
            $sshAgentOutput = & ssh-agent
            $env:SSH_AUTH_SOCK = $null
            $env:SSH_AGENT_PID = $null
            $sshAgentOutput | ForEach-Object {
                if ($_ -match 'SSH_AUTH_SOCK=([^;]+);') {
                    $env:SSH_AUTH_SOCK = $matches[1]
                }
                if ($_ -match 'SSH_AGENT_PID=([^;]+);') {
                    $env:SSH_AGENT_PID = $matches[1]
                }
            }
            Write-Success "SSH agent started manually"
        } catch {
            Write-Warning "Could not start SSH agent manually"
        }
    }
} catch {
    Write-Warning "Could not start SSH agent: $($_.Exception.Message)"
}

# Add key to SSH agent
Write-Info "Adding key to SSH agent..."
try {
    & ssh-add $privateKey 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Key added to SSH agent"
    } else {
        Write-Warning "Could not add key to SSH agent automatically"
        Write-Info "You can add it manually later with: ssh-add $privateKey"
    }
} catch {
    Write-Warning "Could not add key to SSH agent: $($_.Exception.Message)"
    Write-Info "You can add it manually later with: ssh-add $privateKey"
}

# Create/update SSH config (Windows-compatible, BOM-free)
Write-Info "Configuring SSH client..."
$configContent = @"
# GitHub configuration (added by $Script:ScriptName v$Script:Version on 2025-08-15 14:05:57)
Host github.com
    HostName github.com
    User git
    IdentityFile "$privateKey"
    IdentitiesOnly yes
    AddKeysToAgent yes

"@

try {
    # Check if config exists and read it
    $existingConfig = ""
    if (Test-Path $sshConfig) {
        # Read existing config and remove any BOM
        $rawContent = Get-Content $sshConfig -Raw -Encoding UTF8
        $existingConfig = $rawContent -replace "^\uFEFF", ""  # Remove BOM if present
    }
    
    # Process existing config
    if ($existingConfig -match "Host github\.com") {
        Write-Info "Updating existing GitHub SSH configuration..."
        $lines = $existingConfig -split "`r?`n"
        $newLines = @()
        $skipGithubSection = $false
        
        foreach ($line in $lines) {
            # Skip problematic options
            if ($line -match "^\s*(UseKeychain|UsePasswordStore)") {
                continue
            }
            
            # Handle GitHub section
            if ($line -match "^Host github\.com") {
                $skipGithubSection = $true
                continue
            }
            if ($skipGithubSection -and $line -match "^Host ") {
                $skipGithubSection = $false
            }
            if (-not $skipGithubSection -and $line.Trim() -ne "") {
                $newLines += $line
            }
        }
        
        # Combine cleaned config with new GitHub config
        $cleanConfig = ($newLines | Where-Object { $_.Trim() -ne "" }) -join "`n"
        if ($cleanConfig.Trim() -ne "") {
            $finalConfig = $cleanConfig.TrimEnd() + "`n`n" + $configContent
        } else {
            $finalConfig = $configContent
        }
    } else {
        # Clean existing config of problematic options and append new config
        if ($existingConfig.Trim() -ne "") {
            $lines = $existingConfig -split "`r?`n"
            $cleanLines = $lines | Where-Object { $_ -notmatch "^\s*(UseKeychain|UsePasswordStore)" -and $_.Trim() -ne "" }
            $cleanConfig = ($cleanLines) -join "`n"
            $finalConfig = $cleanConfig.TrimEnd() + "`n`n" + $configContent
        } else {
            $finalConfig = $configContent
        }
    }
    
    # Write config file without BOM
    Write-FileWithoutBOM -Path $sshConfig -Content $finalConfig
    Write-Success "SSH configuration updated (BOM-free)"
} catch {
    Write-Error "Failed to update SSH configuration: $($_.Exception.Message)"
    exit 1
}

# Display public key
Write-Host
Write-Header "=== Your SSH Public Key ==="
Write-Info "Copy the following public key and add it to your GitHub account:"
Write-Host
try {
    $publicKeyContent = Get-Content $publicKey -Raw
    Write-ColorOutput $publicKeyContent.Trim() "Green"
    
    # Copy to clipboard
    try {
        $publicKeyContent.Trim() | Set-Clipboard
        Write-Success "Public key copied to clipboard!"
    } catch {
        Write-Warning "Could not copy to clipboard automatically"
    }
} catch {
    Write-Error "Could not read public key file: $($_.Exception.Message)"
    exit 1
}

Write-Host
Write-Header "=== Instructions to add key to GitHub ==="
Write-Host "1. Go to https://github.com/settings/keys" -ForegroundColor White
Write-Host "2. Click 'New SSH key'" -ForegroundColor White
Write-Host "3. Give it a title (e.g., 'Windows Machine - $env:COMPUTERNAME')" -ForegroundColor White
Write-Host "4. Select 'Authentication Key' as the key type" -ForegroundColor White
Write-Host "5. Paste the public key above" -ForegroundColor White
Write-Host "6. Click 'Add SSH key'" -ForegroundColor White
Write-Host

# Wait for user to add key to GitHub
Read-Host "Press Enter after you have added the key to GitHub"

# Add GitHub to known hosts
Write-Info "Adding GitHub to known hosts..."
$knownHosts = "$sshDir\known_hosts"
try {
    $githubKeys = & ssh-keyscan -t rsa,ed25519 github.com 2>$null
    if ($githubKeys) {
        if (!(Test-Path $knownHosts)) {
            New-Item -Path $knownHosts -ItemType File -Force | Out-Null
        }
        
        # Check if GitHub is already in known_hosts
        $existingHosts = ""
        if (Test-Path $knownHosts) {
            $existingHosts = Get-Content $knownHosts -Raw -ErrorAction SilentlyContinue
        }
        
        if ($existingHosts -notmatch "github\.com") {
            # Write known_hosts without BOM
            $newHostsContent = if ($existingHosts.Trim() -eq "") { $githubKeys } else { $existingHosts.TrimEnd() + "`n" + $githubKeys }
            Write-FileWithoutBOM -Path $knownHosts -Content $newHostsContent
        }
        Write-Success "GitHub added to known hosts"
    }
} catch {
    Write-Warning "Could not automatically add GitHub to known hosts"
}

# Test SSH connection
Write-Host
Write-Info "Testing SSH connection to GitHub..."
try {
    $sshTest = & ssh -o BatchMode=yes -o ConnectTimeout=10 -T git@github.com 2>&1
    $sshTestString = $sshTest -join " "
    
    if ($sshTestString -match "Hi ([^!]+)!" -or $sshTestString -match "successfully authenticated") {
        if ($sshTestString -match "Hi ([^!]+)!") {
            $authenticatedUser = $matches[1]
            Write-Success "SSH connection successful! Authenticated as: $authenticatedUser"
            
            if ($authenticatedUser -ne $githubUsername) {
                Write-Warning "Note: Authenticated username ($authenticatedUser) differs from provided username ($githubUsername)"
                $githubUsername = $authenticatedUser  # Update to actual authenticated username
            }
        } else {
            Write-Success "SSH connection successful!"
        }
    } else {
        Write-Warning "SSH connection test failed"
        Write-Info "Response: $sshTestString"
        Write-Info "Try manually: ssh -T git@github.com"
    }
} catch {
    Write-Warning "SSH connection test failed: $($_.Exception.Message)"
    Write-Info "Try manually: ssh -T git@github.com"
}

# Configure Git
Write-Host
Write-Info "Configuring Git..."
try {
    & git config --global user.name "$name"
    & git config --global user.email "$email"
    & git config --global init.defaultBranch main
    
    # Useful Git aliases
    & git config --global alias.ck checkout
    & git config --global alias.br branch
    & git config --global alias.st status
    & git config --global alias.sw switch
    & git config --global alias.lg "log --oneline --decorate --all --graph"
    & git config --global alias.ps push
    & git config --global alias.pl pull
    & git config --global alias.ad "add ."
    & git config --global alias.cm "commit -m"
    & git config --global alias.unstage "reset HEAD --"
    & git config --global alias.last "log -1 HEAD"
    & git config --global alias.cl clone
    
    # Configure Git to prefer SSH for GitHub
    & git config --global url."git@github.com:".insteadOf "https://github.com/"
    
    Write-Success "Git configured successfully"
} catch {
    Write-Error "Failed to configure Git: $($_.Exception.Message)"
}

# Final test of git clone
Write-Host
Write-Info "Testing git clone functionality..."
try {
    $testResult = & git ls-remote git@github.com:$githubUsername/github-key-setup.git 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Git clone test successful!"
        Write-Info "You can now clone with: git clone git@github.com:$githubUsername/github-key-setup.git"
    } else {
        Write-Warning "Git clone test failed, but SSH connection works"
        Write-Info "Repository might not exist or be private"
    }
} catch {
    Write-Warning "Could not test git clone"
}

# Summary
Write-Host
Write-Header "=== Setup Complete! ==="
Write-Success "SSH key setup completed successfully"
Write-Host

Write-Info "Configuration Summary:"
Write-Host "  • SSH Key Type: $KeyType" -ForegroundColor White
Write-Host "  • Key Name: $keyName" -ForegroundColor White
Write-Host "  • GitHub Username: $githubUsername" -ForegroundColor White
Write-Host "  • Email: $email" -ForegroundColor White
Write-Host "  • Passphrase: $(if ([string]::IsNullOrEmpty($passphraseText)) { 'No' } else { 'Yes' })" -ForegroundColor White
Write-Host

Write-Info "Files created:"
Write-Host "  • Private key: $privateKey" -ForegroundColor Gray
Write-Host "  • Public key: $publicKey" -ForegroundColor Gray
Write-Host "  • SSH config: $sshConfig (BOM-free)" -ForegroundColor Gray
Write-Host

Write-Info "Next steps:"
Write-Host "  • Test connection: ssh -T git@github.com" -ForegroundColor Cyan
Write-Host "  • Clone repositories: git clone git@github.com:$githubUsername/repository.git" -ForegroundColor Cyan
Write-Host "  • Your commits will be attributed to: $name <$email>" -ForegroundColor Cyan
Write-Host

Write-Success "You can now use SSH to authenticate with GitHub!"
