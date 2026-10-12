# debian-bootstrap.sh

Non-interactive post-install for **fresh Debian systems** — LXC containers,
VMs, or bare metal. It automates the routine you repeat on every new Debian:
full upgrade, base packages, an admin user with password + sudo, timezone,
SSH key, and unattended security updates.

## What it does

1. Verifies it runs as **root** on a Debian/Ubuntu system
2. **Full upgrade** (`apt-get update && apt-get upgrade`, skippable)
3. Installs **base packages**: sudo, curl, wget, git, vim, htop,
   ca-certificates, gnupg, unzip, bash-completion (+ any extras you pass)
4. Sets the **timezone** (LXC-safe — no `timedatectl` dependency)
5. Creates/updates a **user**:
   - valid username (Linux rules), home directory, bash shell
   - **password** (given, or auto-generated and printed once)
   - added to the **sudo** group (`wheel` fallback on RHEL-family)
6. Installs an **SSH public key** for the user (installs `openssh-server`
   first if missing — LXC templates often lack it)
7. Enables **unattended-upgrades** (automatic security patches)
8. Prints a **summary**; generated passwords are shown once, never stored

## Requirements

- Debian (or Ubuntu) with `apt-get`, run as root
- Any environment: LXC, VM, physical server

## Usage

```bash
# Typical LXC first-boot: user + generated password + your key
sudo ./debian-bootstrap.sh --user alice --gen-password --sshkey "$(cat ~/.ssh/id_ed25519.pub)" --tz Europe/Madrid

# Known password, extra packages, no upgrade step
sudo ./debian-bootstrap.sh --user alice --password 'S3cr3t!' --extra-pkg "jq,ncdu" --no-upgrade

# Just upgrade + base packages, no user changes
sudo ./debian-bootstrap.sh

# One-liner on a fresh container
curl -fsSL https://raw.githubusercontent.com/cmartineztdl/toolbox/main/scripts/debian-bootstrap.sh -o bootstrap.sh
sudo bash bootstrap.sh --user alice --gen-password
```

### Flags

| Flag | Description |
|------|-------------|
| `--user NAME` | Create (or update) this user |
| `--password SECRET` | Set this password for the user |
| `--gen-password` | Generate a random password and print it once |
| `--sshkey KEY` | OpenSSH public key to install for the user |
| `--tz Area/City` | Timezone (must exist under `/usr/share/zoneinfo`) |
| `--extra-pkg "a,b"` | Comma-separated extra packages to install |
| `--no-upgrade` | Skip the system upgrade step |

## Pairing with pve-lxc-create.sh

This script is what [`pve-lxc-create.sh`](pve-lxc-create.md) pushes into new
containers and runs automatically — you normally never call it by hand for
LXC; use it standalone for VMs and bare-metal machines.

## Notes & troubleshooting

- **Idempotent**: safe to re-run; existing users get their settings updated
  instead of an error.
- **Generated passwords** are printed to stdout once and never written to
  disk — store them immediately (password manager, Proxmox notes, etc.).
- **Unprivileged LXC**: everything here works unprivileged; only the
  timezone step needs `/usr/share/zoneinfo` to exist in the template.
- **Root SSH password login** is not modified — harden `sshd_config` per your
  policy after bootstrap if desired.
