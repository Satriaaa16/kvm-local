#!/bin/bash
set -e

# ==========================================================
# INPUT PARAMETER
# Usage: ./create-kvm.sh <nama_vm> [ubuntu|debian|alpine]
# Contoh: ./create-kvm.sh my-test-vm ubuntu
# ==========================================================
NAMEKVM="${1:-test-vm}"
DISTRO_CHOICE="${2:-ubuntu}"

# Directory Storage Utama
BASE_IMAGE_DIR="/home/satria16alan/Dokumen/kvm/image"
VM_DISK_DIR="/home/satria16alan/Dokumen/kvm/vms"

mkdir -p "$VM_DISK_DIR"

# Map Distro ke File Name
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
    echo "❌ Distro '$DISTRO_CHOICE' tidak valid!"
    exit 1
    ;;
esac

BASE_IMAGE_PATH="${BASE_IMAGE_DIR}/${BASE_IMAGE_NAME}"
ACTIVE_VM_DISK="${VM_DISK_DIR}/${NAMEKVM}.qcow2"

# 1. Cek apakah Base Image hasil requirement.sh ada
if [ ! -f "$BASE_IMAGE_PATH" ]; then
    echo "❌ Base Image tidak ditemukan di: $BASE_IMAGE_PATH"
    echo "👉 Tolong jalankan './requirement.sh $DISTRO_CHOICE' terlebih dahulu!"
    exit 1
fi

echo "=========================================================="
echo "🚀 [CREATE KVM] Deploying VM: $NAMEKVM ($DISTRO_CHOICE)"
echo "=========================================================="

# 2. Buat Copy-On-Write (CoW) Disk Overlay agar Base Image Master aman
echo "📦 Membuat disk turunan (overlay) dari Base Image..."
qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE_PATH" "$ACTIVE_VM_DISK" 20G

# 3. Eksekusi virt-install
echo "🖥️  Proses provisioning virt-install..."
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
echo "  Disk VM Active : $ACTIVE_VM_DISK"
echo "  Base Image Ref : $BASE_IMAGE_PATH"
echo "=========================================================="
