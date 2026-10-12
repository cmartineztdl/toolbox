# toolbox

Reusable scripts, tools and utilities for Linux system administration and
automation.

## Contents

| Script | Description | Docs |
|--------|-------------|------|
| [`create-sudo-user.sh`](scripts/create-sudo-user.sh) | Install sudo (if missing), create a new user with home directory, optionally grant sudo privileges | [docs/create-sudo-user.md](docs/create-sudo-user.md) |

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
