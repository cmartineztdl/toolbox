# pve-lxc-create.sh

One command from zero to a **ready-to-use Debian LXC container** on a
Proxmox VE host. It handles the whole routine: template download, container
creation, boot, network wait, and an automatic **in-container bootstrap**
(via [`debian-bootstrap.sh`](debian-bootstrap.md)) that upgrades the system,
installs sudo, and creates your admin user.

## What it does

1. Verifies it runs as **root on the Proxmox host** (`pct` must exist)
2. **Auto-picks** a free CTID (or take `--ctid`) and a storage (or take `--storage`)
3. **Downloads the Debian template** with `pveam` if not already present
4. Creates an **unprivileged** container (default) with `pct create`:
   cores/memory/disk sized via flags, DHCP or static IP, start-on-boot
5. Starts it and **waits for networking** inside the container
6. Pushes `debian-bootstrap.sh` into the container and runs it — full
   upgrade, sudo, your user + password (given or auto-generated, printed
   once), optional SSH key and timezone
7. Prints a **summary** with CTID, IP, user, and the `pct enter` command

## Requirements

- Proxmox VE host, run as root
- `debian-bootstrap.sh` from this repository **in the same directory**
  (it is pushed into the container for the bootstrap step)

## Usage

```bash
# Everyday case: new container 'web1' with admin user alice (random password)
sudo ./pve-lxc-create.sh --hostname web1 --user alice --gen-password \
    --sshkey "$(cat ~/.ssh/id_ed25519.pub)" --tz Europe/Madrid

# Fully specified: fixed CTID, static IP, resources
sudo ./pve-lxc-create.sh --hostname db1 --ctid 110 --user bob --password 'S3cr3t!' \
    --storage local-lvm --bridge vmbr0 --ip 192.168.1.110/24 \
    --cores 2 --memory 2048 --disk 16

# Minimal: create + upgrade only, no user
sudo ./pve-lxc-create.sh --hostname scratch --no-bootstrap
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--hostname NAME` | *(required)* | Container hostname |
| `--ctid N` | auto | Container ID (auto-assigned next free) |
| `--user NAME` | *(required unless `--no-bootstrap`)* | Admin user created inside |
| `--password SECRET` | — | Password for the user |
| `--gen-password` | — | Generate a random password (printed once in the bootstrap output) |
| `--sshkey KEY` | — | SSH public key installed for the user |
| `--tz Area/City` | — | Container timezone |
| `--storage NAME` | auto-detected | Proxmox storage for the root disk |
| `--bridge NAME` | `vmbr0` | Network bridge |
| `--ip dhcp\|CIDR` | `dhcp` | Container IP (static without mask gets `/24` + default gw) |
| `--cores N` | `1` | CPU cores |
| `--memory MB` | `512` | RAM in MB |
| `--disk GB` | `8` | Root disk size in GB |
| `--debian VER` | `12` | Debian template version |
| `--privileged` | unprivileged | Create a privileged container (avoid unless needed) |
| `--no-bootstrap` | — | Skip the in-container bootstrap step |

## Notes & troubleshooting

- **Generated passwords** appear once in the bootstrap output — store them
  immediately.
- `--password` is visible in the host's process list for the duration of the
  bootstrap exec — for anything sensitive prefer `--gen-password` or SSH-key
  only (`--sshkey`, no password flag).
- **Static IP**: pass it with a mask (`10.0.0.10/24`); without a mask the
  script appends `/24` and the host's default gateway.
- If the bootstrap fails mid-way, the container stays up for inspection:
  `pct enter <ctid> && bash /tmp/debian-bootstrap.sh`.
- To delete a test container: `pct destroy <ctid>`.
