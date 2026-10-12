#!/usr/bin/env bash
#
# debian-bootstrap.sh — non-interactive post-install for fresh Debian systems
# (LXC containers, VMs, bare metal). Performs the routine you repeat on every
# new Debian: full upgrade, base packages, a user with password + sudo,
# timezone, SSH key, unattended security updates.
#
# Usage:
#   sudo ./debian-bootstrap.sh --user alice [--password SECRET | --gen-password]
#                              [--sshkey "ssh-ed25519 AAAA..."] [--tz Europe/Madrid]
#                              [--extra-pkg "jq,ncdu"] [--no-upgrade]
#
# All flags are optional except that either --user (to create/modify a user)
# or nothing at all (then it only upgrades + installs base packages) is fine.
# License: MIT (see LICENSE in the repository root)

set -euo pipefail

info() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive

# --help must work without root
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Pre-flight and argument parsing
# ---------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "Run as root (sudo ./debian-bootstrap.sh)."
command -v apt-get >/dev/null 2>&1 || die "This script targets Debian/Ubuntu (apt-get not found)."
command -v useradd  >/dev/null 2>&1 || die "'useradd' not found — install the 'shadow' package on minimal systems."
command -v chpasswd >/dev/null 2>&1 || die "'chpasswd' not found — install the 'shadow' package on minimal systems."

OPT_USER="" OPT_PASSWORD="" OPT_SSHKEY="" OPT_TZ="" OPT_PKGS="" OPT_NO_UPGRADE=0 OPT_GENPW=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)        OPT_USER="$2"; shift 2 ;;
        --password)    OPT_PASSWORD="$2"; shift 2 ;;
        --gen-password) OPT_GENPW=1; shift ;;
        --sshkey)      OPT_SSHKEY="$2"; shift 2 ;;
        --tz)          OPT_TZ="$2"; shift 2 ;;
        --extra-pkg)   OPT_PKGS="$2"; shift 2 ;;
        --no-upgrade)  OPT_NO_UPGRADE=1; shift ;;
        -h|--help)     sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "Unknown argument: $1 (see --help)" ;;
    esac
done

if [[ -n "$OPT_PASSWORD" && "$OPT_GENPW" -eq 1 ]]; then
    die "Use either --password or --gen-password, not both."
fi
if [[ -n "$OPT_USER" && ! "$OPT_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    die "Invalid username '$OPT_USER': 1-32 chars, lowercase letters, digits, '-', '_', starting with a letter or '_'."
fi
SSH_KEY_RE='^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)[[:space:]][A-Za-z0-9+/=]+'
if [[ -n "$OPT_SSHKEY" ]]; then
    if [[ ! "$OPT_SSHKEY" =~ $SSH_KEY_RE ]]; then
        die "--sshkey does not look like a valid OpenSSH public key."
    fi
fi

GENERATED_PASSWORD=""
if [[ -n "$OPT_USER" && "$OPT_GENPW" -eq 1 ]]; then
    if command -v openssl >/dev/null 2>&1; then
        GENERATED_PASSWORD="$(openssl rand -base64 18 | tr -d '/+=')"
    else
        GENERATED_PASSWORD="$(head -c 24 /dev/urandom | base64 | tr -d '/+=\n')"
    fi
    OPT_PASSWORD="$GENERATED_PASSWORD"
fi

# ---------------------------------------------------------------------------
# 2. Upgrade + base packages
# ---------------------------------------------------------------------------
if [[ "$OPT_NO_UPGRADE" -eq 0 ]]; then
    info "Updating package lists and upgrading the system (this can take a while)..."
    apt-get update -qq
    apt-get -y -qq upgrade
    info "System is up to date."
else
    info "Skipping upgrade (--no-upgrade)."
fi

BASE_PKGS=(sudo curl wget git vim htop ca-certificates gnupg unzip bash-completion)
if [[ -n "$OPT_PKGS" ]]; then
    IFS=',' read -ra EXTRA <<<"$OPT_PKGS"
    BASE_PKGS+=("${EXTRA[@]}")
fi
info "Installing base packages: ${BASE_PKGS[*]}"
apt-get -y -qq install "${BASE_PKGS[@]}" >/dev/null

# ---------------------------------------------------------------------------
# 3. Timezone (LXC-safe: no reliance on timedatectl)
# ---------------------------------------------------------------------------
if [[ -n "$OPT_TZ" ]]; then
    if [[ -f "/usr/share/zoneinfo/$OPT_TZ" ]]; then
        ln -sf "/usr/share/zoneinfo/$OPT_TZ" /etc/localtime
        echo "$OPT_TZ" > /etc/timezone
        info "Timezone set to $OPT_TZ."
    else
        warn "Timezone '$OPT_TZ' not found in /usr/share/zoneinfo — skipped."
    fi
fi

# ---------------------------------------------------------------------------
# 4. User creation / update (password + sudo group)
# ---------------------------------------------------------------------------
SUDO_GROUP=""
if getent group sudo >/dev/null 2>&1; then SUDO_GROUP="sudo"
elif getent group wheel >/dev/null 2>&1; then SUDO_GROUP="wheel"; fi

if [[ -n "$OPT_USER" ]]; then
    if id "$OPT_USER" &>/dev/null; then
        info "User '$OPT_USER' already exists — updating settings only."
    else
        LOGIN_SHELL="$(command -v bash || echo /bin/sh)"
        useradd -m -s "$LOGIN_SHELL" "$OPT_USER"
        info "User '$OPT_USER' created (home: $(getent passwd "$OPT_USER" | cut -d: -f6))."
    fi
    if [[ -n "$OPT_PASSWORD" ]]; then
        echo "$OPT_USER:$OPT_PASSWORD" | chpasswd
        info "Password set for '$OPT_USER'."
    else
        warn "No password provided (--password/--gen-password) — password login stays unset for '$OPT_USER'."
    fi
    if [[ -n "$SUDO_GROUP" ]] && ! id -nG "$OPT_USER" | grep -qw "$SUDO_GROUP"; then
        usermod -aG "$SUDO_GROUP" "$OPT_USER"
        info "'$OPT_USER' added to the '$SUDO_GROUP' group (sudo enabled)."
    fi
fi

# ---------------------------------------------------------------------------
# 5. SSH key (ensures openssh-server exists; LXC templates often lack it)
# ---------------------------------------------------------------------------
if [[ -n "$OPT_SSHKEY" && -n "$OPT_USER" ]]; then
    dpkg -s openssh-server >/dev/null 2>&1 || { info "Installing openssh-server..."; apt-get -y -qq install openssh-server >/dev/null; }
    USER_HOME="$(getent passwd "$OPT_USER" | cut -d: -f6)"
    install -d -m 700 -o "$OPT_USER" -g "$OPT_USER" "$USER_HOME/.ssh"
    grep -qxF "$OPT_SSHKEY" "$USER_HOME/.ssh/authorized_keys" 2>/dev/null || echo "$OPT_SSHKEY" >> "$USER_HOME/.ssh/authorized_keys"
    chown "$OPT_USER:$OPT_USER" "$USER_HOME/.ssh/authorized_keys"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
    info "SSH public key installed for '$OPT_USER'."
fi

# ---------------------------------------------------------------------------
# 6. Unattended security upgrades
# ---------------------------------------------------------------------------
if ! dpkg -s unattended-upgrades >/dev/null 2>&1; then
    info "Enabling unattended security upgrades..."
    apt-get -y -qq install unattended-upgrades >/dev/null
    echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | debconf-set-selections
    dpkg-reconfigure -f noninteractive unattended-upgrades >/dev/null
    info "Unattended upgrades enabled."
fi

# ---------------------------------------------------------------------------
# 7. Summary
# ---------------------------------------------------------------------------
echo
info "Bootstrap complete. Summary:"
echo "  System:          upgraded=$([[ $OPT_NO_UPGRADE -eq 0 ]] && echo yes || echo no)"
echo "  User:            ${OPT_USER:-<none>}"
[[ -n "$OPT_USER" ]] && echo "  Sudo group:      $(id -nG "$OPT_USER" 2>/dev/null | grep -qw "${SUDO_GROUP:-sudo}" && echo yes || echo "no (group: ${SUDO_GROUP:-<missing>})")"
[[ -n "$GENERATED_PASSWORD" ]] && {
    echo "  Password:        (generated, shown once)"
    echo "                   $GENERATED_PASSWORD"
}
[[ -n "$OPT_SSHKEY" ]] && echo "  SSH key:         installed"
echo "  Unattended-upg:  enabled"
echo
warn "If you generated a password, store it now — it is not saved anywhere."
