## About
This script provides options for managing Proxmox VE repositories, including disabling the Enterprise Repo, adding or correcting PVE sources, enabling the No-Subscription Repo, adding the test Repo, disabling the subscription nag, updating Proxmox VE, and rebooting the system.

## Notes
- Execute within the Proxmox shell.
- It is recommended to answer “yes” (y) to all options presented during the process.

## Source
- https://community-scripts.org/scripts/post-pve-install

## Install
Run the command below in the Proxmox VE Shell to install PVE Post Install.

`bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/post-pve-install.sh)"`
