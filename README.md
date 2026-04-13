# ALRcloud Server Bootstrap

Epic, friendly, and secure initial setup script for **Ubuntu servers**.

This project provides a single Bash script to automate first-time server hardening and baseline configuration.

## What it does

- Runs system updates:
  - `apt update && apt upgrade -y`
- Appends global shell prompt branding to `/etc/bash.bashrc`
- Creates a new user (interactive prompts)
- Sets user password (interactive prompt)
- Adds the user to `sudo`
- Creates and secures SSH directory and `authorized_keys`
- Injects a provided public key into `authorized_keys`
- Hardens SSH:
  - `PermitRootLogin no`
  - `PasswordAuthentication no` in `/etc/ssh/sshd_config.d/*.conf`
- Restarts SSH service
- Creates and enables swap file (interactive size in GB)
- Adds swap entry to `/etc/fstab` if missing
- Shows active swap
- Asks at the end if you want to reboot now

## Requirements

- **Ubuntu** server
- Run as `root`
- Internet access for package updates

## Run Command

Execute directly from GitHub:

```bash
curl -sSL https://raw.githubusercontent.com/ALRcloud/server-bootstrap/main/alrcloud-bootstrap.sh | sudo bash
```

## Interactive prompts

The script will ask for:

- New username
- Full name
- Password (with confirmation)
- SSH public key
- Swap size (GB)
- Final reboot confirmation

## Important security note

Before confirming execution, make sure the SSH public key you provide is valid and belongs to you.  
The script disables root SSH login and password SSH authentication.

## Tested scope

- Designed for Ubuntu environments.
- Not intended for CentOS, RHEL, Alpine, or other non-APT distributions without adaptation.

## Recommended next steps

- Validate SSH access with the new user in a new terminal session.
- Confirm sudo access:

  ```bash
  su - <new_user>
  sudo whoami
  ```

- Confirm SSH hardening:

  ```bash
  sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication'
  ```

## License

This project is licensed under the MIT License.
See the LICENSE file for full details.
