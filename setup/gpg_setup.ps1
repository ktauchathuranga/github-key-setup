<#
.SYNOPSIS
    GitHub GPG Key Setup Script for Windows PowerShell
.DESCRIPTION
    Sets up GPG keys for GitHub commit signing with improved UX and features
.PARAMETER KeyType
    GPG key type (RSA, ECC) [default: RSA]
.PARAMETER KeyLength
    Key length for RSA (2048, 4096) [default: 4096]
.PARAMETER Email
    Email address for the GPG key
.PARAMETER FullName
    Your full name (first and last name)
.PARAMETER Comment
    Comment for the GPG key (optional)
.PARAMETER ExpireDate
    Expiration date (0 for no expiration, or YYYY-MM-DD, Ny, Nm, Nw, Nd)
.PARAMETER Passphrase
    Passphrase for the GPG key (recommended for security)
.PARAMETER Force
    Force overwrite existing keys without prompting
.PARAMETER NonInteractive
    Run in non-interactive mode (requires all parameters)
.EXAMPLE
    .\gpg_setup.ps1
    Interactive mode (default)
.EXAMPLE
    .\gpg_setup.ps1 -NonInteractive -Email "user@example.com" -FullName "John Doe" -KeyType "RSA" -KeyLength "4096"
    Non-interactive mode
.EXAMPLE
    .\gpg_setup.ps1 -KeyType ECC -Comment "Work laptop key"
    Generate ECC key with comment
.EXAMPLE
    .\gpg_setup.ps1 -ExpireDate "2026-12-31" -Passphrase "my_secure_passphrase"
    Generate key with expiration and passphrase
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "GPG key type (RSA, ECC)")]
    [ValidateSet("RSA", "ECC")]
    [string]$KeyType = "RSA",
    
    [Parameter(HelpMessage = "Key length for RSA (2048, 4096)")]
    [ValidateSet("2048", "4096")]
    [string]$KeyLength = "4096",
    
    [Parameter(HelpMessage = "Email address for the GPG key")]
    [string]$Email = "",
    
    [Parameter(HelpMessage = "Your full name (first and last name)")]
    [string]$FullName = "",
    
    [Parameter(HelpMessage = "Comment for the GPG key")]
    [string]$Comment = "",
    
    [Parameter(HelpMessage = "Expiration date (0, YYYY-MM-DD, Ny, Nm, Nw, Nd)")]
    [string]$ExpireDate = "0",
    
    [Parameter(HelpMessage = "Passphrase for the GPG key")]
    [string]$Passphrase = "",
    
    [Parameter(HelpMessage = "Force overwrite existing keys without prompting")]
    [switch]$Force,
    
    [Parameter(HelpMessage = "Run in non-interactive mode")]
    [switch]$NonInteractive
)

# Script configuration
$Script:Version = "2.0"
$Script:ScriptName = "GitHub GPG Setup"
$ErrorActionPreference = "Stop"

# Global variables
$script:InteractiveMode = -not $NonInteractive
$script:TempConfigFile = ""

# Check if Git and GPG are installed
try { 
    Get-Command git -ErrorAction Stop 
} catch {
    Write-Host "Git is not installed. Please install Git." -ForegroundColor Red
    exit 1
}

try { 
    Get-Command gpg -ErrorAction Stop 
} catch {
    Write-Host "GPG is not installed. Please install GPG (e.g., Gpg4win)." -ForegroundColor Red
    exit 1
}

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

# Get user information
Write-Host "Please provide the following information:"
$name = Read-Host "Enter your full name (for GPG key, e.g., 'John Doe')"
$email = Read-Host "Enter your email address (associated with GitHub)"
$comment = Read-Host "Enter a comment for the GPG key (optional)"

# Create SSH directory
$sshDir = "$env:USERPROFILE\.ssh"
if (!(Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

# Get keys before generation for comparison
Write-Host "Checking existing keys..." -ForegroundColor Yellow
$keysBefore = & gpg --list-secret-keys --keyid-format=long --with-colons | Where-Object { $_ -like "sec:*" }

# Create GPG batch config file
$tempFile = "$env:TEMP\gpg-key-config.txt"
Set-Content -Path $tempFile -Value @"
%no-protection
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Name-Real: $name
Name-Email: $email
Name-Comment: $comment
Expire-Date: 0
%commit
"@

# Generate the key
Write-Host "Generating GPG key..." -ForegroundColor Yellow
& gpg --batch --generate-key $tempFile
Remove-Item $tempFile

# Get keys after generation and find the new one
Write-Host "Detecting newly generated key..." -ForegroundColor Yellow
Start-Sleep -Seconds 1  # Brief pause to ensure key is fully processed

$keysAfter = & gpg --list-secret-keys --keyid-format=long --with-colons | Where-Object { $_ -like "sec:*" }
$newKeyLine = $keysAfter | Where-Object { $_ -notin $keysBefore } | Select-Object -First 1

if ($newKeyLine) {
    $keyId = ($newKeyLine -split ':')[4]
    Write-Host "Automatically detected new key ID: $keyId" -ForegroundColor Green
} else {
    # Fallback: Get the most recent key for the email
    Write-Host "Could not detect new key automatically. Finding most recent key for $email..." -ForegroundColor Yellow
    
    # Get all keys with timestamps and filter by email
    $allKeysDetailed = & gpg --list-secret-keys --keyid-format=long --with-colons
    $keyBlocks = @()
    $currentBlock = @()
    
    foreach ($line in $allKeysDetailed) {
        if ($line -like "sec:*") {
            if ($currentBlock.Count -gt 0) {
                $keyBlocks += ,$currentBlock
            }
            $currentBlock = @($line)
        } elseif ($line -like "uid:*" -or $line -like "ssb:*") {
            $currentBlock += $line
        }
    }
    if ($currentBlock.Count -gt 0) {
        $keyBlocks += ,$currentBlock
    }
    
    # Find blocks that contain our email and get the most recent
    $matchingKeys = @()
    foreach ($block in $keyBlocks) {
        $uidLine = $block | Where-Object { $_ -like "*uid:*" -and $_ -like "*$email*" }
        if ($uidLine) {
            $secLine = $block[0]
            $keyId = ($secLine -split ':')[4]
            $creationTime = ($secLine -split ':')[5]
            $matchingKeys += [PSCustomObject]@{
                KeyId = $keyId
                CreationTime = $creationTime
                SecLine = $secLine
            }
        }
    }
    
    if ($matchingKeys.Count -gt 0) {
        # Sort by creation time (descending) and get the most recent
        $mostRecentKey = $matchingKeys | Sort-Object CreationTime -Descending | Select-Object -First 1
        $keyId = $mostRecentKey.KeyId
        Write-Host "Using most recent key for $email`: $keyId" -ForegroundColor Green
    }
}

# Final fallback
if (-not $keyId) {
    Write-Host "Could not automatically detect key. Please select manually:" -ForegroundColor Yellow
    $keyList = & gpg --list-secret-keys --keyid-format=long
    $keyList | Write-Host -ForegroundColor Gray
    $keyId = Read-Host "Enter the key ID (the part after rsa4096/)"
}

if (-not $keyId) {
    Write-Host "Could not find generated key." -ForegroundColor Red
    exit 1
}

Write-Host "Using Key ID: $keyId" -ForegroundColor Green

# Configure Git to use the GPG key
Write-Host "Configuring Git..." -ForegroundColor Yellow
& git config --global user.signingkey $keyId
& git config --global commit.gpgsign true
& git config --global user.name "$name"
& git config --global user.email $email

# Export public key
Write-Host
Write-Host "=== Your GPG Public Key ===" -ForegroundColor Green
$pubKey = & gpg --armor --export "$keyId"

if ($pubKey) {
    $pubKey | Write-Host -ForegroundColor Cyan
    
    # Copy to clipboard
    try {
        $pubKey | Set-Clipboard
        Write-Host "Public GPG key copied to clipboard!" -ForegroundColor Green
    } catch {
        Write-Host "Note: Could not copy to clipboard." -ForegroundColor Yellow
    }
} else {
    Write-Host "Failed to export public key. Please check the key ID: $keyId" -ForegroundColor Red
    exit 1
}

Write-Host "Go to https://github.com/settings/keys -> New GPG key -> Paste and save."
Read-Host "Press Enter once done..."

Write-Host
Write-Host "GPG key setup complete and Git configured." -ForegroundColor Green
Write-Host "Key ID: $keyId" -ForegroundColor Cyan
Write-Host "You can now sign your commits!" -ForegroundColor Green