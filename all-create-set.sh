#!/bin/bash
set -e

# ==========================================================
# INPUT PARAMETER FLEXIBLE & AUTO-NAMING
# Usage:
#   1. ./create-kvm.sh ubuntu             -> Nama VM: "vm-ubuntu"
#   2. ./create-kvm.sh my-custom-vm debian -> Nama VM: "my-custom-vm"
# ==========================================================
PARAM1="${1:-ubuntu}"
PARAM2="$2"

if [ -n "$PARAM2" ]; then
    NAMEKVM="$PARAM1"
    DISTRO_CHOICE="$PARAM2"
else
    DISTRO_CHOICE="$PARAM1"
    NAMEKVM="vm-${DISTRO_CHOICE}"
fi

# Directory Storage
BASE_IMAGE_DIR="/home/satria16alan/Dokumen/kvm/image"
VM_DISK_DIR="/home/satria16alan/Dokumen/kvm/vms"

mkdir -p "$VM_DISK_DIR"

# Mapping Distro (Presisi dengan requirement.sh)
case "$DISTRO_CHOICE" in
  ubuntu)
    BASE_IMAGE_NAME="ubuntu-24.04-minimal-cloudimg-amd64.img"
    OS_VARIANT="ubuntu24.04"
    ;;
  debian)
    BASE_IMAGE_NAME="debian-12-nocloud-amd64.qcow2"
    OS_VARIANT="debian12"
    ;;
  alpine)
    BASE_IMAGE_NAME="alpine-virt-3.20.3-x86_64.iso"
    OS_VARIANT="alpinelinux3.18"
    ;;
  *)
    echo "❌ Distro '$DISTRO_CHOICE' tidak dikenal!"
    exit 1
    ;;
esac

BASE_IMAGE_PATH="${BASE_IMAGE_DIR}/${BASE_IMAGE_NAME}"
ACTIVE_VM_DISK="${VM_DISK_DIR}/${NAMEKVM}.qcow2"

# Validation Base Image
if [ ! -f "$BASE_IMAGE_PATH" ]; then
    echo "❌ Base Image tidak ditemukan di: $BASE_IMAGE_PATH"
    echo "👉 Jalankan './requirement.sh $DISTRO_CHOICE' terlebih dahulu!"
    exit 1
fi

echo "=========================================================="
echo "🚀 [CREATE KVM] Deploying VM: $NAMEKVM ($DISTRO_CHOICE)"
echo "   Target Disk : $ACTIVE_VM_DISK"
echo "=========================================================="

# 1. CLEANUP DOMAIN VM LAMA JIKA ADA
if virsh dominfo "$NAMEKVM" &>/dev/null; then
    echo "🧹 Domain VM '$NAMEKVM' lama terdeteksi, membersihkan..."
    virsh destroy "$NAMEKVM" 2>/dev/null || true
    virsh undefine "$NAMEKVM" 2>/dev/null || true
fi

# 2. CLEANUP FILE DISK LAMA JIKA ADA
if [ -f "$ACTIVE_VM_DISK" ]; then
    echo "🧹 Menghapus file disk lama..."
    rm -f "$ACTIVE_VM_DISK" 2>/dev/null || sudo rm -f "$ACTIVE_VM_DISK"
fi

# 3. BUAT COW OVERLAY DISK
echo "📦 1. Membuat disk turunan (overlay) dari Base Image..."
qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE_PATH" "$ACTIVE_VM_DISK" 20G

# 4. INJECT CREDENTIALS & AUTOLOGIN SEBELUM VM BOOTING (KUNCI UTAMA FIX LOGIN)
if [ "$DISTRO_CHOICE" != "alpine" ]; then
    echo "🔧 2. Injecting credentials, PAM fix & serial autologin..."
    virt-customize -a "$ACTIVE_VM_DISK" \
      --run-command 'useradd -m -s /bin/bash user-al || true' \
      --password user-al:password:useral \
      --root-password password:useral \
      --run-command 'usermod -aG sudo user-al || true' \
      --run-command 'echo "user-al ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user-al' \
      --run-command 'chmod 440 /etc/sudoers.d/user-al' \
      --run-command 'passwd -u user-al || true' \
      --run-command 'passwd -u root || true' \
      --run-command 'touch /etc/cloud/cloud-init.disabled' \
      --run-command 'mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d' \
      --run-command 'echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty -o \"-p -- \\\\u\" --autologin user-al --keep-baud 115200,38400,9600 %I \$TERM" > /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf' \
      --run-command 'systemctl enable systemd-networkd systemd-resolved || true'
fi

# 5. SPIN-UP VM DENGAN VIRT-INSTALL
echo "🖥️  3. Memulai proses virt-install..."
virt-install \
  --virt-type=kvm \
  --name "$NAMEKVM" \
  --ram 3072 \
  --vcpus 2 \
  --disk path="$ACTIVE_VM_DISK",device=disk,bus=virtio,format=qcow2 \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole \
  --os-variant "$OS_VARIANT" \
  --network network=internet-net \
  --check path_in_use=off \
  --import

echo ""
echo "=========================================================="
echo "✅ VM '$NAMEKVM' BERHASIL DIBUAT & RUNNING!"
echo "=========================================================="
echo "  VM Name        : $NAMEKVM"
echo "  Disk Active    : $ACTIVE_VM_DISK"
echo "  Base Image Ref : $BASE_IMAGE_PATH"
echo "----------------------------------------------------------"
echo "  CONSOLE ACCESS :"
echo "    Autologin    : AKTIFF (Langsung tembus bash di virsh console!)"
echo "----------------------------------------------------------"
echo "  CREDENTIALS    :"
echo "    Username     : user-al"
echo "    Password     : useral"
echo "    Sudo         : YES (NOPASSWD)"
echo "=========================================================="
