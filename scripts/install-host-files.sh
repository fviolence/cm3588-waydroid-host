#!/usr/bin/env bash
# Install new host assets only: never overwrite a working installation.
set -euo pipefail
if (( EUID == 0 )); then
    echo 'Run as the intended user, not as root.' >&2
    exit 1
fi
source_dir="$(cd "$(dirname "$0")/.." && pwd)"
unitdir="$HOME/.config/systemd/user"
launcher="$source_dir/bin/cm3588-waydroid-tv"

[[ -f "$launcher" && -x "$launcher" ]] || {
    echo 'Missing executable bin/cm3588-waydroid-tv' >&2
    exit 1
}

for dest in \
    /etc/xdg/weston/cm3588-weston-4k60.ini \
    "$unitdir/cm3588-weston.service" \
    "$unitdir/cm3588-waydroid-tv.service" \
    "$unitdir/cm3588-weston.service.d/10-boot-gate.conf" \
    "$HOME/.local/bin/cm3588-weston-boot-gate" \
    "$HOME/.local/bin/cm3588-waydroid-tv"; do
    if [[ -e "$dest" || -L "$dest" ]]; then
        echo "Refusing to overwrite: $dest" >&2
        exit 1
    fi
done

sudo install -d -m 0755 /etc/xdg/weston
sudo install -m 0644 "$source_dir/weston/cm3588-weston-4k60.ini" \
    /etc/xdg/weston/cm3588-weston-4k60.ini
install -d -m 0755 "$unitdir/cm3588-weston.service.d" "$HOME/.local/bin"
install -m 0644 "$source_dir/systemd/user/cm3588-weston.service" \
    "$unitdir/cm3588-weston.service"
install -m 0644 "$source_dir/systemd/user/cm3588-waydroid-tv.service" \
    "$unitdir/cm3588-waydroid-tv.service"
install -m 0644 \
    "$source_dir/systemd/user/cm3588-weston.service.d/10-boot-gate.conf" \
    "$unitdir/cm3588-weston.service.d/10-boot-gate.conf"
install -m 0755 "$source_dir/bin/cm3588-weston-boot-gate" \
    "$HOME/.local/bin/cm3588-weston-boot-gate"
install -m 0755 "$launcher" "$HOME/.local/bin/cm3588-waydroid-tv"
systemctl --user daemon-reload
echo 'Host files installed; services were not enabled or started.'
