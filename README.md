# GitHub Key Setup

Easily set up your **SSH** and **GPG** keys for GitHub on **Windows**, **Linux**, or **macOS**.

This tool automates:
- ✅ SSH key generation & GitHub integration
- ✅ GPG key generation & Git commit signing
- ✅ Git global config setup

---

## Features

- Cross-platform support (PowerShell & Bash)
- SSH key creation and GitHub configuration
- GPG key generation and Git signing setup
- Easy to use with simple prompts
- Option to run only SSH, GPG, or both

---

## Prerequisites

Ensure you have the following installed:

### Linux / macOS
- `git`
- `gpg`
- `ssh`
  
### Windows
- [Git for Windows](https://git-scm.com/)
- [Gpg4win](https://gpg4win.org/)

---

## Quick Start

### Linux/macOS
```bash
git clone https://github.com/yourusername/github-key-setup.git
cd github-key-setup
chmod +x install.sh
./install.sh
````

### Windows

1. Clone the repo or download it as ZIP.
2. Right-click `install.ps1` → **Run with PowerShell with Admin privilege**
3. Follow the prompts.

---

## Installation Options

When you run the installer, you'll be prompted to choose:

1. Setup SSH keys
2. Setup GPG keys
3. Setup both

---

## Manual Mode (Advanced)

### Linux/macOS:

```bash
make ssh      # Only SSH
make gpg      # Only GPG
make all      # SSH + GPG
```

if you get any `gpg` permission errors just do `chmod 700 ~/.gnupg`

### Windows:

You can run individual setup scripts from the `setup/` directory:

* `setup/setup.ps1` – SSH setup
* `setup/gpg_setup.ps1` – GPG setup

---

## Project Structure

```
github-key-setup/
├── install.sh             # Main installer for Linux/macOS
├── install.ps1            # Main installer for Windows
├── setup/
│   ├── setup.sh           # SSH setup (Linux/macOS)
│   ├── setup.ps1          # SSH setup (Windows)
│   ├── gpg_setup.sh       # GPG setup (Linux/macOS)
│   └── gpg_setup.ps1      # GPG setup (Windows)
├── Makefile               # Optional CLI usage (Linux/macOS)
└── README.md
```

---

## What It Does

* Generates SSH or GPG key pairs
* Starts `ssh-agent` and adds SSH key
* Adds GitHub host entry to `.ssh/config`
* Configures Git with your name/email
* Enables GPG commit signing in Git
* Optionally copies your public key to clipboard

---

## Troubleshooting

### Windows GPG Signing Error

If you encounter the following error when trying to commit with GPG signing:

```
error: gpg failed to sign the data:
gpg: skipped "KEYID": No secret key
fatal: failed to write commit object
```

**Solution:** Configure Git to use the correct GPG program path:

```bash
git config --global gpg.program "C:\Program Files (x86)\GnuPG\bin\gpg.exe"
```

Or if you have Gpg4win installed in a different location:
```bash
git config --global gpg.program "C:\Program Files (x86)\Gpg4win\bin\gpg.exe"
```

This error typically occurs because Git is using a different GPG executable than where your key was generated.

---

## Aliases

* `git co` : `checkout`
* `git br` : `branch`
* `git st` : `status`
* `git sw` : `switch`
* `git lg` : `log --online --decorate --all --graph`
* `git ps` : `push origin HEAD`
* `git pl` : `pull origin HEAD`
* `git ad` : `add .`
* `git cm` : `commit -m`
* `git unstage` : `reset HEAD --`
* `git last` : `log -1 HEAD`
