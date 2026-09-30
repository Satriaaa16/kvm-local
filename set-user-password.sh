#!/bin/bash
set -e

# ==========================================================
# INPUT PARAMETERS
# Usage:
#   1. Default (User: user-al, Pass: useral):
#      ./set-user-password.sh [ubuntu|debian]
#   2. Password Custom:
#      ./set-user-password.sh [ubuntu|debian] --password <password_custom>
# ==========================================================
DISTRO_CHOICE="${1:-ubuntu}"
FLAG="${2}"
CUSTOM_PASS="${3}"

NAMEKVM="vm-${DISTRO_CHOICE}"
VM_DISK_DIR="/home/satria16alan/Dokumen/kvm/vms"
VM_DISK="${VM_DISK_DIR}/${NAMEKVM}.qcow2"

# 1. LOGIKA KONDISIONAL BILA DISK BELUM ADA
if [ ! -f "$VM_DISK" ]; then
    echo "=========================================================="
    echo "⚠️  File disk '$VM_DISK' belum ditemukan!"
    echo "🔄 Memanggil 'requirement.sh' & 'create-kvm.sh' untuk $DISTRO_CHOICE..."
    echo "=========================================================="

    ./requirement.sh "$DISTRO_CHOICE"
    ./create-kvm.sh "$DISTRO_CHOICE"
fi

# 2. MATIKAN VM SEBENTAR AGAR DISK TIDAK TERKUNCI OLEH KVM
echo "🛑 Memastikan VM '$NAMEKVM' offline sebelum di-customize..."
virsh destroy "$NAMEKVM" 2>/dev/null || true

# 3. PENENTUAN PASSWORD (DEFAULT: useral)
if [ "$FLAG" == "--password" ] && [ -n "$CUSTOM_PASS" ]; then
    TARGET_PASS="$CUSTOM_PASS"
else
    TARGET_PASS="useral"
fi

echo "=========================================================="
echo "🔧 [CUSTOMIZE] Setting up credentials on Ubuntu 24.04..."
echo "   Target VM  : $NAMEKVM"
echo "   Target Disk: $VM_DISK"
echo "=========================================================="

# 4. INJECT CREDENTIALS & AUTOLOGIN FIX VIA VIRT-CUSTOMIZE
virt-customize -a "$VM_DISK" \
  --run-command 'useradd -m -s /bin/bash user-al || true' \
  --password "user-al:password:${TARGET_PASS}" \
  --root-password "password:${TARGET_PASS}" \
  --run-command 'usermod -aG sudo user-al || true' \
  --run-command 'echo "user-al ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user-al' \
  --run-command 'chmod 440 /etc/sudoers.d/user-al' \
  --run-command 'mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d' \
  --run-command 'echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty -o \"-p -- \\\\u\" --autologin user-al --keep-baud 115200,38400,9600 %I \$TERM" > /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf' \
  --run-command 'systemctl enable systemd-networkd systemd-resolved || true'

# 5. NYALAKAN KEMBALI VM
echo "🚀 Nyalakan kembali VM '$NAMEKVM'..."
virsh start "$NAMEKVM" 2>/dev/null || true

# 6. SUMMARY OUTPUT PIPELINE
echo ""
echo "=========================================================="
echo "✅ [SUCCESS] CREDENTIALS & AUTOLOGIN APPLIED!"
echo "=========================================================="
echo "  Target VM   : $NAMEKVM"
echo "  Target Disk : $VM_DISK"
echo "----------------------------------------------------------"
echo "  CONSOLE / TTY ACCESS :"
echo "    Autologin : AKTIFF (Otomatis masuk ke user-al di virsh console!)"
echo "----------------------------------------------------------"
echo "  MANUAL LOGIN / SSH :"
echo "    Username  : user-al"
echo "    Password  : $TARGET_PASS"
echo "    Sudo      : YES (NOPASSWD)"
echo "=========================================================="
