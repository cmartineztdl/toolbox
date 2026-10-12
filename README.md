# toolbox

Reusable scripts, tools and utilities for Linux system administration and
automation.

## Contents

| Script | Description | Docs |
|--------|-------------|------|
| [`create-sudo-user.sh`](scripts/create-sudo-user.sh) | Install sudo (if missing), create a new user with home directory, optionally grant sudo privileges (interactive) | [docs/create-sudo-user.md](docs/create-sudo-user.md) |
| [`debian-bootstrap.sh`](scripts/debian-bootstrap.sh) | Non-interactive post-install for fresh Debian (LXC/VM/bare metal): upgrade, base packages, user + sudo, timezone, SSH key, unattended upgrades | [docs/debian-bootstrap.md](docs/debian-bootstrap.md) |
| [`pve-lxc-create.sh`](scripts/pve-lxc-create.sh) | Proxmox host: create a ready-to-use Debian LXC in one command (template + `pct create` + automatic in-container bootstrap) | [docs/pve-lxc-create.md](docs/pve-lxc-create.md) |
| [`pve-lxc-maintenance.sh`](scripts/pve-lxc-maintenance.sh) | Proxmox host: batch safety snapshots, apt updates across all CTs with pass/fail summary, snapshot rollback | [docs/pve-lxc-maintenance.md](docs/pve-lxc-maintenance.md) |

## Usage

Scripts live in [`scripts/`](scripts/) and their usage guides in
[`docs/`](docs/). Most system scripts must run as root:

```bash
git clone https://github.com/cmartineztdl/toolbox.git
cd toolbox
sudo ./scripts/create-sudo-user.sh
```

## License

MIT — see [LICENSE](LICENSE).
