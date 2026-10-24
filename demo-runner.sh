#!/bin/bash
# Deneme modu (ARCH_UPDATE_GUI_DEMO=1) icin sahte yurutucu — sisteme dokunmaz,
# runner.sh'in cikti bicimini (pacman ilerleme satirlari, @@ isaretleri) taklit eder.
state="${XDG_STATE_HOME:-${HOME}/.local/state}/arch-update-gui"
exec > "${state}/run.log" 2>&1
rm -f "${state}/run.result"
d=${DEMO_DELAY:-0.15}

echo "@@STEP repo"
echo ":: Synchronizing package databases..."
sleep 0.5
echo ":: Starting full system upgrade..."
echo "resolving dependencies..."
echo "looking for conflicting packages..."
echo
echo "Packages (7) firefox-143.0.3-1  kwin-6.7.6-1  linux-firmware-20260928.ef01-1  mesa-1:26.2.4-1  plasma-workspace-6.7.6-1  python-3.14.1-1  systemd-261.3-1"
echo
echo ":: Retrieving packages..."
for i in 1 2 3 4 5 6 7; do
	printf ' Total (%d/7)   %3d MiB  12.4 MiB/s 00:0%d [####----] %d%%\r' "$i" $((i * 40)) $((7 - i)) $((i * 14))
	sleep "$d"
done
echo
for i in 1 2 3 4 5 6 7; do printf '(%d/7) checking keys in keyring    [####] 100%%\r' "$i"; sleep 0.05; done; echo
for i in 1 2 3 4 5 6 7; do printf '(%d/7) checking package integrity   [####] 100%%\r' "$i"; sleep 0.05; done; echo
echo ":: Processing package changes..."
pk=(firefox kwin linux-firmware mesa plasma-workspace python systemd)
for i in "${!pk[@]}"; do
	printf '(%d/7) upgrading %-30s [######] 100%%\n' $((i + 1)) "${pk[$i]}"
	sleep "$d"; sleep "$d"
done
echo ":: Running post-transaction hooks..."
for i in $(seq 1 12); do printf '(%2d/12) Running hook %d...\n' "$i" "$i"; sleep 0.08; done

echo "@@STEP aur"
echo ":: Searching AUR for updates..."
echo "==> Making package: visual-studio-code-bin 1.141.0-1"
sleep 1
echo "(1/1) upgrading visual-studio-code-bin"
sleep 0.4

echo "@@STEP flatpak"
echo " 1. [✓] com.spotify.Client stable u flathub 120 MB"
sleep 0.6

echo "@@STEP post"
echo ":: Önbellek temizleniyor..."
sleep 0.5
{
	echo "rc=${DEMO_RC:-0}"
	echo "msg=${DEMO_MSG:-}"
	echo "reboot=1"
	echo "orphans=python-old-lib"
	echo "pacnew=/etc/pacman.conf.pacnew"
	echo "services=bluetooth.service"
	echo "finished=$(date '+%F %T')"
} > "${state}/run.result"
echo "@@END ${DEMO_RC:-0}"
