#!/usr/bin/env bash
#
# create-sudo-user.sh — interactive helper that:
#   1. Installs sudo if it is missing (apt/dnf/yum/pacman/zypper/apk)
#   2. Creates a new user with a home directory (name and password are asked)
#   3. Optionally grants the user administrative (sudo) privileges
#
# Must be run as root:  sudo ./create-sudo-user.sh
# Usage guide: docs/create-sudo-user.md
# License: MIT (see LICENSE in the repository root)

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Pre-flight — everything below needs root. Running as root also avoids
#    the chicken-and-egg problem of needing sudo to install sudo.
# ---------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "This script must be run as root (try: sudo ./create-sudo-user.sh)"

# Minimal systems (e.g. Alpine without the 'shadow' package) may lack these.
command -v useradd  >/dev/null 2>&1 || die "'useradd' not found — install the 'shadow' package (Alpine) and re-run."
command -v chpasswd >/dev/null 2>&1 || die "'chpasswd' not found — install the 'shadow' package (Alpine) and re-run."

# ---------------------------------------------------------------------------
# 1. Install sudo if it is missing
# ---------------------------------------------------------------------------
if command -v sudo >/dev/null 2>&1; then
    info "sudo is already installed."
else
    warn "sudo is not installed — installing it now..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y sudo
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y sudo
    elif command -v yum >/dev/null 2>&1; then
        yum install -y sudo
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm sudo
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install sudo
    elif command -v apk >/dev/null 2>&1; then
        apk add sudo
    else
        die "No supported package manager found (apt/dnf/yum/pacman/zypper/apk). Install sudo manually and re-run."
    fi
    info "sudo installed successfully."
fi

# ---------------------------------------------------------------------------
# 2. Ask for the username (validated against useradd naming rules)
# ---------------------------------------------------------------------------
while true; do
    read -rp "Username for the new user: " USERNAME
    if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        warn "Invalid username. Use 1-32 characters: lowercase letters, digits, '-' or '_', starting with a letter or '_'."
    elif id "$USERNAME" &>/dev/null; then
        warn "User '$USERNAME' already exists. Choose a different name."
    else
        break
    fi
done

# ---------------------------------------------------------------------------
# 3. Ask for the password (hidden input, asked twice)
# ---------------------------------------------------------------------------
while true; do
    read -rsp "Password for '$USERNAME': " PASSWORD; echo
    read -rsp "Confirm password: " PASSWORD_CONFIRM; echo
    if [[ -z "$PASSWORD" ]]; then
        warn "Password cannot be empty. Try again."
    elif [[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]]; then
        warn "Passwords do not match. Try again."
    else
        break
    fi
done
unset PASSWORD_CONFIRM

# ---------------------------------------------------------------------------
# 4. Create the user with a home directory and set the password
# ---------------------------------------------------------------------------
LOGIN_SHELL="$(command -v bash || echo /bin/sh)"

useradd -m -s "$LOGIN_SHELL" "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd
unset PASSWORD   # drop it from the environment/memory as early as possible

info "User '$USERNAME' created with home directory and shell: $LOGIN_SHELL"

# ---------------------------------------------------------------------------
# 5. Ask whether the user should be a sudoer, and add them to the group
# ---------------------------------------------------------------------------
if getent group sudo >/dev/null 2>&1; then
    SUDO_GROUP="sudo"
elif getent group wheel >/dev/null 2>&1; then
    SUDO_GROUP="wheel"   # RHEL/Fedora-family name for the admin group
else
    SUDO_GROUP=""
fi

read -rp "Grant '$USERNAME' sudo (administrative) privileges? [y/N]: " ANSWER
ANSWER="${ANSWER,,}"

ADDED_TO_GROUP="no"
if [[ "$ANSWER" == y* ]]; then
    if [[ -n "$SUDO_GROUP" ]]; then
        usermod -aG "$SUDO_GROUP" "$USERNAME"
        ADDED_TO_GROUP="yes"
        info "User '$USERNAME' added to the '$SUDO_GROUP' group."
    else
        warn "No 'sudo' or 'wheel' group exists on this system. Add the user to sudoers manually (visudo)."
    fi
else
    info "User '$USERNAME' was NOT granted sudo privileges."
fi

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
echo
info "Summary:"
echo "  Username:        $USERNAME"
echo "  Home directory:  $(getent passwd "$USERNAME" | cut -d: -f6)"
echo "  Shell:           $LOGIN_SHELL"
echo "  Sudo privileges: $ADDED_TO_GROUP${ADDED_TO_GROUP:+ (group: $SUDO_GROUP)}"
