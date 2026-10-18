#!/usr/bin/env bash
set -uo pipefail
printf '== Platform ==\n'; uname -a
printf '\n== Binders ==\n'; ls -l /dev/binder /dev/hwbinder /dev/vndbinder /dev/binderfs/ 2>&1 || :
printf '\n== DRM/GPU/CEC/uinput ==\n'; ls -l /dev/dri/card0 /dev/dri/renderD128 /dev/mali0 /dev/cec0 /dev/uinput 2>&1 || :
printf '\n== Software ==\n'; command -v waydroid weston cec-ctl || :
printf '\n== Group membership ==\n'; id
printf '\n== WayDroid image config ==\n'; sudo grep -E '^(images_path|vendor_type)' /var/lib/waydroid/waydroid.cfg 2>/dev/null || :
printf '\n== Service enablement ==\n'
systemctl is-enabled waydroid-container.service 2>&1 || :
systemctl --user is-enabled cm3588-weston.service cm3588-waydroid-tv.service 2>&1 || :
printf '\n== User lingering ==\n'; loginctl show-user "$(id -un)" -p Linger || :
