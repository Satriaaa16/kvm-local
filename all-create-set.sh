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
CACHE_DIR="/home/satria16alan/Dokumen/kvm/cache"

mkdir -p "$VM_DISK_DIR" "$CACHE_DIR"

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

# ----------------------------------------------------------
# PRE-FETCH NODE EXPORTER BINARY ON HOST
# ----------------------------------------------------------
NODE_EXPORTER_BIN="${CACHE_DIR}/node_exporter"
if [ ! -f "$NODE_EXPORTER_BIN" ]; then
    echo "📥 Pre-downloading Node Exporter di Host..."
    curl -sSL https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz -o "${CACHE_DIR}/node_exporter.tar.gz"
    tar -C "$CACHE_DIR" -xzf "${CACHE_DIR}/node_exporter.tar.gz"
    mv "${CACHE_DIR}/node_exporter-1.8.2.linux-amd64/node_exporter" "$NODE_EXPORTER_BIN"
    rm -rf "${CACHE_DIR}/node_exporter*"
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

# 4. INJECT CREDENTIALS, FORCE NETWORK UP, AUTOLOGIN & NODE EXPORTER
if [ "$DISTRO_CHOICE" != "alpine" ]; then
    echo "🔧 2. Injecting credentials, Network Force-Up, Autologin & Node Exporter..."
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
      --run-command 'rm -rf /etc/netplan/* /etc/systemd/network/*' \
      --run-command 'mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d' \
      --run-command 'echo -e "[Service]\nExecStart=\nExecStart=-/sbin/agetty -o \"-p -- \\\\u\" --autologin user-al --keep-baud 115200,38400,9600 %I \$TERM" > /etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf' \
      --run-command 'mkdir -p /etc/netplan' \
      --run-command 'echo -e "network:\n  version: 2\n  renderer: networkd\n  ethernets:\n    enp1s0:\n      dhcp4: true\n    ens3:\n      dhcp4: true" > /etc/netplan/01-netcfg.yaml' \
      --run-command 'chmod 600 /etc/netplan/01-netcfg.yaml' \
      --run-command 'echo -e "[Unit]\nDescription=Force Network Interface Up\nAfter=multi-user.target\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/bash -c \"ip link set enp1s0 up 2>/dev/null || true; ip link set ens3 up 2>/dev/null || true; netplan apply 2>/dev/null || true\"\n\n[Install]\nWantedBy=multi-user.target" > /etc/systemd/system/force-net.service' \
      --run-command 'systemctl enable force-net.service systemd-networkd systemd-resolved || true' \
      --run-command 'useradd --no-create-home --shell /bin/false node_exporter || true' \
      --upload "${NODE_EXPORTER_BIN}:/usr/local/bin/node_exporter" \
      --run-command 'chmod 755 /usr/local/bin/node_exporter && chown node_exporter:node_exporter /usr/local/bin/node_exporter' \
      --run-command 'echo -e "[Unit]\nDescription=Node Exporter\nWants=network-online.target\nAfter=network-online.target\n\n[Service]\nUser=node_exporter\nGroup=node_exporter\nType=simple\nExecStart=/usr/local/bin/node_exporter\n\n[Install]\nWantedBy=multi-user.target" > /etc/systemd/system/node_exporter.service' \
      --run-command 'systemctl enable node_exporter.service'
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
  --network network=internet-net,model=virtio \
  --check path_in_use=off \
  --import

# 6. MENGAMBIL DAN MENAMPILKAN IP ADDRESS AUTOMATIS
echo "⏳ Menunggu VM mendapatkan IP Address dari KVM DHCP..."
VM_IP=""
RETRY_COUNT=0
MAX_RETRIES=20

while [ -z "$VM_IP" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    sleep 2
    # Check 1: virsh net-dhcp-leases
    VM_IP=$(virsh net-dhcp-leases internet-net 2>/dev/null | grep -i "$NAMEKVM" | awk '{print $5}' | cut -d'/' -f1 | head -n 1 || true)
    
    # Check 2: virsh domifaddr
    if [ -z "$VM_IP" ]; then
        VM_IP=$(virsh domifaddr "$NAMEKVM" 2>/dev/null | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1 || true)
    fi
    
    RETRY_COUNT=$((RETRY_COUNT+1))
done

# 7. AUTOMATIC HEALTH CHECK
PING_STATUS="SKIPPED"
EXPORTER_STATUS="SKIPPED"

if [ -n "$VM_IP" ] && [[ "$VM_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "🔍 Verifikasi Konektivitas ke IP $VM_IP..."
    if ping -c 2 -W 2 "$VM_IP" &>/dev/null; then
        PING_STATUS="OK (REACHABLE)"
    else
        PING_STATUS="FAILED"
    fi

    echo "🔍 Verifikasi Node Exporter Metrics Endpoint..."
    if curl -s --connect-timeout 3 "http://$VM_IP:9100/metrics" | grep -q "node_exporter"; then
        EXPORTER_STATUS="OK (ONLINE)"
    else
        EXPORTER_STATUS="FAILED / STARTING"
    fi
else
    VM_IP="Sedang dialokasikan (Jalankan 'virsh net-dhcp-leases internet-net' sesaat lagi)"
fi

echo ""
echo "=========================================================="
echo "✅ VM '$NAMEKVM' BERHASIL DIBUAT & RUNNING!"
echo "=========================================================="
echo "  VM Name        : $NAMEKVM"
echo "  Disk Active    : $ACTIVE_VM_DISK"
echo "  IP Address     : $VM_IP"
echo "----------------------------------------------------------"
echo "  PIPELINE HEALTH CHECK :"
echo "    Network Ping : $PING_STATUS"
echo "    Node Exporter: $EXPORTER_STATUS"
echo "----------------------------------------------------------"
echo "  CONSOLE ACCESS :"
echo "    Virsh Command: virsh console $NAMEKVM"
echo "    Autologin    : AKTIFF (Langsung tembus bash)"
echo "----------------------------------------------------------"
echo "  SSH ACCESS     :"
echo "    Command      : ssh user-al@$VM_IP"
echo "    Username     : user-al"
echo "    Password     : useral"
echo "    Sudo Priv    : YES (NOPASSWD)"
echo "----------------------------------------------------------"
echo "  MONITORING METRICS :"
echo "    Node Exporter: http://$VM_IP:9100/metrics"
echo "=========================================================="
