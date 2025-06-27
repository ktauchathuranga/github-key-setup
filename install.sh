#!/bin/bash

echo "GitHub Key Setup"
echo "1. Setup SSH keys"
echo "2. Setup GPG keys"
echo "3. Setup both"
read -rp "Choose an option [1-3]: " option

case $option in
  1) bash ./setup/ssh_setup.sh ;;
  2) bash ./setup/gpg_setup.sh ;;
  3) bash ./setup/ssh_setup.sh && bash ./setup/gpg_setup.sh ;;
  *) echo "Invalid option." ;;
esac

