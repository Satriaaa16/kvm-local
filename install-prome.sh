#!/bin/bash
set -e

# ==========================================================
# PROMETHEUS INSTALLER & AUTO-TARGET DISCOVERY FOR KVM
# Usage:
#   1. ./install-prometheus.sh          -> Auto-register target vm-ubuntu
#   2. ./install-prometheus.sh debian   -> Auto-register target vm-debian
# ==========================================================
DISTRO_TARGET="${1:-ubuntu}"
NAMEKVM="vm-${DISTRO_TARGET}"

PROMETHEUS_VERSION="2.54.1"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/prometheus"
DATA_DIR="/var/lib/prometheus"
CACHE_DIR="/home/satria16alan/Dokumen/kvm/cache"

mkdir -p "$CONFIG_DIR" "$DATA_DIR" "$CACHE_DIR"

echo "=========================================================="
echo "📊 [PROMETHEUS] Installing & Configuring Prometheus Server"
echo "=========================================================="

# 1. SETUP USER & GROUP PROMETHEUS
if ! id "prometheus" &>/dev/null; then
    echo "👤 Membuat system user 'prometheus'..."
    sudo useradd --no-create-home --shell /bin/false prometheus || true
fi

# 2. DOWNLOAD & EXTRACT PROMETHEUS BINARY
PROM_TAR="${CACHE_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
PROM_EXTRACT_DIR="${CACHE_DIR}/prometheus-${PROMETHEUS_VERSION}.linux-amd64"

if [ ! -f "${INSTALL_DIR}/prometheus" ]; then
    echo "📥 Pre-downloading Prometheus Binary v${PROMETHEUS_VERSION}..."
    if [ ! -f "$PROM_TAR" ]; then
        curl -sSL "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz" -o "$PROM_TAR"
    fi
    tar -C "$CACHE_DIR" -xzf "$PROM_TAR"
    
    sudo cp "${PROM_EXTRACT_DIR}/prometheus" "${INSTALL_DIR}/"
    sudo cp "${PROM_EXTRACT_DIR}/promtool" "${INSTALL_DIR}/"
    
    sudo chown prometheus:prometheus "${INSTALL_DIR}/prometheus" "${INSTALL_DIR}/promtool"
    rm -rf "$PROM_EXTRACT_DIR"
    echo "✅ Prometheus binary berhasil terpasang di $INSTALL_DIR"
fi

# 3. DETEKSI IP TARGET VM KVM AUTOMATIS
echo "🔍 Mencari IP Address untuk VM target '$NAMEKVM'..."
TARGET_IP=""
VM_MAC=$(virsh dumpxml "$NAMEKVM" 2>/dev/null | grep -i "mac address" | head -n 1 | cut -d"'" -f2 || true)

if [ -n "$VM_MAC" ]; then
    TARGET_IP=$(virsh net-dhcp-leases internet-net 2>/dev/null | grep -i "$VM_MAC" | awk '{print $5}' | cut -d'/' -f1 | head -n 1 || true)
fi

if [ -z "$TARGET_IP" ]; then
    TARGET_IP=$(virsh domifaddr "$NAMEKVM" 2>/dev/null | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1 || true)
fi

if [ -n "$TARGET_IP" ]; then
    echo "🎯 IP Target KVM Ditemukan: $TARGET_IP"
    TARGET_SPEC="'$TARGET_IP:9100'"
else
    echo "⚠️  IP Target VM '$NAMEKVM' belum terdeteksi/offline. Menggunakan IP dummy '192.168.100.73:9100'..."
    TARGET_SPEC="'192.168.100.73:9100'"
fi

# 4. BUAT FILE KONFIGURASI PROMETHEUS (prometheus.yml)
echo "⚙️  Membuat file konfigurasi Prometheus di ${CONFIG_DIR}/prometheus.yml..."
sudo bash -c "cat <<EOF > ${CONFIG_DIR}/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus_host'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'kvm_node_exporter'
    static_configs:
      - targets: [$TARGET_SPEC]
        labels:
          environment: 'kvm-lab'
          vm_name: '$NAMEKVM'
EOF"

sudo chown -R prometheus:prometheus "$CONFIG_DIR" "$DATA_DIR"

# 5. BUAT SYSTEMD SERVICE FOR PROMETHEUS
echo "🔧 Menyiapkan Systemd Service untuk Prometheus..."
sudo bash -c "cat <<EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus Server
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=${INSTALL_DIR}/prometheus \\
  --config.file=${CONFIG_DIR}/prometheus.yml \\
  --storage.tsdb.path=${DATA_DIR} \\
  --web.console.templates=${CONFIG_DIR}/consoles \\
  --web.console.libraries=${CONFIG_DIR}/console_libraries \\
  --web.listen-address=0.0.0.0:9090

Restart=always

[Install]
WantedBy=multi-user.target
EOF"

# 6. RELOAD & RESTART PROMETHEUS SERVICE
echo "🔄 Reloading Systemd & Restarting Prometheus..."
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl restart prometheus

echo ""
echo "=========================================================="
echo "🎉 PROMETHEUS SERVER BERHASIL DIPASANG & RUNNING!"
echo "=========================================================="
echo "  URL Dashboard  : http://localhost:9090"
echo "  Config Path    : ${CONFIG_DIR}/prometheus.yml"
echo "  Target Node    : $TARGET_SPEC"
echo "  Status Service : $(systemctl is-active prometheus)"
echo "=========================================================="
