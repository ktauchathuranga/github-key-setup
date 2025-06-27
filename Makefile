.PHONY: ssh gpg all

ssh:
	bash ./setup/ssh_setup.sh

gpg:
	bash ./setup/gpg_setup.sh

all: ssh gpg

