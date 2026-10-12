# pve-lxc-maintenance.sh

Batch maintenance for **LXC containers on a Proxmox VE host**: take safety
snapshots before changes, run apt updates across every container with a
per-container pass/fail summary, and roll back when an update breaks
something.

## Modes

| Mode | What it does |
|------|--------------|
| `snapshot` | `pct snapshot` on each selected (running) CT, timestamped `pre-YYYYmmdd-HHMMSS`, with an optional note |
| `update` | Per CT: (optional safety snapshot) → `apt-get update && apt-get upgrade` via `pct exec` → OK/FAILED summary; non-Debian and stopped CTs are skipped with a note |
| `rollback` | Stop (if running, with `--force`) → `pct rollback` → restart |
| `list` | `pct list` — see IDs and states |

## Usage

```bash
# Snapshot every running container before a maintenance window
sudo ./pve-lxc-maintenance.sh snapshot --all --note "before patching evening"

# Update ALL running Debian containers (auto-snapshot each first)
sudo ./pve-lxc-maintenance.sh update --all

# Update only two containers, skip the safety snapshots
sudo ./pve-lxc-maintenance.sh update --ctid 101,104 --no-snapshot

# Pass extra args to apt (e.g. also dist-upgrade)
sudo ./pve-lxc-maintenance.sh update --all --extra-args "--with-new-pkgs"

# Something broke? See snapshots, then roll back one container
pct listsnapshot 103
sudo ./pve-lxc-maintenance.sh rollback --ctid 103 --snap pre-20260112-220001 --force

# Quick overview
sudo ./pve-lxc-maintenance.sh list
```

## Exit codes

- `0` — everything selected succeeded
- `1` — at least one CT failed (see the per-CT summary); failed CTs keep
  their **pre-update snapshot** so you can roll back individually

## Notes & troubleshooting

- **Safety first**: `update` takes a snapshot per CT *before* upgrading —
  pass `--no-snapshot` to skip (faster, but no one-click undo).
- **Rollback of a running CT** requires stopping it; the script refuses
  unless you pass `--force` (stop → rollback → start).
- **Non-Debian containers** (Alpine, etc.) are detected and skipped in
  `update` mode.
- Snapshots are cheap but not backups — for real backups use Proxmox
  vzdump/PBS on a schedule.
- CTs that are stopped are never touched (snapshots/updates skip them).
