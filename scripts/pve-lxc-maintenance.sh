#!/usr/bin/env bash
#
# pve-lxc-maintenance.sh — batch maintenance for LXC containers on a
# Proxmox VE host: safety snapshots before changes, apt updates across
# every container with a pass/fail summary, and snapshot rollback.
#
# Usage:
#   sudo ./pve-lxc-maintenance.sh snapshot [--all|--ctid N[,M...]] [--note TEXT]
#   sudo ./pve-lxc-maintenance.sh update   [--all|--ctid N[,M...]] [--no-snapshot] [--extra-args "..."]
#   sudo ./pve-lxc-maintenance.sh rollback --ctid N --snap NAME [--force]
#   sudo ./pve-lxc-maintenance.sh list
#
# License: MIT (see LICENSE in the repository root)

set -euo pipefail

info() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Pre-flight
# ---------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "Run as root on the Proxmox host (sudo ./pve-lxc-maintenance.sh)."
command -v pct >/dev/null 2>&1 || die "'pct' not found — this script must run on a Proxmox VE host."

MODE_RE='^(snapshot|update|rollback|list)$'
MODE="${1:-}"; shift || true
[[ "$MODE" =~ $MODE_RE ]] || die "Mode must be: snapshot | update | rollback | list (see --help)"

TARGET="" NOTE="auto maintenance" NO_SNAPSHOT=0 EXTRA_ARGS="" SNAP_NAME="" FORCE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)         TARGET="all"; shift ;;
        --ctid)        TARGET="$2"; shift 2 ;;
        --note)        NOTE="$2"; shift 2 ;;
        --no-snapshot) NO_SNAPSHOT=1; shift ;;
        --extra-args)  EXTRA_ARGS="$2"; shift 2 ;;
        --snap)        SNAP_NAME="$2"; shift 2 ;;
        --force)       FORCE=1; shift ;;
        *) die "Unknown argument for $MODE: $1 (see --help)" ;;
    esac
done

# ---------------------------------------------------------------------------
# 2. Helpers
# ---------------------------------------------------------------------------
# List container IDs. Scope: all (any state) or an explicit comma list.
select_cts() {
    if [[ -z "$TARGET" ]]; then die "Specify --all or --ctid N[,M...] for mode '$MODE'."; fi
    if [[ "$TARGET" == "all" ]]; then
        pct list 2>/dev/null | awk 'NR>1 {print $1}'
    else
        IFS=',' read -ra IDS <<<"$TARGET"
        for id in "${IDS[@]}"; do
            [[ "$id" =~ ^[0-9]+$ ]] || die "Invalid CTID '$id'."
            pct status "$id" &>/dev/null || die "CTID $id does not exist."
        done
        printf '%s\n' "${IDS[@]}"
    fi
}

is_running() { [[ "$(pct status "$1" 2>/dev/null | awk '{print $2}')" == "running" ]]; }

# ---------------------------------------------------------------------------
# 3. Mode: list
# ---------------------------------------------------------------------------
if [[ "$MODE" == "list" ]]; then
    pct list
    exit 0
fi

# ---------------------------------------------------------------------------
# 4. Mode: snapshot
# ---------------------------------------------------------------------------
make_snapshot() {
    local id="$1" name
    name="pre-$(date +%Y%m%d-%H%M%S)"
    if pct listsnapshot "$id" 2>/dev/null | grep -q "$name"; then
        warn "CT $id: snapshot '$name' already exists — skipped."
        return 0
    fi
    if pct snapshot "$id" "$name" --description "$NOTE" >/dev/null 2>&1; then
        info "CT $id: snapshot '$name' created ($NOTE)"
    else
        warn "CT $id: snapshot FAILED"
        return 1
    fi
}

if [[ "$MODE" == "snapshot" ]]; then
    FAIL=0
    while read -r id; do
        make_snapshot "$id" || FAIL=1
    done < <(select_cts)
    exit $FAIL
fi

# ---------------------------------------------------------------------------
# 5. Mode: rollback
# ---------------------------------------------------------------------------
if [[ "$MODE" == "rollback" ]]; then
    [[ -n "$TARGET" && "$TARGET" != "all" ]] || die "rollback needs a single --ctid N (never --all)."
    CTID_RE='^[0-9]+$'
    [[ "$TARGET" =~ $CTID_RE ]] || die "rollback needs exactly one numeric --ctid (not a list, never --all)."
    [[ -n "$SNAP_NAME" ]] || die "rollback needs --snap NAME (see names with: pct listsnapshot $TARGET)"
    pct listsnapshot "$TARGET" 2>/dev/null | grep -q "$SNAP_NAME" || die "Snapshot '$SNAP_NAME' not found on CT $TARGET."
    if is_running "$TARGET"; then
        if [[ "$FORCE" -eq 1 ]]; then
            warn "CT $TARGET is running — stopping it for rollback (--force)..."
            pct stop "$TARGET" >/dev/null
            STOPPED=1
        else
            die "CT $TARGET is running. Rollback requires stopping it — re-run with --force to stop+rollback+start."
        fi
    fi
    pct rollback "$TARGET" "$SNAP_NAME" >/dev/null
    info "CT $TARGET rolled back to '$SNAP_NAME'."
    if [[ "${STOPPED:-0}" -eq 1 ]]; then
        pct start "$TARGET" >/dev/null
        info "CT $TARGET restarted."
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# 6. Mode: update
# ---------------------------------------------------------------------------
RESULTS=()
FAIL=0
while read -r id; do
    if ! is_running "$id"; then
        warn "CT $id: not running — skipped (start it first or update it manually)."
        RESULTS+=("CT $id: SKIPPED (stopped)")
        continue
    fi
    if [[ "$NO_SNAPSHOT" -eq 0 ]]; then
        make_snapshot "$id" || true   # a failed snapshot warns but does not abort the batch
    fi
    if ! pct exec "$id" -- sh -c 'command -v apt-get' >/dev/null 2>&1; then
        warn "CT $id: no apt-get (non-Debian) — skipped."
        RESULTS+=("CT $id: SKIPPED (no apt)")
        continue
    fi
    info "CT $id: updating (this may take a while)..."
    if pct exec "$id" -- env DEBIAN_FRONTEND=noninteractive \
        bash -c "apt-get update -qq && apt-get -y -qq upgrade $EXTRA_ARGS" >/dev/null 2>&1; then
        info "CT $id: update OK"
        RESULTS+=("CT $id: OK")
    else
        warn "CT $id: update FAILED — check with: pct exec $id -- apt-get upgrade"
        RESULTS+=("CT $id: FAILED")
        FAIL=1
    fi
done < <(select_cts)

echo
info "Update summary:"
printf '  %s\n' "${RESULTS[@]}"
exit $FAIL
