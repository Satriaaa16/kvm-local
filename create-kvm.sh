#!/bin/bash
set -e

# ==========================================================
# INPUT PARAMETER FLEXIBLE & AUTO-NAMING
# Usage:
#   1. ./create-kvm.sh ubuntu             -> Nama VM otomatis: "vm-ubuntu"
#   2. ./create-kvm.sh my-custom-vm debian -> Nama VM custom: "my-custom-vm"
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

# Mapping Distro (Harus presisi dengan requirement.sh)
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

# 1. CLEANUP DOMAIN VM LAMA JIKA ADA (Mencegah error 'Nama guest sudah digunakan')
if virsh dominfo "$NAMEKVM" &>/dev/null; then
    echo "🧹 Domain VM '$NAMEKVM' lama terdeteksi, membersihkan..."
    virsh destroy "$NAMEKVM" 2>/dev/null || true
    virsh undefine "$NAMEKVM" 2>/dev/null || true
fi

# 2. CLEANUP FILE DISK LAMA JIKA ADA (Mencegah 'Permission Denied' dari qemu-img)
if [ -f "$ACTIVE_VM_DISK" ]; then
    echo "🧹 Menghapus file disk lama..."
    rm -f "$ACTIVE_VM_DISK" 2>/dev/null || sudo rm -f "$ACTIVE_VM_DISK"
fi

# 3. Buat CoW Overlay Disk
echo "📦 1. Membuat disk turunan (overlay) dari Base Image..."
qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE_PATH" "$ACTIVE_VM_DISK" 20G

# 4. Spin-Up VM dengan virt-install
echo "🖥️  2. Memulai proses virt-install..."
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
echo "=========================================================="
