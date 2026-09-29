#!/bin/bash

# Exit jika terjadi error
set -e

# Ambil distro dari argumen pertama, jika tidak diisi default ke 'ubuntu'
# Contoh penggunaan: ./requirement.sh debian
DISTRO_CHOICE="${1:-ubuntu}"

IMAGE_DIR="./image"
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
    echo "❌ Distro '$DISTRO_CHOICE' tidak dikenal! (Gunakan: ubuntu | debian | alpine)"
    exit 1
    ;;
esac

IMAGE_PATH="${IMAGE_DIR}/${IMAGE_NAME}"

echo "=========================================================="
echo "🚀 [REQUIREMENT] Menyiapkan Image: $DISTRO_CHOICE"
echo "=========================================================="

if [ -f "$IMAGE_PATH" ]; then
    echo "ℹ️  Image '$IMAGE_NAME' sudah ada di lokal. Skip download."
else
    echo "⬇️  Downloading dari official source..."
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

# ==========================================================
# OUTPUT SUMMARY DI AKHIR (CEK FILE LOKAL)
# ==========================================================
FILE_SIZE=$(du -h "$IMAGE_PATH" | cut -f1)
FULL_PATH=$(realpath "$IMAGE_PATH")

echo ""
echo "=========================================================="
echo "📊 SUMMARY IMAGE READY FOR KVM"
echo "=========================================================="
echo "  Status        : READY ✅"
echo "  Distro Target : $DISTRO_CHOICE"
echo "  File Name     : $IMAGE_NAME"
echo "  File Size     : $FILE_SIZE"
echo "  Absolute Path : $FULL_PATH"
echo "=========================================================="
