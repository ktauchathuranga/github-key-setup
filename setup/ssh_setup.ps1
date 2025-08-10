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
    .\github_ssh_setup.ps1
    Interactive mode (default)
.EXAMPLE
    .\github_ssh_setup.ps1 -NonInteractive -Email "user@example.com" -Username "ktauchathuranga" -FullName "Kasun Tharindu" -KeyType "ed25519"
    Non-interactive mode
.EXAMPLE
    .\github_ssh_setup.ps1 -KeyType rsa -KeyName "my_github_key"
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
$Script:Version = "2.0"
$Script:ScriptName = "GitHub SSH Setup"
$ErrorActionPreference = "Stop"

# Global variables
$script:InteractiveMode = -not $NonInteractive
$script:SshDir = "$env:USERPROFILE\.ssh"
$script:PrivateKey = ""
$script:PublicKey = ""
$script:SshConfig = ""

#==============================================================================
# Helper Functions (MUST BE DEFINED FIRST)
#==============================================================================

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

function Show-Progress {
    param(
        [string]$Activity,
        [scriptblock]$ScriptBlock
    )
    
    $job = Start-Job -ScriptBlock $ScriptBlock
    $spinner = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
    $i = 0
    
    Write-Host "$Activity " -NoNewline
    while ($job.State -eq 'Running') {
        Write-Host "`b$($spinner[$i])" -NoNewline
        $i = ($i + 1) % $spinner.Length
        Start-Sleep -Milliseconds 100
    }
    Write-Host "`b " -NoNewline
    
    $result = Receive-Job $job
    Remove-Job $job
    
    return $result
}

function Show-Help {
    Write-Header "$Script:ScriptName v$Script:Version"
    Write-Host
    Write-Header "USAGE:"
    Write-Host "    .\github_ssh_setup.ps1 [OPTIONS]"
    Write-Host
    Write-Header "PARAMETERS:"
    Write-Host "    -KeyType TYPE           SSH key type (ed25519, rsa, ecdsa) [default: ed25519]"
    Write-Host "    -KeyName NAME           SSH key name [default: github_key]"
    Write-Host "    -Email EMAIL            Email address for the SSH key"
    Write-Host "    -Username USER          GitHub username (the one in your profile URL)"
    Write-Host "    -FullName NAME          Your full name (first and last name for Git commits)"
    Write-Host "    -Passphrase PASS        Passphrase for the SSH key (empty for no passphrase)"
    Write-Host "    -Force                  Force overwrite existing keys without prompting"
    Write-Host "    -NonInteractive         Run in non-interactive mode (requires all parameters)"
    Write-Host "    -Help                   Show this help message"
    Write-Host
    Write-Header "EXAMPLES:"
    Write-Host "    Interactive mode (default):"
    Write-Host "        .\github_ssh_setup.ps1"
    Write-Host
    Write-Host "    Non-interactive mode:"
    Write-Host "        .\github_ssh_setup.ps1 -NonInteractive -Email 'user@example.com' -Username 'ktauchathuranga' -FullName 'Kasun Tharindu' -KeyType 'ed25519'"
    Write-Host
    Write-Host "    Generate RSA key with custom name:"
    Write-Host "        .\github_ssh_setup.ps1 -KeyType rsa -KeyName 'my_github_key'"
    Write-Host
    Write-Header "SUPPORTED KEY TYPES:"
    Write-Host "    ed25519    - Recommended (fast, secure, small keys)"
    Write-Host "    rsa        - 4096-bit RSA keys (widely compatible)"
    Write-Host "    ecdsa      - ECDSA P-256 keys (good balance)"
    Write-Host
    Write-Header "NOTE:"
    Write-Host "    Two different names are used:"
    Write-Host "    - GitHub Username: The unique identifier in your GitHub URL (github.com/username)"
    Write-Host "    - Full Name: Your actual name used for Git commit attribution (e.g., 'John Doe')"
    Write-Host
}

#==============================================================================
# System Check Functions
#==============================================================================

function Test-SystemCompatibility {
    Write-Info "Checking system compatibility..."
    
    # Check Windows version
    $osVersion = [System.Environment]::OSVersion.Version
    Write-Info "Windows Version: $($osVersion.Major).$($osVersion.Minor)"
    
    # Check PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    Write-Info "PowerShell Version: $psVersion"
    
    if ($psVersion.Major -lt 5) {
        Write-Warning "PowerShell 5.0 or higher is recommended"
    }
}

function Test-Dependencies {
    Write-Info "Checking system dependencies..."
    
    $missingDeps = @()
    
    # Check for required commands
    $requiredCommands = @("git", "ssh-keygen", "ssh", "ssh-add")
    
    foreach ($cmd in $requiredCommands) {
        try {
            $null = Get-Command $cmd -ErrorAction Stop
        }
        catch {
            $missingDeps += $cmd
        }
    }
    
    if ($missingDeps.Count -gt 0) {
        Write-Error "Missing required dependencies: $($missingDeps -join ', ')"
        Write-Info "Please install the missing packages:"
        Write-Info "- Git: https://git-scm.com/download/win"
        Write-Info "- OpenSSH: Install via Windows Features or download from GitHub"
        
        if ($script:InteractiveMode) {
            Read-Host "Press Enter to exit"
        }
        exit 2
    }
    
    Write-Success "All dependencies found"
    
    # Check versions
    try {
        $gitVersion = & git --version 2>$null
        Write-Info "Git: $gitVersion"
        
        $sshVersion = & ssh -V 2>&1 | Select-Object -First 1
        Write-Info "SSH: $sshVersion"
    }
    catch {
        Write-Warning "Could not determine version information"
    }
}

function Test-SshAgent {
    Write-Info "Checking SSH agent status..."
    
    # Check if ssh-agent service exists and is running
    $sshAgentService = Get-Service ssh-agent -ErrorAction SilentlyContinue
    
    if ($sshAgentService) {
        if ($sshAgentService.Status -eq "Running") {
            Write-Success "SSH agent service is running"
            return $true
        }
        else {
            Write-Warning "SSH agent service exists but is not running"
            return $false
        }
    }
    else {
        Write-Warning "SSH agent service not found"
        return $false
    }
}

#==============================================================================
# User Input Functions
#==============================================================================

function Test-RequiredParameters {
    $missingParams = @()
    
    if ([string]::IsNullOrWhiteSpace($Email)) { $missingParams += "Email (-Email)" }
    if ([string]::IsNullOrWhiteSpace($Username)) { $missingParams += "Username (-Username)" }
    if ([string]::IsNullOrWhiteSpace($FullName)) { $missingParams += "FullName (-FullName)" }
    
    if ($missingParams.Count -gt 0) {
        Write-Error "Missing required parameters for non-interactive mode:"
        $missingParams | ForEach-Object { Write-Host "  - $_" }
        Write-Host
        Show-Help
        exit 3
    }
    
    # Set script variables from parameters
    $script:Email = $Email
    $script:Username = $Username
    $script:FullName = $FullName
    $script:KeyName = $KeyName
    $script:KeyType = $KeyType
    $script:Passphrase = $Passphrase
}

function Get-UserInput {
    if (-not $script:InteractiveMode) {
        Test-RequiredParameters
        return
    }
    
    Write-Header "=== GitHub SSH Key Setup for Windows ==="
    Write-Host
    
    Write-Info "This script will help you set up SSH authentication for GitHub"
    Write-Host
    
    # Get full name first
    while ([string]::IsNullOrWhiteSpace($script:FullName)) {
        $script:FullName = Read-Host "Enter your full name (for Git commits, e.g., 'John Doe')"
        if ([string]::IsNullOrWhiteSpace($script:FullName)) {
            Write-Error "Full name cannot be empty"
        }
    }
    
    # Get GitHub username with clear explanation
    Write-Info "GitHub Username Information:"
    Write-Info "Your GitHub username is the unique identifier in your profile URL"
    Write-Info "Example: If your profile is github.com/ktauchathuranga, your username is 'ktauchathuranga'"
    Write-Info "This is different from your full name and display name"
    Write-Host
    
    while ([string]::IsNullOrWhiteSpace($script:Username)) {
        $script:Username = Read-Host "Enter your GitHub username (from your profile URL)"
        if ([string]::IsNullOrWhiteSpace($script:Username)) {
            Write-Error "GitHub username cannot be empty"
        }
        else {
            Write-Info "You entered: $script:Username"
            Write-Info "Your repositories will be accessed as: git@github.com:$script:Username/repository.git"
            $confirm = Read-Host "Is this correct? (Y/n)"
            if ($confirm -match '^[Nn]$') {
                $script:Username = ""
            }
        }
    }
    
    # Get email
    while ([string]::IsNullOrWhiteSpace($script:Email)) {
        $script:Email = Read-Host "Enter your email address (associated with GitHub)"
        if ([string]::IsNullOrWhiteSpace($script:Email)) {
            Write-Error "Email address cannot be empty"
        }
    }
    
    # Get key name
    $inputKeyName = Read-Host "Enter a name for your SSH key (default: $KeyName)"
    if (-not [string]::IsNullOrWhiteSpace($inputKeyName)) {
        $script:KeyName = $inputKeyName
    }
    
    # Get key type
    Write-Host
    Write-Info "Available SSH key types:"
    Write-Host "  1) ed25519 (recommended - fast, secure, small)"
    Write-Host "  2) rsa (4096-bit - widely compatible)"
    Write-Host "  3) ecdsa (P-256 - good balance)"
    Write-Host
    
    do {
        $keyChoice = Read-Host "Select key type (1-3, default: 1)"
        switch ($keyChoice) {
            { $_ -eq "" -or $_ -eq "1" } { $script:KeyType = "ed25519"; $validChoice = $true }
            "2" { $script:KeyType = "rsa"; $validChoice = $true }
            "3" { $script:KeyType = "ecdsa"; $validChoice = $true }
            default { Write-Error "Invalid choice. Please select 1, 2, or 3."; $validChoice = $false }
        }
    } while (-not $validChoice)
    
    # Get passphrase
    $securePassphrase = Read-Host "Enter passphrase for SSH key (press Enter for no passphrase)" -AsSecureString
    $script:Passphrase = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassphrase))
    Write-Host
}

#==============================================================================
# SSH Setup Functions
#==============================================================================

function Initialize-SshPaths {
    $script:PrivateKey = "$script:SshDir\$script:KeyName"
    $script:PublicKey = "$script:SshDir\$script:KeyName.pub"
    $script:SshConfig = "$script:SshDir\config"
    
    # Create .ssh directory if it doesn't exist
    if (!(Test-Path $script:SshDir)) {
        Write-Info "Creating SSH directory: $script:SshDir"
        New-Item -ItemType Directory -Path $script:SshDir -Force | Out-Null
    }
}

function Test-ExistingKeys {
    if (Test-Path $script:PrivateKey) {
        Write-Warning "SSH key '$script:KeyName' already exists at $script:PrivateKey"
        
        if ($Force) {
            Write-Info "Force overwrite enabled, proceeding..."
            return
        }
        
        if ($script:InteractiveMode) {
            $overwrite = Read-Host "Do you want to overwrite it? (y/N)"
            if ($overwrite -notmatch '^[Yy]$') {
                Write-Info "Exiting without changes"
                if ($script:InteractiveMode) {
                    Read-Host "Press Enter to exit"
                }
                exit 0
            }
        }
        else {
            Write-Error "Key exists and force overwrite not enabled"
            Write-Info "Use -Force to overwrite existing keys"
            exit 4
        }
    }
}

function New-SshKey {
    Write-Info "Generating $script:KeyType SSH key..."
    
    $keyOpts = @()
    
    switch ($script:KeyType) {
        "ed25519" { $keyOpts = @("-t", "ed25519", "-C", $script:Email) }
        "rsa" { $keyOpts = @("-t", "rsa", "-b", "4096", "-C", $script:Email) }
        "ecdsa" { $keyOpts = @("-t", "ecdsa", "-b", "256", "-C", $script:Email) }
        default {
            Write-Error "Unsupported key type: $script:KeyType"
            exit 4
        }
    }
    
    # Generate the key
    try {
        $result = Show-Progress "Generating SSH key" {
            & ssh-keygen @keyOpts -f $script:PrivateKey -N $script:Passphrase 2>&1
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "SSH key generated successfully"
        }
        else {
            Write-Error "Failed to generate SSH key: $result"
            exit 4
        }
    }
    catch {
        Write-Error "Failed to generate SSH key: $($_.Exception.Message)"
        exit 4
    }
}

function Initialize-SshAgent {
    Write-Info "Setting up SSH agent..."
    
    # Try to start SSH agent service
    if (-not (Test-SshAgent)) {
        Write-Info "Starting SSH agent..."
        try {
            $sshAgentService = Get-Service ssh-agent -ErrorAction SilentlyContinue
            if ($sshAgentService) {
                Start-Service ssh-agent
                Write-Success "SSH agent service started"
            }
            else {
                # Fallback: start ssh-agent manually
                $sshAgentOutput = & ssh-agent 2>&1
                $env:SSH_AUTH_SOCK = $null
                $env:SSH_AGENT_PID = $null
                
                foreach ($line in $sshAgentOutput) {
                    if ($line -match 'SSH_AUTH_SOCK=([^;]+);') {
                        $env:SSH_AUTH_SOCK = $matches[1]
                    }
                    if ($line -match 'SSH_AGENT_PID=([^;]+);') {
                        $env:SSH_AGENT_PID = $matches[1]
                    }
                }
                Write-Success "SSH agent started manually"
            }
        }
        catch {
            Write-Error "Failed to start SSH agent: $($_.Exception.Message)"
            exit 4
        }
    }
    
    # Add key to SSH agent
    Write-Info "Adding key to SSH agent..."
    try {
        $result = & ssh-add $script:PrivateKey 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Key added to SSH agent"
        }
        else {
            Write-Error "Failed to add key to SSH agent: $result"
            exit 4
        }
    }
    catch {
        Write-Error "Failed to add key to SSH agent: $($_.Exception.Message)"
        exit 4
    }
}

function Set-SshConfig {
    Write-Info "Configuring SSH client..."
    
    # Check if GitHub config already exists
    $githubConfigExists = $false
    if (Test-Path $script:SshConfig) {
        $configContent = Get-Content $script:SshConfig -Raw -ErrorAction SilentlyContinue
        if ($configContent -match "Host github\.com") {
            $githubConfigExists = $true
        }
    }
    
    if ($githubConfigExists) {
        Write-Warning "GitHub SSH configuration already exists in $script:SshConfig"
        
        if ($script:InteractiveMode -and -not $Force) {
            $updateConfig = Read-Host "Do you want to update it? (y/N)"
            if ($updateConfig -notmatch '^[Yy]$') {
                Write-Info "Skipping SSH config update"
                return
            }
        }
    }
    
    # Add GitHub configuration
    Write-Info "Adding GitHub configuration to SSH config..."
    $configEntry = @"

# GitHub configuration (added by $Script:ScriptName v$Script:Version)
Host github.com
    HostName github.com
    User git
    IdentityFile $script:PrivateKey
    IdentitiesOnly yes
    AddKeysToAgent yes
"@
    
    try {
        Add-Content -Path $script:SshConfig -Value $configEntry -Encoding UTF8
        Write-Success "SSH configuration updated"
    }
    catch {
        Write-Error "Failed to update SSH configuration: $($_.Exception.Message)"
        exit 4
    }
}

#==============================================================================
# GitHub Integration Functions
#==============================================================================

function Show-PublicKey {
    Write-Host
    Write-Header "=== Your SSH Public Key ==="
    Write-Info "Copy the following public key and add it to your GitHub account:"
    Write-Host
    
    try {
        $publicKeyContent = Get-Content $script:PublicKey -Raw
        Write-ColorOutput $publicKeyContent "Green"
        
        # Copy to clipboard if possible
        try {
            $publicKeyContent | Set-Clipboard
            Write-Success "Public key has been copied to clipboard!"
        }
        catch {
            Write-Warning "Could not copy to clipboard automatically"
        }
    }
    catch {
        Write-Error "Could not read public key file: $($_.Exception.Message)"
        exit 4
    }
    
    Write-Host
    Write-Header "=== Instructions to add key to GitHub ==="
    Write-Host "1. Go to https://github.com/settings/keys"
    Write-Host "2. Click 'New SSH key'"
    Write-Host "3. Give it a title (e.g., 'My Windows Machine - $env:COMPUTERNAME')"
    Write-Host "4. Select 'Authentication Key' as the key type"
    Write-Host "5. Paste the public key above"
    Write-Host "6. Click 'Add SSH key'"
    Write-Host
}

function Test-GitHubConnection {
    if ($script:InteractiveMode) {
        Read-Host "Press Enter after you've added the key to GitHub"
    }
    else {
        Write-Info "Waiting 5 seconds for key to be added to GitHub..."
        Start-Sleep -Seconds 5
    }
    
    Write-Host
    Write-Info "Testing SSH connection to GitHub..."
    
    try {
        $sshTestOutput = & ssh -T git@github.com 2>&1
        
        if ($sshTestOutput -match "successfully authenticated") {
            Write-Success "SSH connection to GitHub successful!"
            
            # Extract username from output
            if ($sshTestOutput -match "Hi ([^!]+)!") {
                $authenticatedUser = $matches[1]
                Write-Success "Authenticated as: $authenticatedUser"
                
                # Verify username matches
                if ($authenticatedUser -ne $script:Username) {
                    Write-Warning "Authenticated username ($authenticatedUser) differs from provided username ($script:Username)"
                    
                    if ($script:InteractiveMode) {
                        $useAuthUser = Read-Host "Continue with the authenticated username ($authenticatedUser)? (Y/n)"
                        if ($useAuthUser -notmatch '^[Nn]$') {
                            Write-Info "Updating username to: $authenticatedUser"
                            $script:Username = $authenticatedUser
                        }
                    }
                }
            }
        }
        else {
            Write-Error "SSH connection test failed"
            Write-Info "Output: $sshTestOutput"
            
            if ($script:InteractiveMode) {
                $continueSetup = Read-Host "Continue with Git configuration anyway? (y/N)"
                if ($continueSetup -notmatch '^[Yy]$') {
                    exit 5
                }
            }
            else {
                exit 5
            }
        }
    }
    catch {
        Write-Error "SSH connection test failed: $($_.Exception.Message)"
        exit 5
    }
}

#==============================================================================
# Git Configuration Functions
#==============================================================================

function Set-GitConfiguration {
    Write-Info "Configuring Git..."
    
    try {
        # Basic Git configuration
        & git config --global user.name $script:FullName
        if ($LASTEXITCODE -ne 0) { throw "Failed to set Git user name" }
        
        & git config --global user.email $script:Email
        if ($LASTEXITCODE -ne 0) { throw "Failed to set Git email" }
        
        & git config --global init.defaultBranch main
        if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to set default branch" }
        
        # Configure Git to use SSH for GitHub
        & git config --global url."git@github.com:".insteadOf "https://github.com/"
        if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to configure Git SSH URL rewriting" }
        
        Write-Success "Git configuration completed"
        Write-Info "Git commits will be attributed to: $script:FullName <$script:Email>"
    }
    catch {
        Write-Error "Git configuration failed: $($_.Exception.Message)"
        exit 1
    }
}

function Test-GitOperations {
    Write-Info "Testing Git operations with SSH..."
    
    try {
        $result = Show-Progress "Testing Git clone operation" {
            & git ls-remote git@github.com:octocat/Hello-World.git 2>&1
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Git operations working correctly with SSH"
        }
        else {
            Write-Warning "Git SSH test failed - this might be normal"
            Write-Info "Try cloning your own repository to verify: git clone git@github.com:$script:Username/repository.git"
        }
    }
    catch {
        Write-Warning "Git SSH test failed: $($_.Exception.Message)"
    }
}

#==============================================================================
# Summary Function
#==============================================================================

function Show-Summary {
    Write-Host
    Write-Header "=== Setup Complete! ==="
    Write-Success "Your SSH key has been set up and Git is configured"
    Write-Host
    
    Write-Info "Configuration Summary:"
    Write-Host "  • SSH Key Type: $script:KeyType"
    Write-Host "  • Key Name: $script:KeyName"
    Write-Host "  • GitHub Username: $script:Username"
    Write-Host "  • Full Name (for commits): $script:FullName"
    Write-Host "  • Email: $script:Email"
    Write-Host
    
    Write-Info "Next Steps:"
    Write-Host "  • Clone repositories: git clone git@github.com:$script:Username/repository.git"
    Write-Host "  • Test connection: ssh -T git@github.com"
    Write-Host
}

#==============================================================================
# Main Function
#==============================================================================

function Main {
    # Handle help parameter
    if ($Help) {
        Show-Help
        return
    }
    
    try {
        # System checks
        Test-SystemCompatibility
        Test-Dependencies
        
        # Get user input
        Get-UserInput
        
        # Setup SSH
        Initialize-SshPaths
        Test-ExistingKeys
        New-SshKey
        Initialize-SshAgent
        Set-SshConfig
        
        # GitHub integration
        Show-PublicKey
        Test-GitHubConnection
        
        # Git configuration
        Set-GitConfiguration
        Test-GitOperations
        
        # Show summary
        Show-Summary
        
        if ($script:InteractiveMode) {
            Read-Host "Press Enter to exit"
        }
    }
    catch {
        Write-Error "An unexpected error occurred: $($_.Exception.Message)"
        if ($script:InteractiveMode) {
            Read-Host "Press Enter to exit"
        }
        exit 1
    }
}

# Run the script
Main
