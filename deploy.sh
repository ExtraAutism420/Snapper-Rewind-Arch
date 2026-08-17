#!/bin/bash
# deploy.sh - Install Snapper-Rewind on a target Arch system
# Usage: sudo ./deploy.sh

set -e

echo "Snapper-Rewind – Copyright (C) 2026 Sabastian Harbaugh – GPLv3"

echo "=== Installing Snapper Rewind ==="

# 1. Install required packages (optional – skip if already present)
echo "Installing required packages..."
pacman -S --needed --noconfirm snapper btrfs-progs sbctl snap-pac ukify

# 2. Copy scripts to /usr/local/bin/
echo "Installing scripts..."
cp -v add-kernel-tries auto-rollback-on-snapshot-boot snapper-uki /usr/local/bin/
chmod +x /usr/local/bin/{add-kernel-tries,auto-rollback-on-snapshot-boot,snapper-uki}

# 3. Copy systemd units
echo "Installing systemd units..."
cp -v rollback-on-snapshot.{service,timer} /etc/systemd/system/
cp -v restore-kernel-counter.{service,timer} /etc/systemd/system/ 2>/dev/null || true

# 4. Ensure systemd-bless-boot is unmasked and enabled
echo "Ensuring systemd-bless-boot is enabled..."
systemctl unmask systemd-bless-boot.service 2>/dev/null || true
systemctl enable systemd-bless-boot.service 2>/dev/null || true
mkdir -p /etc/systemd/system/systemd-bless-boot.service.d
cp -v systemd-bless-boot.service.d/override.conf /etc/systemd/system/systemd-bless-boot.service.d/ 2>/dev/null || true

# 5. Copy pacman hooks
echo "Installing pacman hooks..."
mkdir -p /etc/pacman.d/hooks
cp -v rename-kernel.hook zzz-snapper-uki.hook /etc/pacman.d/hooks/

# 6. Set kernel tries
echo "Setting boot tries..."
mkdir -p /etc/kernel
cp -v tries /etc/kernel/tries

# 7. Copy loader.conf
info "Copying loader.conf..."
mkdir -p /boot/loader
if [[ ! -f /boot/loader/loader.conf ]]; then
    cp -v loader.conf /boot/loader/loader.conf
else
    echo "loader.conf already exists – please merge manually if needed."
fi

# 8. Reset default to @ hook
cp -v reset-default-to-at /usr/local/bin/
chmod +x /usr/local/bin/reset-default-to-at
cp -v zzzz-default-reset.hook /etc/pacman.d/hooks/

# 9. Install snapper config (template – adjust on target)
echo "Copying snapper config template..."
if [ ! -f /etc/snapper/configs/root ]; then
    mkdir -p /etc/snapper/configs
    cp -v root.template /etc/snapper/configs/root
else
    echo "Snapper config already exists – please merge manually if needed."
fi

# 10. Validate and fix Snapper config if needed
echo "Validating Snapper config..."
if ! sudo snapper -c root list &>/dev/null; then
    echo "Snapper config 'root' is invalid. Recreating..."
    sudo btrfs subvolume delete /.snapshots 2>/dev/null || true
    sudo snapper -c root create-config /
    sudo sed -i 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="3"/' /etc/snapper/configs/root
    sudo sed -i 's/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="3"/' /etc/snapper/configs/root
fi
sudo systemctl restart snapperd

# 11. Enable timers
echo "Enabling timers..."
systemctl enable --now rollback-on-snapshot.timer
systemctl enable --now restore-kernel-counter.timer 2>/dev/null || true

# 12. Optionally rename default kernel
echo "Renaming default kernel to include boot counter..."
/usr/local/bin/add-kernel-tries

echo "=== Installation complete! ==="
echo "Please review /etc/snapper/configs/root and adjust settings."
echo "Then create your first snapshot:"
echo "  sudo snapper -c root create --description \"Initial\""
echo "  sudo /usr/local/bin/snapper-uki"
echo "Reboot to test the fallback chain."
