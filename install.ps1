Write-Host "GitHub Key Setup"
Write-Host "1. Setup SSH keys"
Write-Host "2. Setup GPG keys"
Write-Host "3. Setup both"
$choice = Read-Host "Choose an option [1-3]"

switch ($choice) {
    "1" { .\setup\ssh_setup.ps1 }
    "2" { .\setup\gpg_setup.ps1 }
    "3" { .\setup\ssh_setup.ps1; .\setup\gpg_setup.ps1 }
    default { Write-Host "Invalid option." }
}

