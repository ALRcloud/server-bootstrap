#!/usr/bin/env bash
set -euo pipefail

if [[ ! -t 0 ]]; then
  echo "[ERROR] Interactive TTY required. Run as: sudo ./alrcloud-bootstrap.sh"
  exit 1
fi

# =========================================================
# ALRcloud Ubuntu Initial Server Setup
# =========================================================

# ---------- Colors ----------
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
NC="\033[0m"

info()  { echo -e "${BLUE}[ALRcloud]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

show_banner() {
  clear
  echo -e "${CYAN}"
  cat <<'EOF'
     _    _     ____      _                 _ 
    / \  | |   |  _ \ ___| | ___  _   _  __| |
   / _ \ | |   | |_) / __| |/ _ \| | | |/ _` |
  / ___ \| |___|  _ < (__| | (_) | |_| | (_| |
 /_/   \_\_____|_| \_\___|_|\___/ \__,_|\__,_|
                                              
                 A L R c l o u d
      Ubuntu Server Bootstrap • Secure • Fast • Clean
EOF
  echo -e "${NC}"
}

show_banner

if [[ "${EUID}" -ne 0 ]]; then
  error "Please run this script as root."
  exit 1
fi

echo
info "Welcome to ALRcloud initial Ubuntu setup."
echo

# ---------- User input ----------
read -r -p "Enter new username: " NEW_USER
while [[ -z "${NEW_USER}" ]]; do
  read -r -p "Username cannot be empty. Enter new username: " NEW_USER
done

read -r -p "Enter full name for ${NEW_USER}: " FULL_NAME
while [[ -z "${FULL_NAME}" ]]; do
  read -r -p "Full name cannot be empty. Enter full name: " FULL_NAME
done

read -r -s -p "Enter password for ${NEW_USER}: " USER_PASS
echo
read -r -s -p "Confirm password for ${NEW_USER}: " USER_PASS_CONFIRM
echo
if [[ "${USER_PASS}" != "${USER_PASS_CONFIRM}" ]]; then
  error "Passwords do not match."
  exit 1
fi

read -r -p "Paste SSH public key for ${NEW_USER}: " PUBKEY
while [[ -z "${PUBKEY}" ]]; do
  read -r -p "Public key cannot be empty. Paste SSH public key: " PUBKEY
done

read -r -p "Enter swap size in GB (example: 2): " SWAP_GB
if ! [[ "${SWAP_GB}" =~ ^[0-9]+$ ]] || [[ "${SWAP_GB}" -eq 0 ]]; then
  error "Swap size must be a positive integer."
  exit 1
fi

echo
warn "This will disable root SSH login and password SSH authentication."
warn "Ensure your SSH key is correct before continuing."
read -r -p "Continue? (yes/no): " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  warn "Setup aborted by user."
  exit 0
fi

# ---------- System update ----------
info "Updating system packages..."
apt update && apt upgrade -y
ok "System updated."

# ---------- /etc/bash.bashrc prompt config ----------
info "Configuring global prompt in /etc/bash.bashrc..."
if ! grep -q "R-Core Global Prompt Configuration" /etc/bash.bashrc; then
cat <<'EOF' >> /etc/bash.bashrc

# R-Core Global Prompt Configuration
__rcore_prompt() {
    local host
    # Get the system hostname
    host="$(hostname)"

    if [ "$(id -u)" -eq 0 ]; then
        # Root User: Red Color for safety awareness
        PS1="\[\033[01;31m\]\u@${host}\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]# "
    else
        # Normal User: Green Color
        PS1="\[\e[1;32m\]\u@${host}\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ "
    fi
}

# Safely inject the R-Core prompt function into PROMPT_COMMAND
if [[ ! "$PROMPT_COMMAND" =~ "__rcore_prompt" ]]; then
    PROMPT_COMMAND="__rcore_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi
# End R-Core Configuration
EOF
  ok "Prompt configuration added."
else
  warn "Prompt configuration already exists, skipping."
fi

# ---------- Create user ----------
if id "${NEW_USER}" &>/dev/null; then
  warn "User ${NEW_USER} already exists. Skipping creation."
else
  info "Creating user ${NEW_USER}..."
  adduser --disabled-password --gecos "${FULL_NAME},,," "${NEW_USER}"
  echo "${NEW_USER}:${USER_PASS}" | chpasswd
  ok "User created."
fi

# ---------- Add user to sudo ----------
info "Adding ${NEW_USER} to sudo group..."
usermod -aG sudo "${NEW_USER}"
ok "User added to sudo group."

# ---------- SSH setup ----------
info "Setting up SSH authorized_keys for ${NEW_USER}..."
install -d -m 700 -o "${NEW_USER}" -g "${NEW_USER}" "/home/${NEW_USER}/.ssh"
printf "%s\n" "${PUBKEY}" > "/home/${NEW_USER}/.ssh/authorized_keys"
chmod 700 -R "/home/${NEW_USER}/.ssh"
chmod 600 "/home/${NEW_USER}/.ssh/authorized_keys"
chown -R "${NEW_USER}:${NEW_USER}" "/home/${NEW_USER}"
ok "SSH key configured."

# ---------- SSH hardening ----------
info "Hardening SSH settings..."

if grep -Eq '^\s*#?\s*PermitRootLogin\s+' /etc/ssh/sshd_config; then
  sed -i -E 's|^\s*#?\s*PermitRootLogin\s+.*|PermitRootLogin no|' /etc/ssh/sshd_config
else
  echo "PermitRootLogin no" >> /etc/ssh/sshd_config
fi

shopt -s nullglob
CONF_FILES=(/etc/ssh/sshd_config.d/*.conf)
if ((${#CONF_FILES[@]} > 0)); then
  for f in "${CONF_FILES[@]}"; do
    if grep -Eq '^\s*#?\s*PasswordAuthentication\s+' "$f"; then
      sed -i -E 's|^\s*#?\s*PasswordAuthentication\s+.*|PasswordAuthentication no|' "$f"
    else
      echo "PasswordAuthentication no" >> "$f"
    fi
  done
else
  mkdir -p /etc/ssh/sshd_config.d
  echo "PasswordAuthentication no" > /etc/ssh/sshd_config.d/99-alrcloud-hardening.conf
fi
shopt -u nullglob

service ssh restart
ok "SSH hardened and restarted."

# ---------- Swap ----------
info "Configuring swap (${SWAP_GB}G)..."
if [[ -f /swapfile ]]; then
  warn "/swapfile already exists. Recreating."
  swapoff /swapfile || true
  rm -f /swapfile
fi

fallocate -l "${SWAP_GB}G" /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

if ! grep -qE '^\s*/swapfile\s+swap\s+swap\s+defaults\s+0\s+0\s*$' /etc/fstab; then
  echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
fi

swapon --show
ok "Swap configured."

echo
ok "ALRcloud setup completed successfully."
echo

# ---------- Reboot prompt ----------
read -r -p "Do you want to reboot now to apply all changes? (yes/no): " REBOOT_NOW
if [[ "${REBOOT_NOW}" == "yes" ]]; then
  info "Rebooting now..."
  reboot
else
  warn "Reboot skipped. Please reboot manually when ready."
fi
