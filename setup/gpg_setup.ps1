# GitHub GPG Key Setup Script for Windows PowerShell
$ErrorActionPreference = "Stop"

Write-Host "=== GitHub GPG Key Setup for Windows ===" -ForegroundColor Green

# Check if Git and GPG are installed
try { Get-Command git -ErrorAction Stop } catch {
    Write-Host "Git is not installed. Please install Git." -ForegroundColor Red; exit 1
}
try { Get-Command gpg -ErrorAction Stop } catch {
    Write-Host "GPG is not installed. Please install GPG (e.g., Gpg4win)." -ForegroundColor Red; exit 1
}

# User input
$name = Read-Host "Enter your name"
$email = Read-Host "Enter your email (GitHub email)"
$comment = Read-Host "Enter a comment (optional)"

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

# Get Key ID
$keyInfo = & gpg --list-secret-keys --keyid-format=long "$email"
$keyId = ($keyInfo | Select-String 'sec' | ForEach-Object { ($_ -split '/')[1] }) -replace '\s.*', ''

if (-not $keyId) {
    Write-Host "Could not find generated key." -ForegroundColor Red
    exit 1
}

# Export public key
Write-Host
Write-Host "=== Your GPG Public Key ===" -ForegroundColor Green
$pubKey = & gpg --armor --export "$keyId"
$pubKey | Write-Host -ForegroundColor Cyan

# Copy to clipboard
try {
    $pubKey | Set-Clipboard
    Write-Host "✓ Public GPG key copied to clipboard!" -ForegroundColor Green
} catch {
    Write-Host "Note: Could not copy to clipboard." -ForegroundColor Yellow
}

Write-Host "Go to https://github.com/settings/keys → New GPG key → Paste and save."
Read-Host "Press Enter once done..."

# Git config
& git config --global user.signingkey "$keyId"
& git config --global commit.gpgsign true
& git config --global user.name "$name"
& git config --global user.email "$email"

Write-Host
Write-Host "✓ GPG key setup complete and Git configured." -ForegroundColor Green

