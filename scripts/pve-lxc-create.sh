#!/usr/bin/env bash
#
# pve-lxc-create.sh — create a ready-to-use Debian LXC container on a
# Proxmox VE host in one command: template download, container creation,
# boot, and (by default) an automatic in-container bootstrap that upgrades
# the system, installs sudo, and creates your admin user (via
# debian-bootstrap.sh from this repository).
#
# Usage:
#   sudo ./pve-lxc-create.sh --hostname web1 [--ctid 101] [--user alice]
#        [--password SECRET | --gen-password] [--sshkey "ssh-ed25519 AAA..."]
#        [--storage local-lvm] [--bridge vmbr0] [--ip dhcp | --ip 10.0.0.10/24]
#        [--cores 2] [--memory 1024] [--disk 8] [--debian 12]
#        [--privileged] [--no-bootstrap]
#
# License: MIT (see LICENSE in the repository root)

set -euo pipefail

info() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Pre-flight: root + Proxmox host
# ---------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "Run as root on the Proxmox host (sudo ./pve-lxc-create.sh)."
command -v pct >/dev/null 2>&1 || die "'pct' not found — this script must run on a Proxmox VE host."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="$SCRIPT_DIR/debian-bootstrap.sh"
[[ -f "$BOOTSTRAP" ]] || die "debian-bootstrap.sh not found next to this script (needed for the bootstrap step). Download the full repository."

# ---------------------------------------------------------------------------
# 2. Arguments
# ---------------------------------------------------------------------------
HOSTNAME_ARG="" CTID="" USER_ARG="" PASSWORD="" GENPW=0 SSHKEY="" TZ_ARG=""
STORAGE="" BRIDGE="vmbr0" IP="dhcp" CORES=1 MEMORY=512 DISK=8 DEBIAN_VER="12" PRIVILEGED=0 NO_BOOTSTRAP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hostname)    HOSTNAME_ARG="$2"; shift 2 ;;
        --ctid)        CTID="$2"; shift 2 ;;
        --user)        USER_ARG="$2"; shift 2 ;;
        --password)    PASSWORD="$2"; shift 2 ;;
        --gen-password) GENPW=1; shift ;;
        --sshkey)      SSHKEY="$2"; shift 2 ;;
        --tz)          TZ_ARG="$2"; shift 2 ;;
        --storage)     STORAGE="$2"; shift 2 ;;
        --bridge)      BRIDGE="$2"; shift 2 ;;
        --ip)          IP="$2"; shift 2 ;;
        --cores)       CORES="$2"; shift 2 ;;
        --memory)      MEMORY="$2"; shift 2 ;;
        --disk)        DISK="$2"; shift 2 ;;
        --debian)      DEBIAN_VER="$2"; shift 2 ;;
        --privileged)  PRIVILEGED=1; shift ;;
        --no-bootstrap) NO_BOOTSTRAP=1; shift ;;
        *) die "Unknown argument: $1 (see --help)" ;;
    esac
done

[[ -n "$HOSTNAME_ARG" ]] || die "--hostname is required."
[[ "$HOSTNAME_ARG" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]] || die "Invalid hostname '$HOSTNAME_ARG'."
if [[ -n "$PASSWORD" && "$GENPW" -eq 1 ]]; then
    die "Use either --password or --gen-password, not both."
fi
[[ -n "$USER_ARG" || "$NO_BOOTSTRAP" -eq 1 ]] || die "Give --user (for the bootstrap) or pass --no-bootstrap."

if [[ -z "$STORAGE" ]]; then
    STORAGE="$(pvesh get /nodes/$(hostname)/storage --output-format json 2>/dev/null | grep -o '"storage":"[^"]*"' | head -1 | cut -d'"' -f4)"
    [[ -n "$STORAGE" ]] || STORAGE="local-lvm"
    info "Auto-detected storage: $STORAGE"
fi

if [[ -z "$CTID" ]]; then
    CTID="$(pvesh get /cluster/nextid)"
    info "Auto-assigned CTID: $CTID"
fi
pct status "$CTID" &>/dev/null && die "CTID $CTID already exists. Choose another with --ctid."

# ---------------------------------------------------------------------------
# 3. Debian template (download if missing)
# ---------------------------------------------------------------------------
pveam available >/dev/null 2>&1 || pveam update >/dev/null
TEMPLATE="$(pveam list local 2>/dev/null | grep "debian-${DEBIAN_VER}-standard" | awk '{print $1}' | head -1)"
if [[ -z "$TEMPLATE" ]]; then
    info "Downloading Debian ${DEBIAN_VER} LXC template (one-time)..."
    TEMPLATE="$(pveam available --section system 2>/dev/null | grep "debian-${DEBIAN_VER}-standard" | awk '{print $2}' | sort -V | tail -1)"
    [[ -n "$TEMPLATE" ]] || die "No debian-${DEBIAN_VER}-standard template found in pveam (try --debian 12)."
    pveam download local "$TEMPLATE" >/dev/null
    TEMPLATE="local:vztmpl/${TEMPLATE##*/}"
    info "Template downloaded: $TEMPLATE"
else
    info "Template found: $TEMPLATE"
fi

# ---------------------------------------------------------------------------
# 4. Create the container
# ---------------------------------------------------------------------------
UNPRIV_FLAG="--unprivileged"; [[ "$PRIVILEGED" -eq 1 ]] && UNPRIV_FLAG=""
NET_FLAG="name=eth0,bridge=${BRIDGE},ip=${IP}"
[[ "$IP" != "dhcp" && "$IP" != *"/"* ]] && NET_FLAG="${NET_FLAG}/24,gw=$(ip -4 route show default | awk '{print $3}')"

info "Creating container $CTID ('$HOSTNAME_ARG') on $STORAGE..."
pct create "$CTID" "$TEMPLATE" \
    --hostname "$HOSTNAME_ARG" \
    --storage "$STORAGE" \
    --rootfs "${DISK}G" \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --swap 512 \
    --net0 "$NET_FLAG" \
    $UNPRIV_FLAG \
    --onboot 1 \
    --start 1 >/dev/null
info "Container created and started."

# ---------------------------------------------------------------------------
# 5. Wait for network inside the container
# ---------------------------------------------------------------------------
info "Waiting for network inside the container..."
for _ in $(seq 1 15); do
    if pct exec "$CTID" -- getent hosts debian.org >/dev/null 2>&1; then
        NET_OK=1; break
    fi
    sleep 2
done
[[ "${NET_OK:-0}" -eq 1 ]] || warn "Network not confirmed after 30s — bootstrap may fail; check container networking."

# ---------------------------------------------------------------------------
# 6. Bootstrap inside the container (upgrade + sudo + user)
# ---------------------------------------------------------------------------
IP_GOT="$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}')"
if [[ "$NO_BOOTSTRAP" -eq 0 ]]; then
    info "Pushing debian-bootstrap.sh into the container..."
    pct push "$CTID" "$BOOTSTRAP" /tmp/debian-bootstrap.sh >/dev/null
    BOOT_ARGS=(--user "$USER_ARG")
    [[ -n "$PASSWORD" ]] && BOOT_ARGS+=(--password "$PASSWORD")
    [[ -n "$SSHKEY" ]] && BOOT_ARGS+=(--sshkey "$SSHKEY")
    [[ -n "$TZ_ARG" ]] && BOOT_ARGS+=(--tz "$TZ_ARG")
    if pct exec "$CTID" -- bash /tmp/debian-bootstrap.sh "${BOOT_ARGS[@]}"; then
        pct exec "$CTID" -- rm -f /tmp/debian-bootstrap.sh >/dev/null
        info "Bootstrap finished."
    else
        warn "Bootstrap failed — inspect manually: pct enter $CTID && bash /tmp/debian-bootstrap.sh"
    fi
fi

# ---------------------------------------------------------------------------
# 7. Summary
# ---------------------------------------------------------------------------
echo
info "Container ready. Summary:"
echo "  CTID:        $CTID"
echo "  Hostname:    $HOSTNAME_ARG"
echo "  IP:          ${IP_GOT:-<pending DHCP>}"
echo "  User:        ${USER_ARG:-<none>}"
[[ -n "$USER_ARG" && "$GENPW" -eq 1 ]] && echo "  Password:    see bootstrap output above (shown once)"
echo
echo "  Enter it:    pct enter $CTID"
[[ "$IP" == "dhcp" ]] && echo "  SSH:         ssh ${USER_ARG:-root}@${IP_GOT:-<check 'pct config $CTID'>}"
