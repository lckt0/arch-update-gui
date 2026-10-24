# Maintainer: lckt0 <lckt0@protonmail.com>
pkgname=arch-update-gui
pkgver=0.1.0
pkgrel=1
pkgdesc="Tray popup for cachy-update/arch-update: pending updates, Arch news and one-click upgrade (PySide6 + QML)"
arch=('any')
url="https://github.com/lckt0/arch-update-gui"
license=('MIT')
depends=('python' 'pyside6' 'kirigami' 'qqc2-desktop-style' 'layer-shell-qt'
         'cachy-update' 'pacman-contrib' 'archlinux-contrib' 'util-linux' 'systemd' 'libnotify' 'sudo')
optdepends=(
  'yay: AUR updates'
  'flatpak: Flatpak updates'
  'konsole: "Update in terminal" button'
  'qt6-tools: reboot prompt (qdbus6)'
)
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('SKIP')

package() {
  cd "$pkgname-$pkgver"
  install -Dm755 arch_update_gui.py "$pkgdir/usr/share/$pkgname/arch_update_gui.py"
  install -Dm644 Popup.qml "$pkgdir/usr/share/$pkgname/Popup.qml"
  install -Dm755 runner.sh "$pkgdir/usr/share/$pkgname/runner.sh"
  install -Dm755 demo-runner.sh "$pkgdir/usr/share/$pkgname/demo-runner.sh"
  install -d "$pkgdir/usr/bin"
  ln -s "/usr/share/$pkgname/arch_update_gui.py" "$pkgdir/usr/bin/arch-update-gui"
  install -Dm644 arch-update.desktop "$pkgdir/usr/share/$pkgname/arch-update.desktop"
  install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
