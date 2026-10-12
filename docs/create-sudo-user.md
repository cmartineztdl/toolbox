# create-sudo-user.sh

Interactive helper for fresh Linux servers/containers: it installs **sudo** if
missing, creates a **new user with a home directory**, and — if you choose —
grants that user **administrative (sudo) privileges**.

## What it does

1. **Checks that it runs as root** — installing sudo and creating users
   requires it. Run it with `sudo` (or directly as root).
2. **Installs sudo** if the `sudo` binary is not present. Supported package
   managers: `apt`, `dnf`, `yum`, `pacman`, `zypper`, `apk`.
3. **Asks for a username** and validates it against Linux naming rules
   (1–32 chars: lowercase letters, digits, `-`, `_`; must start with a letter
   or `_`; must not already exist).
4. **Asks for a password** — input is hidden and asked twice with
   confirmation. The password is never stored in a file; it is passed to
   `chpasswd` over stdin and discarded from memory right after.
5. **Creates the user** with `useradd -m` (home directory is created) and
   sets **bash** as the login shell (falls back to `/bin/sh` if bash is not
   available).
6. **Asks whether the user should be a sudoer** — if you answer `y`, the user
   is added to the admin group (`sudo`; on RHEL-family systems it falls back
   to `wheel`). Anything other than `y`/`yes` leaves the user without sudo.
7. Prints a **summary** of what was created.

## Requirements

- Linux with one of the supported package managers (Debian/Ubuntu, Fedora/
  RHEL, Arch, openSUSE, Alpine)
- Run as root: `sudo ./create-sudo-user.sh`

## Usage

```bash
# Option A — clone the repository
git clone https://github.com/cmartineztdl/toolbox.git
cd toolbox
chmod +x scripts/create-sudo-user.sh
sudo ./scripts/create-sudo-user.sh

# Option B — one-liner download
curl -fsSL https://raw.githubusercontent.com/cmartineztdl/toolbox/main/scripts/create-sudo-user.sh -o create-sudo-user.sh
chmod +x create-sudo-user.sh
sudo ./create-sudo-user.sh
```

### Example session

```text
$ sudo ./create-sudo-user.sh
[+] sudo is already installed.
Username for the new user: alice
Password for 'alice':
Confirm password:
[+] User 'alice' created with home directory and shell: /usr/bin/bash
Grant 'alice' sudo (administrative) privileges? [y/N]: y
[+] User 'alice' added to the 'sudo' group.

[+] Summary:
  Username:        alice
  Home directory:  /home/alice
  Shell:           /usr/bin/bash
  Sudo privileges: yes (group: sudo)
```

## Equivalent manual commands

What the script automates, for reference:

```bash
sudo apt-get install sudo          # 1. install sudo (Debian/Ubuntu)
sudo useradd -m -s /bin/bash alice # 2. create user with home + shell
sudo passwd alice                  # 3. set the password (interactive)
sudo usermod -aG sudo alice        # 4. grant sudo privileges
```

## Notes & troubleshooting

- **`useradd` vs `adduser`**: the script uses `useradd` (present on every
  distribution). Home directory and shell are handled by the `-m` and `-s`
  flags.
- **Group not found**: if neither a `sudo` nor a `wheel` group exists (rare),
  the script warns you instead of failing — configure sudoers manually with
  `visudo`.
- **Sudo not taking effect for the new user**: group membership is applied on
  the next login. Log out and back in (or `newgrp sudo`) and try again.
- **Password rules**: the script only checks for non-empty input and matching
  confirmation; the system's own password policy may additionally apply.
