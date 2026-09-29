#!/bin/bash
set -e

DISTRO_CHOICE="${1:-ubuntu}"

# ==========================================================
# UBAH KELUAR KE DIREKTORI LOKAL HOST PERMANEN
# ==========================================================
IMAGE_DIR="/home/satria16alan/Dokumen/kvm/image"
# Atau bisa juga pakai: IMAGE_DIR="/var/lib/libvirt/images"

mkdir -p "$IMAGE_DIR"

case "$DISTRO_CHOICE" in
  ubuntu)
    IMAGE_NAME="ubuntu-24.04-minimal-cloudimg-amd64.img"
    IMAGE_URL="https://cloud-images.ubuntu.com/minimal/releases/noble/release/ubuntu-24.04-minimal-cloudimg-amd64.img"
    ;;
  debian)
    IMAGE_NAME="debian-12-nocloud-amd64.qcow2"
    IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.qcow2"
    ;;
  alpine)
    IMAGE_NAME="alpine-virt-3.20.3-x86_64.iso"
    IMAGE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/alpine-virt-3.20.3-x86_64.iso"
    ;;
  *)
    echo "❌ Distro '$DISTRO_CHOICE' tidak dikenal!"
    exit 1
    ;;
esac

IMAGE_PATH="${IMAGE_DIR}/${IMAGE_NAME}"

echo "=========================================================="
echo "🚀 [REQUIREMENT] Menyiapkan Image di Host Local: $DISTRO_CHOICE"
echo "=========================================================="

if [ -f "$IMAGE_PATH" ]; then
    echo "ℹ️  Image '$IMAGE_NAME' sudah ada di Host ($IMAGE_PATH)."
    echo "⚡ Skip download!"
else
    echo "⬇️  Downloading langsung ke folder lokal host..."
    echo "    URL: $IMAGE_URL"
    
    if command -v curl &> /dev/null; then
        curl -L -o "$IMAGE_PATH" "$IMAGE_URL" --progress-bar
    elif command -v wget &> /dev/null; then
        wget -O "$IMAGE_PATH" "$IMAGE_URL"
    else
        echo "❌ Error: 'curl' atau 'wget' tidak ditemukan!"
        exit 1
    fi
fi

# Summary
FILE_SIZE=$(du -h "$IMAGE_PATH" | cut -f1)

echo ""
echo "=========================================================="
echo "📊 SUMMARY IMAGE READY ON HOST LOCAL"
echo "=========================================================="
echo "  Status        : READY ✅"
echo "  Absolute Path : $IMAGE_PATH"
echo "  File Size     : $FILE_SIZE"
echo "=========================================================="
