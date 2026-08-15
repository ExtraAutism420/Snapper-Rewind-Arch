# 🌿 Snapper-Rewind

A self‑healing Btrfs snapshot rollback system for Arch Linux with systemd‑boot and Secure Boot.

**Author**: Sabastian Harbaugh
**License**: GNU General Public License v3.0 – see [LICENSE](LICENSE)
**Repository**: (add your repo URL here)

---

A portable, self‑healing Arch Linux recovery system using:

- **systemd‑boot** (with boot counting)
- **Btrfs snapshots** (via snapper)
- **UKIs** (Unified Kernel Images)
- **SecureBoot** (via sbctl — optional)
- **Pacman hooks** + **systemd timers** for automation

> Fits in ~64 KB. Deploys in seconds.

---

## 📦 What’s Inside

### Scripts (`/usr/local/bin/`)

| Script | Purpose |
|--------|---------|
| `snapper-uki` | Generates UKIs for all snapshots, signs them, makes them writable, and cleans up old UKIs/snapshots. |
| `auto-rollback-on-snapshot-boot` | Detects a snapshot boot via kernel parameter `snapshot=`, sets that snapshot as the default subvolume, and reboots. |
| `add-kernel-tries` | Renames the default kernel UKI to include a boot counter (e.g., `+3-2`) and signs it. |

### Systemd Units

| Unit | Purpose |
|------|---------|
| `rollback-on-snapshot.service` | Runs the rollback script. |
| `rollback-on-snapshot.timer` | Triggers the rollback service **25 seconds** after boot. |
| `restore-kernel-counter.service` | Restores the boot counter after `systemd-bless-boot` clears it. |
| `restore-kernel-counter.timer` | Runs the restore service **10 seconds** after boot (redundant safety). |

### Pacman Hooks (`/etc/pacman.d/hooks/`)

| Hook | Purpose |
|------|---------|
| `rename-kernel.hook` | Runs `add-kernel-tries` after every kernel update. |
| `zzz-snapper-uki.hook` | Runs `snapper-uki` after **every** pacman transaction (post‑snapshot). |

### Config Files

| File | Purpose |
|------|---------|
| `tries` | Contains the number of boot attempts (default: `3`). |
| `root.template` | Template for `/etc/snapper/configs/root` – adjust per system. |
| `systemd-bless-boot.service` | Symlink to `/dev/null` – masks the service to prevent counter clearing (we restore via timer). |
| `systemd-bless-boot.service.d/override.conf` | Adds `ConditionPathIsReadWrite=/` to skip on read‑only snapshots. |

---

## 🔧 Required Packages

The deploy script will install:
```bash
snapper btrfs-progs sbctl snap-pac ukify

If you're not using Secure Boot, you can skip sbctl – comment it out in deploy.sh.

🚀 Installation
1. Copy the folder to the target system
```bash
cp -r /Path/To/Snapper-Rewind /target-system/
cd /target-system/Snapper-Rewind

2. Run the deploy script
```bash
sudo ./deploy.sh

3. What the deploy script does
Installs required packages.

Copies scripts to /usr/local/bin/ and makes them executable.

Copies systemd units to /etc/systemd/system/.

Masks systemd-bless-boot.service.

Copies pacman hooks to /etc/pacman.d/hooks/.

Copies tries to /etc/kernel/tries.

Copies root.template to /etc/snapper/configs/root (if not already present).

Enables and starts timers.

Renames the default kernel to include the boot counter.

4. Post‑installation steps
Review and adjust snapper config:
```bash
sudo nano /etc/snapper/configs/root
Set:

text
SUBVOLUME="/"
SNAPSHOT_DIR="/.snapshots"
NUMBER_LIMIT="3"
NUMBER_LIMIT_IMPORTANT="3"

Create your first snapshot and generate its UKI:
```bash
sudo snapper -c root create --description "Initial"
sudo /usr/local/bin/snapper-uki

🧠 How It Works
Boot Counting & Fallback
Default kernel is arch-linux-zen+3-2.efi (3 total tries, 2 remaining).

Each boot decrements remaining → +2-3, +1-4, +0-5.

After 3 failures, systemd-boot skips it and tries the latest snapshot.

Snapshot boots → rollback timer (25s) runs → sets snapshot as default → reboots.

Kernel Counter Restoration
On a successful boot, systemd-bless-boot clears the counter (arch-linux-zen.efi).

restore-kernel-counter.timer (10s) runs add-kernel-tries, renaming it back to +3-2 and signing it.

The default kernel always has fresh tries.

Snapshot UKI Generation
Runs after every pacman transaction.

Generates UKI for each snapshot, signs it, makes it writable, adds counter.

Keeps only the latest 3 snapshots and UKIs.

🛠️ Customization
Change number of boot attempts
```bash
echo 5 | sudo tee /etc/kernel/tries
sudo /usr/local/bin/add-kernel-tries
Change how many snapshots/UKIs to keep
Snapshots: Edit /etc/snapper/configs/root → NUMBER_LIMIT.

UKIs: Edit /usr/local/bin/snapper-uki → MAX_UKIS.

Ensure loader.conf inside /boot/loader/ has '*' at the end of your UKI right before .efi,
for example 'default arch-linux-zen*.efi'. This is to ensure systemd-boot always detects the
correct entry with the boot counter.

Adjust timer delays
```bash
sudo nano /etc/systemd/system/rollback-on-snapshot.timer   # OnBootSec=25s
sudo nano /etc/systemd/system/restore-kernel-counter.timer # OnBootSec=10s
sudo systemctl daemon-reload
sudo systemctl restart rollback-on-snapshot.timer
sudo systemctl restart restore-kernel-counter.timer
Disable Secure Boot signing (if not using sbctl)
Remove sbctl from package list in deploy.sh.

Comment out sbctl blocks in snapper-uki and add-kernel-tries.

Disable a timer (temporarily)
```bash
sudo systemctl disable --now rollback-on-snapshot.timer

Re‑enable:
```bash
sudo systemctl enable --now rollback-on-snapshot.timer
❓ Troubleshooting

Check timer status
```bash
sudo systemctl status rollback-on-snapshot.timer
sudo systemctl status restore-kernel-counter.timer

View logs
```bash
sudo journalctl -u rollback-on-snapshot.service -b
sudo journalctl -u restore-kernel-counter.service -b

Manual rollback (if timer doesn't fire)
```bash
sudo /usr/local/bin/auto-rollback-on-snapshot-boot

Verify Secure Boot signing
```bash
sudo sbctl verify

🧪 Testing the Fallback Chain
Temporarily rename the default kernel:
```bash
sudo mv /boot/EFI/Linux/arch-linux-zen+3-2.efi /boot/EFI/Linux/arch-linux-zen+3-2.efi.bak
Reboot. The system will try the default, fail 3 times, and fall back to the latest snapshot.

After 25 seconds, the rollback timer will promote the snapshot and reboot.

Restore the default kernel after testing:
```bash
sudo mv /boot/EFI/Linux/arch-linux-zen+3-2.efi.bak /boot/EFI/Linux/arch-linux-zen+3-2.efi
sudo btrfs subvolume set-default 256 /   # replace 256 with your @ subvolume ID

📝 Notes
Assumes root subvolume is @ and mounted at /. Adjust SUBVOLUME in snapper config if not.

snapshot= kernel parameter is automatically added by snapper-uki.

Designed for Arch Linux; dependencies may vary on derivatives.

🏁 Conclusion
You now have a fully automated, self‑healing Arch system – from snapshot creation to automatic rollback – all in ~64 KB.

