#!/bin/bash
# arch-update-gui'nin guncelleme yurutucusu.
# GUI bunu `systemd-run --user` ile ayri bir birimde baslatir; boylece acilir
# pencere kapansa / cokse de pacman islem ortasinda olmez. Tum cikti run.log'a
# yazilir, GUI bu dosyayi izler. "@@" ile baslayan satirlar GUI icin isarettir.
#
# Kullanim: runner.sh [--repo] [--aur] [--flatpak]

state="${XDG_STATE_HOME:-${HOME}/.local/state}"
au_state="${state}/arch-update"
gui_state="${state}/arch-update-gui"
log="${gui_state}/run.log"
result="${gui_state}/run.result"
conf="${XDG_CONFIG_HOME:-${HOME}/.config}/arch-update/arch-update.conf"

mkdir -p "${gui_state}" "${au_state}"
rm -f "${result}"
exec > "${log}" 2>&1

do_repo="" do_aur="" do_flatpak=""
for arg in "$@"; do
	case "${arg}" in
		--repo) do_repo=1 ;;
		--aur) do_aur=1 ;;
		--flatpak) do_flatpak=1 ;;
	esac
done

export LANG=C.UTF-8 LC_ALL=C.UTF-8

finish() {
	local rc="$1" msg="$2"
	{
		echo "rc=${rc}"
		echo "msg=${msg}"
		echo "reboot=${reboot_needed}"
		echo "orphans=${orphans}"
		echo "pacnew=${pacnew}"
		echo "services=${services}"
		echo "finished=$(date '+%F %T')"
	} > "${result}"
	echo "@@END ${rc}"

	if [ "${rc}" -eq 0 ]; then
		body="Tüm paketler güncel."
		[ -n "${reboot_needed}" ] && body="${body} Çekirdek güncellendi — yeniden başlatma gerekiyor."
		[ -n "${pacnew}" ] && body="${body} Bekleyen .pacnew dosyası var."
		notify-send -a "Arch Güncelleme" -i cachy-update-blue "Güncelleme tamamlandı" "${body}"
	else
		notify-send -u critical -a "Arch Güncelleme" -i dialog-error "Güncelleme başarısız" "${msg}"
	fi
	exit "${rc}"
}

# Ayni kilit dosyasi arch-update tarafindan da kullaniliyor — es zamanli calismayi onler
exec {fd_lock}> "/tmp/arch-update.lock"
if ! flock -n "${fd_lock}"; then
	echo "Başka bir arch-update örneği zaten çalışıyor."
	finish 17 "Başka bir güncelleme zaten çalışıyor"
fi

# pacman/yay ilerleme cubuklarini satir satir verebilsin diye sahte terminal (pty).
in_pty() {
	script -qfec "stty cols 110 rows 40 2>/dev/null; $*" /dev/null
}

if [ -n "${do_repo}" ]; then
	echo "@@STEP repo"
	if ! in_pty "sudo -n pacman -Syu --noconfirm --color never"; then
		echo
		echo "@@ERROR repo"
		finish 5 "pacman -Syu başarısız oldu — ayrıntılar günlükte"
	fi
	: > "${au_state}/last_updates_check_packages"
	packages_updated=1
fi

if [ -n "${do_aur}" ]; then
	echo "@@STEP aur"
	if ! in_pty "yay -Sua --noconfirm --color never --answerclean None --answerdiff None --answeredit None"; then
		echo
		echo "@@ERROR aur"
		aur_failed=1
	else
		: > "${au_state}/last_updates_check_aur"
		packages_updated=1
	fi
fi

if [ -n "${do_flatpak}" ]; then
	echo "@@STEP flatpak"
	if ! flatpak update --assumeyes --noninteractive; then
		echo
		echo "@@ERROR flatpak"
		flatpak_failed=1
	else
		: > "${au_state}/last_updates_check_flatpak"
	fi
fi

cat "${au_state}"/last_updates_check_{packages,aur,flatpak} > "${au_state}/last_updates_check" 2> /dev/null

echo "@@STEP post"
date +%Y-%m-%d > "${au_state}/last_update_run"

# Tepsi simgesini guncel duruma cek (stil mevcut dosyadan korunur)
style=$(grep -E '^[[:space:]]*TrayIconStyle[[:space:]]*=' "${conf}" 2> /dev/null | awk -F '=' '{print $2}' | tr -d '[:space:]')
[ -z "${style}" ] && style="blue"
if [ ! -s "${au_state}/last_updates_check" ]; then
	echo "cachy-update-${style}" > "${au_state}/tray_icon"
fi

# arch-update varsayilanlari: eski onbellegi temizle (evet), yetimleri kaldirma (hayir),
# servisleri yeniden baslatma (hayir) — yalnizca listelenir.
keep_old=$(grep -E '^[[:space:]]*KeepOldPackages[[:space:]]*=' "${conf}" 2> /dev/null | awk -F '=' '{print $2}' | tr -d '[:space:]')
keep_uninst=$(grep -E '^[[:space:]]*KeepUninstalledPackages[[:space:]]*=' "${conf}" 2> /dev/null | awk -F '=' '{print $2}' | tr -d '[:space:]')
echo ":: Önbellek temizleniyor..."
sudo -n paccache -r -k"${keep_old:-3}"
sudo -n paccache -r -u -k"${keep_uninst:-0}"

orphans=$(pacman -Qtdq 2> /dev/null | tr '\n' ' ' | sed 's/ $//')
pacnew=$(pacdiff -o 2> /dev/null | tr '\n' ' ' | sed 's/ $//')
if [ ! -f "/usr/lib/modules/$(uname -r)/vmlinuz" ]; then
	reboot_needed=1
fi
if [ -n "${packages_updated}" ]; then
	services=$(sudo -n checkservices -F -P -R -i gdm.service -i plasmalogin.service -i sddm.service -i lightdm.service -i greetd.service 2> /dev/null | grep ".service" | cut -f2 -d "'" | tr '\n' ' ' | sed 's/ $//')
fi

if [ -n "${aur_failed}" ]; then
	finish 6 "AUR güncellemesi başarısız oldu — ayrıntılar günlükte"
elif [ -n "${flatpak_failed}" ]; then
	finish 7 "Flatpak güncellemesi başarısız oldu — ayrıntılar günlükte"
fi
finish 0 ""
