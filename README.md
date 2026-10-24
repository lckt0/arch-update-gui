# arch-update-gui

**English** · [Türkçe](README.tr.md)

A small PySide6 + QML popup for [cachy-update](https://github.com/CachyOS/cachy-update)
(the CachyOS fork of [arch-update](https://github.com/Antiz96/arch-update)) on
KDE Plasma. Clicking the arch-update tray icon opens it in the top-right corner,
like a Plasma tray popup, instead of a terminal.

![Pending updates](screenshots/packages.png)

> **A note before you start:** arch-update-gui was originally built for my own setup and daily use, and later shared in case it helps someone else. It reflects my own hardware, tools and preferences, so it may not fit every system or workflow. Issues and suggestions are welcome, but please keep that in mind.
>
> Some choices are hard-coded for that reason: it expects `cachy-update`, uses `yay` for AUR
> updates and `konsole` as the terminal, and needs the passwordless `sudo` rule described below.

> **Note:** the interface text is currently Turkish only.

## What it does

- Lists pending updates from the repositories (`checkupdates`), the AUR
  (`yay -Qua`) and Flatpak, with the changed part of each version highlighted.
- Shows the latest Arch Linux news; entries can be expanded in place.
- Starts the upgrade with one button. It only asks for confirmation when
  manual intervention may be needed:
  - there is an unread Arch news item,
  - a `pacman -Sup` dry run (against a separate sync database) fails or would
    ask a question,
  - a locally built package that replaces a repository package (it both
    provides and conflicts with it) is now older than the repository version.
- Runs the upgrade in a separate `systemd-run --user` unit, so closing the
  popup does not interrupt pacman. Reopening the popup reattaches to the
  running upgrade and shows progress and the log.
- After the upgrade it reports whether a reboot is needed (kernel updated),
  pending `.pacnew` files, services to restart (`checkservices`) and orphan
  packages, and cleans the package cache with `paccache` using the
  `KeepOldPackages` / `KeepUninstalledPackages` values from
  `arch-update.conf`.
- Keeps arch-update's state files (`~/.local/state/arch-update`) and tray
  icon in sync.

| Manual intervention | News | Updating | Done |
|---|---|---|---|
| ![Confirm](screenshots/confirm.png) | ![News](screenshots/news.png) | ![Updating](screenshots/updating.png) | ![Done](screenshots/done.png) |

## Requirements

- Arch Linux with KDE Plasma 6 on Wayland (the popup is a layer-shell surface)
- `cachy-update` (provides `arch-update`, its tray and the `cachy-update-*`
  icons used here)
- Python 3, `pyside6`, `kirigami`, `qqc2-desktop-style`, `layer-shell-qt`
- `pacman-contrib` (`checkupdates`, `paccache`, `pacdiff`)
- `archlinux-contrib` (`checkservices`)
- `util-linux` (`script`, `flock`), `systemd` (`systemd-run`), `libnotify`
  (`notify-send`)
- Optional: `yay` for AUR updates, `flatpak`, `konsole` for the
  "update in terminal" button, `qt6-tools` (`qdbus6`) for the reboot prompt

Upstream `arch-update` (without the CachyOS changes) has not been tested; it
uses different icon names.

### Passwordless sudo

The upgrade runs without a terminal, so `runner.sh` calls `sudo -n` (it never
prompts). The following commands must be allowed without a password, or the
upgrade fails immediately:

```
pacman -Syu --noconfirm --color never
paccache -r ...
checkservices -F -P -R ...
```

Example `/etc/sudoers.d/arch-update-gui` (edit with `visudo`, replace `youruser`):

```
youruser ALL=(root) NOPASSWD: /usr/bin/pacman -Syu --noconfirm --color never, /usr/bin/paccache, /usr/bin/checkservices
```

Be aware that this lets your user run a full system upgrade and these tools
as root without a password.

AUR packages are built by `yay -Sua --noconfirm` with diff/clean/edit prompts
answered "None".

## Installation

### Arch Linux (PKGBUILD)

```sh
git clone https://github.com/lckt0/arch-update-gui.git
cd arch-update-gui
makepkg -si
```

### Manual

```sh
git clone https://github.com/lckt0/arch-update-gui.git ~/.local/share/arch-update-gui
mkdir -p ~/.local/bin
ln -s ~/.local/share/arch-update-gui/arch_update_gui.py ~/.local/bin/arch-update-gui
```

### Hooking it into the tray icon

The arch-update tray launches `arch-update.desktop`, and looks in
`~/.local/share/applications` first. Put the provided desktop file there to
make a click on the tray icon open the popup:

```sh
mkdir -p ~/.local/share/applications
# package install:
cp /usr/share/arch-update-gui/arch-update.desktop ~/.local/share/applications/
# manual install:
cp ~/.local/share/arch-update-gui/arch-update.desktop ~/.local/share/applications/
```

Then set up the passwordless `sudo` rule described under [Passwordless sudo](#passwordless-sudo).

## Usage

Click the tray icon, or run `arch-update-gui`. Clicking the icon again or
pressing Esc closes the popup. Only one popup runs at a time; launching it
again raises the existing one.

Demo mode uses fake data and a fake runner, and does not touch the system:

```sh
ARCH_UPDATE_GUI_DEMO=1 arch-update-gui
ARCH_UPDATE_GUI_DEMO=1 ARCH_UPDATE_GUI_DEMO_WARN=1 arch-update-gui   # with warnings
```

Files:

- `~/.local/state/arch-update-gui/run.log` – log of the last upgrade
- `~/.local/state/arch-update-gui/run.result` – result of the last upgrade
- `~/.local/state/arch-update-gui/acks.json` – acknowledged news and warnings

## Uninstallation

### Arch Linux (package)

```sh
sudo pacman -Rns arch-update-gui
```

### Manual

```sh
rm ~/.local/bin/arch-update-gui
rm -rf ~/.local/share/arch-update-gui
```

### Reverting system changes

Remove the desktop file override, so the tray icon opens arch-update in a
terminal again, and the `sudo` rule if you added it:

```sh
rm ~/.local/share/applications/arch-update.desktop
sudo rm /etc/sudoers.d/arch-update-gui
```

### User data (optional)

The upgrade log, last result and acknowledged news are kept in
`~/.local/state/arch-update-gui`:

```sh
rm -r ~/.local/state/arch-update-gui
```

Leave `~/.local/state/arch-update` alone; it belongs to arch-update itself.

## License

MIT, see [LICENSE](LICENSE).
