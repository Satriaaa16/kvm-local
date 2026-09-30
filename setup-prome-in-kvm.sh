#!/bin/bash
set -e

# ==========================================================
# INPUT PARAMETER FLEXIBLE & AUTO-NAMING
# Usage:
#   1. ./setup-prome-in-vm.sh                     -> Nama VM: "vm-ubuntu" (Default)
#   2. ./setup-prome-in-vm.sh debian              -> Nama VM: "vm-debian"
#   3. ./setup-prome-in-vm.sh nginx-devops-repo   -> Nama VM: "nginx-devops-repo"
#   4. ./setup-prome-in-vm.sh my-custom-vm debian -> Nama VM: "my-custom-vm"
# ==========================================================
PARAM1="${1:-ubuntu}"
PARAM2="$2"

if [ -n "$PARAM2" ]; then
    NAMEKVM="$PARAM1"
    DISTRO_CHOICE="$PARAM2"
elif [[ "$PARAM1" == vm-* ]] || [[ "$PARAM1" == *devops* ]]; then
    NAMEKVM="$PARAM1"
    DISTRO_CHOICE="ubuntu"
else
    DISTRO_CHOICE="$PARAM1"
    NAMEKVM="vm-${DISTRO_CHOICE}"
fi

echo "=========================================================="
echo "📊 [JOB 3] Installing Prometheus Server Inside VM: $NAMEKVM"
echo "=========================================================="

echo "⏳ Menyiapkan koneksi console ke VM '$NAMEKVM'..."
sleep 3

# Eksekusi expect untuk install & setup Prometheus di dalam VM via Serial Console
expect <<EOF
set timeout 180
spawn virsh console $NAMEKVM

# 1. Pancing console dengan ENTER ganda
send "\r\r"
sleep 1

# 2. Masuk Sudo Root (Menggunakan Sudo NOPASSWD / Fallback Password)
send "sudo -i\r"
sleep 1
send "useral\r"
sleep 1

# 3. Setup User Prometheus & Direktori di dalam VM
send "useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true\r"
sleep 1

send "mkdir -p /etc/prometheus /var/lib/prometheus /tmp/prom-install\r"
sleep 1

# 4. Download Binary Prometheus v2.54.1 langsung dari dalam VM
send "curl -sSL https://github.com/prometheus/prometheus/releases/download/v2.54.1/prometheus-2.54.1.linux-amd64.tar.gz -o /tmp/prom-install/prometheus.tar.gz\r"
sleep 15

send "tar -C /tmp/prom-install -xzf /tmp/prom-install/prometheus.tar.gz\r"
sleep 3

send "cp /tmp/prom-install/prometheus-2.54.1.linux-amd64/prometheus /usr/local/bin/\r"
send "cp /tmp/prom-install/prometheus-2.54.1.linux-amd64/promtool /usr/local/bin/\r"
send "chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool\r"
sleep 2

# 5. Injeksi Config prometheus.yml di dalam VM (Scrape Node Exporter Lokal & Host/VM Lain)
send "cat <<'YML' > /etc/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus_internal'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
YML\r"
sleep 2

send "chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus\r"
sleep 1

# 6. Buat Systemd Service Prometheus di dalam VM
send "cat <<'SERVICE' > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus Server
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \\
  --config.file=/etc/prometheus/prometheus.yml \\
  --storage.tsdb.path=/var/lib/prometheus \\
  --web.listen-address=0.0.0.0:9090

Restart=always

[Install]
WantedBy=multi-user.target
SERVICE\r"
sleep 2

send "systemctl daemon-reload && systemctl enable --now prometheus\r"
sleep 3

# 7. Cleanup File Instalasi Sementara & Keluar dari Console
send "rm -rf /tmp/prom-install\r"
sleep 1
send "exit\r"
sleep 1
send "exit\r"

expect eof
EOF

# Otomatis Deteksi IP VM dari KVM DHCP
echo "⏳ Deteksi IP VM '$NAMEKVM'..."
VM_IP=""
VM_MAC=$(virsh dumpxml "$NAMEKVM" 2>/dev/null | grep -i "mac address" | head -n 1 | cut -d"'" -f2 || true)

if [ -n "$VM_MAC" ]; then
    VM_IP=$(virsh net-dhcp-leases internet-net 2>/dev/null | grep -i "$VM_MAC" | awk '{print $5}' | cut -d'/' -f1 | head -n 1 || true)
fi

if [ -z "$VM_IP" ]; then
    VM_IP=$(virsh domifaddr "$NAMEKVM" 2>/dev/null | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1 || true)
fi

echo ""
if [ -n "$VM_IP" ]; then
    echo "=========================================================="
    echo "🎉 [JOB 3 SUCCESS] PROMETHEUS BERHASIL DIPASANG DI DALAM VM!"
    echo "=========================================================="
    echo "  VM Name        : $NAMEKVM"
    echo "  IP Address     : $VM_IP"
    echo "  Prometheus Web : http://$VM_IP:9090"
    echo "  Node Exporter  : http://$VM_IP:9100/metrics"
    echo "=========================================================="
else
    echo "✅ Instalasi Prometheus selesai di dalam VM '$NAMEKVM'."
fi
