# CM3588 WayDroid Android TV host

A Debian host runtime for Android TV on the FriendlyElec CM3588 Plus (RK3588).
This repository installs and starts **already compiled** WayDroid `system.img` and `vendor.img` files.

## Related repositories

- **Build Android images:** [cm3588-waydroid-atv](https://github.com/fviolence/cm3588-waydroid-atv).
- **Build the TV remote bridge:** [cm3588-cec-remote](https://github.com/fviolence/cm3588-cec-remote).

## Included files

| Path | Purpose |
|---|---|
| `weston/cm3588-weston-4k60.ini` | Configurable HDMI output (defaults to HDMI-A-1), 3840×2160 at 60 Hz |
| `systemd/user/cm3588-weston.service` | Weston DRM/GL kiosk compositor, journald, forced composition |
| `systemd/user/cm3588-weston.service.d/10-boot-gate.conf` | Deferred startup until DRM is ready |
| `systemd/user/cm3588-waydroid-tv.service` | Android session and fullscreen launcher |
| `bin/cm3588-weston-boot-gate` | Startup gate |
| `bin/cm3588-waydroid-tv` | WayDroid session supervisor and fullscreen launcher |
| `scripts/install-host-files.sh` | Guarded file installation; does not init WayDroid or start services |
| `scripts/patch-waydroid-iplatform.sh` | Optional, guarded Android Binder service-descriptor fix |

## Host runtime architecture

The Linux host provides the DRM/KMS display pipeline, Mali GBM/EGL rendering, Binder devices, Linux namespaces and cgroups, WayDroid LXC container, PipeWire audio, and the `waydroid0` network interface.

Weston 14 uses the DRM backend on `card0`, the Mali-G610 GL renderer, `kiosk-shell`, `wayland-kiosk`, and 3840×2160@60. **The output connector name is host-dependent:** the supplied `.ini` defaults to `HDMI-A-1`.

> wa: `WESTON_FORCE_RENDERER=1` prevents invalid full-width requests for the Rockchip VOP2 `Cluster0-win1` two-window plane. Weston outputs to the user journal.

`waydroid-container.service` is a system service. Weston and the fullscreen Android TV launcher are user services. The TV launcher waits for the compositor socket and Android readiness, then requests the WayDroid fullscreen UI.

HDMI-CEC handling belongs to the separate [cm3588-cec-remote](https://github.com/fviolence/cm3588-cec-remote) project. The bridge receives commands from `/dev/cec0` and creates a Linux uinput keyboard consumed by Weston.

## Installation

### Preparations

Obtain compatible ARM64 `system.img` and `vendor.img` from the [CM3588 Android TV build guide](https://github.com/fviolence/cm3588-waydroid-atv).

The tested stack uses Debian 13, Weston 14, WayDroid 1.6.3, the Rockchip 6.1 host kernel, host Mali G610 GL/GBM, Android 16 and Android vendor g29p0.

### 1. Check the host kernel and devices

The kernel must supply Binder/BinderFS, namespaces, cgroups, loop-backed mounts, DRM/KMS, Mali GPU and input devices. Consult the [CM3588 kernel configuration guide](https://github.com/fviolence/cm3588-kernel-security-backports#51-optional-enable-waydroid-kernel-support).

```bash
uname -r
ls -l /dev/dri/card0 /dev/mali0 /dev/cec0 /dev/uinput
ls -l /dev/binder /dev/hwbinder /dev/vndbinder /dev/binderfs/ 2>/dev/null || true
```

For the tested RK3588 host kernel, relevant options include:

```text
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDERFS=y
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"
CONFIG_MEMFD_CREATE=y
```

```bash
KREL="$(uname -r)"
if [ -r /proc/config.gz ]; then
    zcat /proc/config.gz
elif [ -r "/boot/config-$KREL" ]; then
    cat "/boot/config-$KREL"
else
    echo "Kernel config unavailable; inspect the installed kernel sources" >&2
fi | grep -E 'ANDROID_BINDER|MEMFD_CREATE|CGROUPS|NAMESPACES|VETH|BRIDGE|BLK_DEV_LOOP'
```

### 2. Install WayDroid, Weston, audio and diagnostic tools

For Debian 13, install WayDroid from the distribution's `trixie-backports` repository or use the [official WayDroid Debian instructions](https://docs.waydro.id/usage/install-on-desktops).

```bash
sudo apt update
sudo apt install git waydroid weston seatd pipewire pipewire-pulse wireplumber \
  libinput-tools v4l-utils alsa-utils rsync e2fsprogs
waydroid --version
weston --version
```

Run the dedicated compositor as a regular login user, with working user D-Bus, `XDG_RUNTIME_DIR`, libseat access and permissions to DRM/GPU/input devices. Check the actual device groups, then add **only** the groups necessary for this host (often `video`, `render`, and `input`):

```bash
id
ls -l /dev/dri/* /dev/mali0 /dev/input/*
```

Group changes take effect only after logging in again. Do not use broad `MODE=0666` rules for all GPU, input and audio devices. If seatd is used, check its local permissions and start it according to its Debian package configuration.

### 3. Prepare the compiled images

```bash
sudo install -d -m 0755 /etc/waydroid-extra/images
sudo install -o root -g root -m 0644 system.img /etc/waydroid-extra/images/system.img
sudo install -o root -g root -m 0644 vendor.img /etc/waydroid-extra/images/vendor.img
sudo sha256sum /etc/waydroid-extra/images/{system,vendor}.img
```

### 4. Initialize WayDroid (fresh installation only)

Check if `/var/lib/waydroid/waydroid.cfg` already exists:

```bash
if sudo test -e /var/lib/waydroid/waydroid.cfg; then
    echo 'WayDroid is already initialized. STOP: do not reinitialize.'
else
    sudo waydroid init -f -i /etc/waydroid-extra/images
fi
```

Inspect the result:

```bash
sudo grep -E '^(images_path|vendor_type)' /var/lib/waydroid/waydroid.cfg
sudo ls -lh /etc/waydroid-extra/images/
```

Use `images_path = /etc/waydroid-extra/images` and a mainline vendor for these images.

### 5. Configure the connected HDMI output

Identify the DRM connector that is actually connected to the TV on the CM3588 host:

```bash
grep -H . /sys/class/drm/card*-HDMI-A-*/status
```

For example, after moving the cable to the second HDMI output:

```text
/sys/class/drm/card0-HDMI-A-1/status:disconnected
/sys/class/drm/card0-HDMI-A-2/status:connected
```

The supplied Weston template defaults to **`HDMI-A-1`**; that is only a default, not a universal choice. Configure `name=` for the connected output, `mode=3840x2160@60` requests 4K60.

```bash
git clone https://github.com/fviolence/cm3588-waydroid-host.git
cd cm3588-waydroid-host
vim weston/cm3588-weston-4k60.ini
```

For `HDMI-A-2` the contents should be:

```ini
[output]
name=HDMI-A-2
mode=3840x2160@60
```

Check the saved template:

```bash
cat weston/cm3588-weston-4k60.ini
```

**If the host files are already installed**, edit the *installed* configuration instead. Changing the repository template does not update `/etc/xdg/weston/`, because the installer deliberately refuses to overwrite existing files. Stop the WayDroid user session and Weston, then back up and edit the installed file:

Restart in compositor-then-session order:

```bash
systemctl --user start cm3588-weston.service
systemctl --user start cm3588-waydroid-tv.service
```

Confirm the actual mode, not merely the contents of the `.ini`:

```bash
grep -H . /sys/class/drm/card*-HDMI-A-*/{status,enabled}
sudo journalctl -k -b --no-pager | grep 'Update mode to' | tail -n 5
```

### 6. Install Weston and Android TV startup services

From the cloned `cm3588-waydroid-host` directory (Step 5), install the files:

```bash
./scripts/install-host-files.sh
```

The installation script refuses to overwrite existing files. It installs:

- `/etc/xdg/weston/cm3588-weston-4k60.ini`
- `~/.local/bin/cm3588-weston-boot-gate` and `~/.local/bin/cm3588-waydroid-tv`
- `~/.config/systemd/user/cm3588-weston.service` and `cm3588-waydroid-tv.service`
- Weston boot gate drop-in

> The Weston service deliberately enables `WESTON_FORCE_RENDERER=1` to avoid Rockchip VOP2 invalid-plane retries.

Check the systemd units:

```bash
systemctl --user cat cm3588-weston.service cm3588-waydroid-tv.service
systemctl --user daemon-reload
```

### 7. Verify WayDroid host service compatibility

The Android 16 guest's WayDroid platform Binder descriptor is `id.waydro.waydroid.IPlatform`. Some older Debian host wrappers use `lineageos.waydroid.IPlatform` instead, making `waydroid show-full-ui` and `waydroid app list` fail even when the container is healthy.

```bash
grep -n '^INTERFACE =' /usr/lib/waydroid/tools/interfaces/IPlatform.py
```

**Only if the older descriptor is present** for the matching WayDroid version:

```bash
./scripts/patch-waydroid-iplatform.sh
```

This guarded script backs up the installed Python file.

### 8. Enable unattended Android TV startup

The WayDroid container is a **system service**, while Weston and the TV launcher are **user services**. To start the user manager at boot without an SSH/login session, enable user lingering:

```bash
sudo systemctl enable --now waydroid-container.service
sudo loginctl enable-linger "$(id -un)"
systemctl --user enable cm3588-weston.service cm3588-waydroid-tv.service
```

Start the display stack as the normal host user:

```bash
systemctl --user start cm3588-weston.service
systemctl --user start cm3588-waydroid-tv.service
```

The launcher waits for Weston's `wayland-kiosk` socket, starts the WayDroid session, waits until Android is ready, then invokes `waydroid show-full-ui`. The WayDroid container alone cannot display the launcher.

Check startup:

```bash
systemctl --user is-active cm3588-weston.service cm3588-waydroid-tv.service
systemctl is-active waydroid-container.service
waydroid status
sudo waydroid shell getprop sys.boot_completed
journalctl --user -u cm3588-weston.service -b --no-pager -n 50
```

The successful image pair reports `sys.boot_completed=1`, a running SurfaceFlinger and Bifrost allocator, and an Android TV display at 3840x2160 60 Hz.

### 9. Enable HDMI-CEC remote input (separate project)

The HDMI-CEC-to-uinput daemon is maintained independently as [cm3588-cec-remote](https://github.com/fviolence/cm3588-cec-remote). Build and install it using that project's README, and check that `/dev/cec0` and `/dev/uinput` exist. On hosts where uinput is a loadable kernel module, the bridge's service requires it to be loaded before startup; see the CEC repository for persistent module setup. The bridge feeds a virtual keyboard to Weston, which forwards events to Android TV. Remote OK/Select requires Linux `KEY_SELECT` (353) and the Android HWC key-range patch; `KEY_ENTER` dismisses the on-screen keyboard instead of selecting a letter.

### 10. Audio and networking

PipeWire, PipeWire-Pulse and WirePlumber run in the host user session. The guest reaches the host Pulse-compatible socket through WayDroid integration.

```bash
systemctl --user is-active pipewire.service pipewire-pulse.service wireplumber.service
wpctl status
aplay -l
```

The WayDroid virtual bridge must allow DHCP, DNS and outbound traffic.

```bash
ip addr show waydroid0
waydroid status
```

### 11. Replace Android images safely

Replacing images does not require reinstalling WayDroid or clearing Android application data.

```bash
systemctl --user stop cm3588-waydroid-tv.service
waydroid session stop
sudo systemctl stop waydroid-container.service
sudo lxc-info -P /var/lib/waydroid/lxc -n waydroid
findmnt -R /var/lib/waydroid/rootfs
```

## Troubleshooting

### Android starts but the TV is black

```bash
grep -H . /sys/class/drm/card*-HDMI-A-*/status
cat /etc/xdg/weston/cm3588-weston-4k60.ini
waydroid status
sudo waydroid shell getprop sys.boot_completed
```

```bash
systemctl --user --no-pager status cm3588-weston.service cm3588-waydroid-tv.service
journalctl --user -u cm3588-weston.service -b --no-pager -n 80
```

### HDMI output appears at 4K30 or flickers

Weston's selected mode must be `3840x2160@60`. Keep forced composition enabled. Review Weston and kernel DRM errors, especially VOP2 `Cluster0-win1` width rejections. The 45-second boot gate protects against late DRM initialization.

### Cobalt displays missing thumbnail tiles

Confirm that the Android system image includes the YouTube low-end-mode override. The confirmed workaround is in the **Android framework**; changing host Weston cannot substitute for it. Consult the build repository's patch notes.

## References

- [Build the Android images](https://github.com/fviolence/cm3588-waydroid-atv)
- [WayDroid's official Debian installation guide](https://docs.waydro.id/usage/install-on-desktops)
- [WayDroid custom images](https://docs.waydro.id/faq/using-custom-waydroid-images)
- [Weston DRM backend](https://manpages.debian.org/trixie/weston/weston-drm.7.en.html)
- [CEC bridge](https://github.com/fviolence/cm3588-cec-remote)
