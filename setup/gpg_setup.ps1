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
    .\github_gpg_setup.ps1
    Interactive mode (default)
.EXAMPLE
    .\github_gpg_setup.ps1 -NonInteractive -Email "user@example.com" -FullName "John Doe" -KeyType "RSA" -KeyLength "4096"
    Non-interactive mode
.EXAMPLE
    .\github_gpg_setup.ps1 -KeyType ECC -Comment "Work laptop key"
    Generate ECC key with comment
.EXAMPLE
    .\github_gpg_setup.ps1 -ExpireDate "2026-12-31" -Passphrase "my_secure_passphrase"
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

#==============================================================================
# Helper Functions
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
    Write-Host "    .\github_gpg_setup.ps1 [OPTIONS]"
    Write-Host
    Write-Header "PARAMETERS:"
    Write-Host "    -KeyType TYPE           GPG key type (RSA, ECC) [default: RSA]"
    Write-Host "    -KeyLength LEN          Key length for RSA (2048, 4096) [default: 4096]"
    Write-Host "    -Email EMAIL            Email address for the GPG key"
    Write-Host "    -FullName NAME          Your full name (first and last name)"
    Write-Host "    -Comment TEXT           Comment for the GPG key (optional)"
    Write-Host "    -ExpireDate DATE        Expiration date (0 for no expiration, or YYYY-MM-DD)"
    Write-Host "    -Passphrase PASS        Passphrase for the GPG key (recommended)"
    Write-Host "    -Force                  Force overwrite existing keys without prompting"
    Write-Host "    -NonInteractive         Run in non-interactive mode (requires all parameters)"
    Write-Host "    -Help                   Show this help message"
    Write-Host
    Write-Header "EXAMPLES:"
    Write-Host "    Interactive mode (default):"
    Write-Host "        .\github_gpg_setup.ps1"
    Write-Host
    Write-Host "    Non-interactive mode:"
    Write-Host "        .\github_gpg_setup.ps1 -NonInteractive -Email 'user@example.com' -FullName 'John Doe' -KeyType 'RSA' -KeyLength '4096'"
    Write-Host
    Write-Host "    Generate ECC key with comment:"
    Write-Host "        .\github_gpg_setup.ps1 -KeyType ECC -Comment 'Work laptop key'"
    Write-Host
    Write-Host "    Generate key with expiration:"
    Write-Host "        .\github_gpg_setup.ps1 -ExpireDate '2026-12-31' -Passphrase 'my_secure_passphrase'"
    Write-Host
    Write-Header "SUPPORTED KEY TYPES:"
    Write-Host "    RSA        - RSA keys (2048 or 4096 bit) - widely compatible"
    Write-Host "    ECC        - Elliptic Curve keys (faster, smaller) - modern"
    Write-Host
    Write-Header "KEY EXPIRATION:"
    Write-Host "    0          - No expiration (default)"
    Write-Host "    YYYY-MM-DD - Specific expiration date (e.g., 2026-12-31)"
    Write-Host "    Nd         - Expire in N days (e.g., 365d)"
    Write-Host "    Nw         - Expire in N weeks (e.g., 52w)"
    Write-Host "    Nm         - Expire in N months (e.g., 12m)"
    Write-Host "    Ny         - Expire in N years (e.g., 2y)"
    Write-Host
    Write-Header "SECURITY NOTES:"
    Write-Host "    - Using a passphrase is highly recommended for security"
    Write-Host "    - Key expiration helps maintain good security hygiene"
    Write-Host "    - RSA 4096-bit keys provide excellent security"
    Write-Host "    - ECC keys are faster and smaller but require modern GPG"
    Write-Host
    Write-Header "TROUBLESHOOTING:"
    Write-Host "    If GPG key generation fails:"
    Write-Host "    1. Ensure GPG is properly installed (e.g., Gpg4win)"
    Write-Host "    2. Check GPG version: gpg --version"
    Write-Host "    3. Verify GPG agent: gpg-connect-agent /bye"
    Write-Host "    4. Try generating entropy by moving mouse/typing"
    Write-Host
    Write-Host "    If Git signing fails:"
    Write-Host "    1. Verify GPG key exists: gpg --list-secret-keys"
    Write-Host "    2. Check Git configuration: git config --list | Select-String gpg"
    Write-Host "    3. Test signing: echo 'test' | gpg --clearsign"
    Write-Host "    4. Verify GPG agent: gpg-connect-agent /bye"
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
    $requiredCommands = @("git", "gpg")
    
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
        Write-Info "- GPG: https://www.gpg4win.org/ or https://gnupg.org/download/"
        
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
        
        $gpgVersion = & gpg --version 2>$null | Select-Object -First 1
        Write-Info "GPG: $gpgVersion"
    }
    catch {
        Write-Warning "Could not determine version information"
    }
}

function Test-GpgAgent {
    Write-Info "Checking GPG agent status..."
    
    try {
        $result = & gpg-connect-agent '/bye' 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "GPG agent is responsive"
            return $true
        }
        else {
            Write-Warning "GPG agent not responding properly"
            return $false
        }
    }
    catch {
        Write-Warning "GPG agent not found or not responding"
        return $false
    }
}

#==============================================================================
# User Input Functions
#==============================================================================

function Get-UserInput {
    if (-not $script:InteractiveMode) {
        Test-RequiredParameters
        return
    }
    
    Write-Header "=== GitHub GPG Key Setup for Windows ==="
    Write-Host
    
    Write-Info "This script will help you set up GPG key signing for GitHub commits"
    Write-Host
    
    # Get full name
    while ([string]::IsNullOrWhiteSpace($script:FullName)) {
        $script:FullName = Read-Host "Enter your full name (for GPG key, e.g., 'John Doe')"
        if ([string]::IsNullOrWhiteSpace($script:FullName)) {
            Write-Error "Full name cannot be empty"
        }
    }
    
    # Get email
    while ([string]::IsNullOrWhiteSpace($script:Email)) {
        $script:Email = Read-Host "Enter your email address (associated with GitHub)"
        if ([string]::IsNullOrWhiteSpace($script:Email)) {
            Write-Error "Email address cannot be empty"
        }
    }
    
    # Get optional comment
    $script:Comment = Read-Host "Enter a comment for the GPG key (optional, e.g., 'Work laptop')"
    
    # Get key type
    Write-Host
    Write-Info "Available GPG key types:"
    Write-Host "  1) RSA (recommended - widely compatible)"
    Write-Host "  2) ECC (modern - faster, smaller keys)"
    Write-Host
    
    do {
        $keyChoice = Read-Host "Select key type (1-2, default: 1)"
        switch ($keyChoice) {
            { $_ -eq "" -or $_ -eq "1" } { $script:KeyType = "RSA"; $validChoice = $true }
            "2" { $script:KeyType = "ECC"; $validChoice = $true }
            default { Write-Error "Invalid choice. Please select 1 or 2."; $validChoice = $false }
        }
    } while (-not $validChoice)
    
    # Get key length for RSA
    if ($script:KeyType -eq "RSA") {
        Write-Host
        Write-Info "Available RSA key lengths:"
        Write-Host "  1) 4096 bits (recommended - high security)"
        Write-Host "  2) 2048 bits (standard - good compatibility)"
        Write-Host
        
        do {
            $lengthChoice = Read-Host "Select key length (1-2, default: 1)"
            switch ($lengthChoice) {
                { $_ -eq "" -or $_ -eq "1" } { $script:KeyLength = "4096"; $validChoice = $true }
                "2" { $script:KeyLength = "2048"; $validChoice = $true }
                default { Write-Error "Invalid choice. Please select 1 or 2."; $validChoice = $false }
            }
        } while (-not $validChoice)
    }
    
    # Get expiration date
    Write-Host
    Write-Info "Key expiration options:"
    Write-Host "  1) No expiration (keys never expire)"
    Write-Host "  2) 1 year from now"
    Write-Host "  3) 2 years from now"
    Write-Host "  4) Custom date/period"
    Write-Host
    
    do {
        $expireChoice = Read-Host "Select expiration (1-4, default: 1)"
        switch ($expireChoice) {
            { $_ -eq "" -or $_ -eq "1" } { $script:ExpireDate = "0"; $validChoice = $true }
            "2" { $script:ExpireDate = "1y"; $validChoice = $true }
            "3" { $script:ExpireDate = "2y"; $validChoice = $true }
            "4" { 
                $script:ExpireDate = Read-Host "Enter custom expiration (YYYY-MM-DD, Ny, Nm, Nw, Nd, or 0)"
                $validChoice = $true 
            }
            default { Write-Error "Invalid choice. Please select 1-4."; $validChoice = $false }
        }
    } while (-not $validChoice)
    
    # Get passphrase
    Write-Host
    Write-Info "Passphrase Protection:"
    Write-Info "A passphrase protects your private key from unauthorized use"
    $securePassphrase = Read-Host "Enter passphrase for GPG key (press Enter for no passphrase, NOT recommended)" -AsSecureString
    $script:Passphrase = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassphrase))
    
    if ([string]::IsNullOrWhiteSpace($script:Passphrase)) {
        Write-Warning "No passphrase set - your private key will be unprotected!"
        $confirmNoPass = Read-Host "Are you sure you want to continue without a passphrase? (y/N)"
        if ($confirmNoPass -notmatch '^[Yy]$') {
            Write-Info "Please run the script again and set a passphrase"
            exit 0
        }
    }
    
    Write-Host
}

function Test-RequiredParameters {
    $missingParams = @()
    
    if ([string]::IsNullOrWhiteSpace($Email)) { $missingParams += "Email (-Email)" }
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
    $script:FullName = $FullName
    $script:Comment = $Comment
    $script:KeyType = $KeyType
    $script:KeyLength = $KeyLength
    $script:ExpireDate = $ExpireDate
    $script:Passphrase = $Passphrase
}

#==============================================================================
# GPG Setup Functions
#==============================================================================

function Test-ExistingKeys {
    Write-Info "Checking for existing GPG keys..."
    
    try {
        $existingKeys = & gpg --list-secret-keys --keyid-format=long $script:Email 2>$null
        
        if ($existingKeys -and ($existingKeys | Select-String 'sec').Count -gt 0) {
            Write-Warning "Found existing GPG key(s) for $script:Email:"
            $existingKeys | Select-String -Pattern 'sec|uid' | ForEach-Object { Write-Host "  $_" }
            Write-Host
            
            if ($Force) {
                Write-Info "Force overwrite enabled, continuing with new key generation..."
                return
            }
            
            if ($script:InteractiveMode) {
                $createNew = Read-Host "Do you want to create a new key anyway? (y/N)"
                if ($createNew -notmatch '^[Yy]$') {
                    Write-Info "Exiting without creating new key"
                    if ($script:InteractiveMode) {
                        Read-Host "Press Enter to exit"
                    }
                    exit 0
                }
            }
            else {
                Write-Error "Existing key found and force overwrite not enabled"
                Write-Info "Use -Force to create a new key anyway"
                exit 4
            }
        }
        else {
            Write-Success "No existing GPG keys found for $script:Email"
        }
    }
    catch {
        Write-Info "Could not check for existing keys (this is normal if no keys exist)"
    }
}

function New-GpgKeyConfig {
    $script:TempConfigFile = "$env:TEMP\gpg-key-config-$(Get-Random).txt"
    
    Write-Info "Creating GPG key configuration..."
    
    $configContent = @"
%echo Generating GPG key...
"@
    
    if ($script:KeyType -eq "RSA") {
        $configContent += @"
Key-Type: RSA
Key-Length: $script:KeyLength
Subkey-Type: RSA
Subkey-Length: $script:KeyLength
"@
    }
    else {
        # ECC
        $configContent += @"
Key-Type: EDDSA
Key-Curve: Ed25519
Subkey-Type: ECDH
Subkey-Curve: Curve25519
"@
    }
    
    $configContent += @"
Name-Real: $script:FullName
Name-Email: $script:Email
"@
    
    if (-not [string]::IsNullOrWhiteSpace($script:Comment)) {
        $configContent += "Name-Comment: $script:Comment`n"
    }
    
    $configContent += "Expire-Date: $script:ExpireDate`n"
    
    if ([string]::IsNullOrWhiteSpace($script:Passphrase)) {
        $configContent += "%no-protection`n"
    }
    else {
        $configContent += "Passphrase: $script:Passphrase`n"
    }
    
    $configContent += @"
%commit
%echo GPG key generation complete
"@
    
    try {
        Set-Content -Path $script:TempConfigFile -Value $configContent -Encoding UTF8
        Write-Success "GPG key configuration created"
    }
    catch {
        Write-Error "Failed to create GPG key configuration: $($_.Exception.Message)"
        exit 4
    }
}

function New-GpgKey {
    Write-Info "Generating $script:KeyType GPG key..."
    Write-Info "This may take a while, especially on systems with low entropy"
    
    try {
        $result = Show-Progress "Generating GPG key (move mouse/type to generate entropy)" {
            & gpg --batch --generate-key $script:TempConfigFile 2>&1
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "GPG key generated successfully"
        }
        else {
            Write-Error "Failed to generate GPG key: $result"
            exit 4
        }
    }
    catch {
        Write-Error "Failed to generate GPG key: $($_.Exception.Message)"
        exit 4
    }
    finally {
        # Clean up temporary config file
        if (Test-Path $script:TempConfigFile) {
            Remove-Item $script:TempConfigFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-GeneratedKeyId {
    Write-Info "Finding generated GPG key..."
    
    try {
        $keyInfo = & gpg --list-secret-keys --keyid-format=long $script:Email 2>$null
        
        if (-not $keyInfo) {
            Write-Error "No GPG keys found for $script:Email"
            exit 4
        }
        
        # Extract key ID from the sec line
        $secLine = $keyInfo | Select-String 'sec' | Select-Object -Last 1
        if ($secLine) {
            $keyId = ($secLine -split '/')[1] -replace '\s.*', ''
            Write-Success "GPG key ID: $keyId"
            return $keyId
        }
        else {
            Write-Error "Could not parse GPG key ID"
            exit 4
        }
    }
    catch {
        Write-Error "Failed to find generated GPG key: $($_.Exception.Message)"
        exit 4
    }
}

#==============================================================================
# GitHub Integration Functions
#==============================================================================

function Show-PublicKey {
    param([string]$KeyId)
    
    Write-Host
    Write-Header "=== Your GPG Public Key ==="
    Write-Info "Copy the following public key and add it to your GitHub account:"
    Write-Host
    
    try {
        $publicKey = & gpg --armor --export $KeyId 2>$null
        
        if ($publicKey) {
            Write-ColorOutput ($publicKey -join "`n") "Green"
            
            # Copy to clipboard
            try {
                ($publicKey -join "`n") | Set-Clipboard
                Write-Success "Public key copied to clipboard!"
            }
            catch {
                Write-Warning "Could not copy to clipboard automatically"
            }
        }
        else {
            Write-Error "Failed to export public key"
            exit 4
        }
    }
    catch {
        Write-Error "Failed to export public key: $($_.Exception.Message)"
        exit 4
    }
    
    Write-Host
    Write-Header "=== Instructions to add key to GitHub ==="
    Write-Host "1. Go to https://github.com/settings/keys"
    Write-Host "2. Click 'New GPG key'"
    Write-Host "3. Paste the public key above"
    Write-Host "4. Click 'Add GPG key'"
    Write-Host
}

function Test-GpgSigning {
    param([string]$KeyId)
    
    if ($script:InteractiveMode) {
        Read-Host "Press Enter after you've added the key to GitHub"
    }
    else {
        Write-Info "Waiting 5 seconds for key to be added to GitHub..."
        Start-Sleep -Seconds 5
    }
    
    Write-Host
    Write-Info "Testing GPG signing..."
    
    try {
        $testMessage = "Test GPG signing - $(Get-Date)"
        $result = $testMessage | & gpg --clearsign --default-key $KeyId 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "GPG signing test successful!"
        }
        else {
            Write-Warning "GPG signing test failed: $result"
            Write-Info "This might be due to:"
            Write-Host "  - Missing or incorrect passphrase"
            Write-Host "  - GPG agent not running properly"
            Write-Host "  - Permission issues with GPG"
            
            if ($script:InteractiveMode) {
                $continueSetup = Read-Host "Continue with Git configuration anyway? (y/N)"
                if ($continueSetup -notmatch '^[Yy]$') {
                    exit 4
                }
            }
        }
    }
    catch {
        Write-Warning "GPG signing test failed: $($_.Exception.Message)"
    }
}

#==============================================================================
# Git Configuration Functions
#==============================================================================

function Set-GitConfiguration {
    param([string]$KeyId)
    
    Write-Info "Configuring Git for GPG signing..."
    
    try {
        # Configure Git to use the GPG key
        & git config --global user.signingkey $KeyId
        if ($LASTEXITCODE -ne 0) { throw "Failed to set Git signing key" }
        
        # Enable automatic commit signing
        & git config --global commit.gpgsign true
        if ($LASTEXITCODE -ne 0) { throw "Failed to enable commit signing" }
        
        # Configure user information
        & git config --global user.name $script:FullName
        if ($LASTEXITCODE -ne 0) { throw "Failed to set Git user name" }
        
        & git config --global user.email $script:Email
        if ($LASTEXITCODE -ne 0) { throw "Failed to set Git email" }
        
        # Optional: Enable tag signing
        if ($script:InteractiveMode) {
            $enableTagSigning = Read-Host "Enable automatic tag signing? (Y/n)"
            if ($enableTagSigning -notmatch '^[Nn]$') {
                & git config --global tag.gpgsign true
                if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to enable tag signing" }
            }
        }
        else {
            # Enable tag signing by default in non-interactive mode
            & git config --global tag.gpgsign true
            if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to enable tag signing" }
        }
        
        Write-Success "Git configuration completed"
        Write-Info "Git commits will be signed with key: $KeyId"
        Write-Info "Git commits will be attributed to: $script:FullName <$script:Email>"
    }
    catch {
        Write-Error "Git configuration failed: $($_.Exception.Message)"
        exit 1
    }
}

function Test-GitSigning {
    Write-Info "Testing Git commit signing..."
    
    $testDir = "$env:TEMP\gpg_signing_test_$(Get-Random)"
    
    try {
        $result = Show-Progress "Testing Git commit signing" {
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            Set-Location $testDir
            & git init --quiet 2>$null
            "# GPG Signing Test" | Out-File -FilePath "README.md" -Encoding UTF8
            & git add README.md 2>$null
            & git commit -m "Test GPG signing" --quiet 2>$null
            
            # Check if the commit was signed
            $commitSignature = & git log --show-signature -1 --pretty=format:"%G?" 2>$null
            Set-Location $env:TEMP
            Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
            
            return $commitSignature
        }
        
        if ($result -eq "G") {
            Write-Success "Git commit signing working correctly"
        }
        else {
            Write-Warning "Git commit signing test failed"
            Write-Info "Your commits may not show as verified on GitHub"
            Write-Info "Check GPG configuration with: git config --list | Select-String gpg"
        }
    }
    catch {
        Write-Warning "Git commit signing test failed: $($_.Exception.Message)"
        Write-Info "Check GPG configuration with: git config --list | Select-String gpg"
    }
    finally {
        if (Test-Path $testDir) {
            Set-Location $env:TEMP
            Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

#==============================================================================
# Summary and Cleanup Functions
#==============================================================================

function Show-Summary {
    param([string]$KeyId)
    
    Write-Host
    Write-Header "=== Setup Complete! ==="
    Write-Success "Your GPG key has been set up and Git is configured for signing"
    Write-Host
    
    Write-Info "Configuration Summary:"
    Write-Host "  • GPG Key Type: $script:KeyType"
    if ($script:KeyType -eq "RSA") {
        Write-Host "  • Key Length: $script:KeyLength bits"
    }
    Write-Host "  • Key ID: $KeyId"
    Write-Host "  • Full Name: $script:FullName"
    Write-Host "  • Email: $script:Email"
    Write-Host "  • Comment: $(if ([string]::IsNullOrWhiteSpace($script:Comment)) { '(none)' } else { $script:Comment })"
    Write-Host "  • Expiration: $(if ($script:ExpireDate -eq '0') { 'Never' } else { $script:ExpireDate })"
    Write-Host "  • Passphrase: $(if ([string]::IsNullOrWhiteSpace($script:Passphrase)) { 'No' } else { 'Yes' })"
    Write-Host
    
    Write-Info "Git Configuration:"
    Write-Host "  • Signing Key: $KeyId"
    Write-Host "  • Commit Signing: Enabled"
    try {
        $tagSigningEnabled = & git config --global tag.gpgsign 2>$null
        Write-Host "  • Tag Signing: $(if ($tagSigningEnabled -eq 'true') { 'Enabled' } else { 'Disabled' })"
    }
    catch {
        Write-Host "  • Tag Signing: Unknown"
    }
    Write-Host "  • Author Name: $script:FullName"
    Write-Host "  • Author Email: $script:Email"
    Write-Host
    
    Write-Info "Next Steps:"
    Write-Host "  • Your commits will now be automatically signed"
    Write-Host "  • Signed commits will show as 'Verified' on GitHub"
    Write-Host "  • Back up your GPG key: gpg --export-secret-keys $KeyId > backup.gpg"
    Write-Host "  • Share your public key: gpg --armor --export $KeyId"
    Write-Host
    
    Write-Info "Useful Commands:"
    Write-Host "  • List GPG keys: gpg --list-secret-keys"
    Write-Host "  • Test signing: echo 'test' | gpg --clearsign"
    Write-Host "  • Git config check: git config --list | Select-String gpg"
    Write-Host "  • Verify last commit: git log --show-signature -1"
    Write-Host
    
    if ($script:InteractiveMode) {
        Read-Host "Press Enter to exit"
    }
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
        Test-GpgAgent
        
        # Get user input
        Get-UserInput
        
        # GPG key setup
        Test-ExistingKeys
        New-GpgKeyConfig
        New-GpgKey
        $keyId = Get-GeneratedKeyId
        
        # GitHub integration
        Show-PublicKey $keyId
        Test-GpgSigning $keyId
        
        # Git configuration
        Set-GitConfiguration $keyId
        Test-GitSigning
        
        # Show summary
        Show-Summary $keyId
    }
    catch {
        Write-Error "An unexpected error occurred: $($_.Exception.Message)"
        if ($script:InteractiveMode) {
            Read-Host "Press Enter to exit"
        }
        exit 1
    }
    finally {
        # Clean up temporary files
        if ($script:TempConfigFile -and (Test-Path $script:TempConfigFile)) {
            Remove-Item $script:TempConfigFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# Run main function
Main
