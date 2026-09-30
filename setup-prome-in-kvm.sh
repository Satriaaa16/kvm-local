#!/bin/bash
set -eo pipefail

# ==========================================================
# INPUT PARAMETER FLEXIBLE & AUTO-NAMING
# Usage:
#   1. ./setup-prome-in-vm.sh                 -> Nama VM: "vm-ubuntu" (Default)
#   2. ./setup-prome-in-vm.sh debian          -> Nama VM: "vm-debian"
#   3. ./setup-prome-in-vm.sh nginx-devops    -> Nama VM: "nginx-devops"
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

# Validasi apakah command 'expect' dan 'virsh' tersedia di Host
for cmd in expect virsh; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ Error: Command '$cmd' tidak ditemukan. Harap install terlebih dahulu."
        exit 1
    fi
done

# Pastikan VM sedang berjalan
VM_STATE=$(virsh domstate "$NAMEKVM" 2>/dev/null || echo "not_found")
if [ "$VM_STATE" != "running" ]; then
    echo "⚠️  VM '$NAMEKVM' sedang tidak berjalan (Status: $VM_STATE). Menyalakan VM..."
    virsh start "$NAMEKVM" || { echo "❌ Gagal menyalakan VM '$NAMEKVM'"; exit 1; }
    echo "⏳ Menunggu boot VM selama 10 detik..."
    sleep 10
fi

echo "⏳ Menyiapkan koneksi serial console ke VM '$NAMEKVM'..."

# Eksekusi expect untuk install & setup Prometheus di dalam VM via Serial Console
expect <<EOF
set timeout 300
log_user 1

spawn virsh console $NAMEKVM

# 1. Pancing TTY Console dengan ENTER
send "\r\r"
expect {
    "login:" {
        send "useral\r"
        expect "Password:"
        send "useral\r"
        expect "*$*"
        send "sudo -i\r"
        expect "password for"
        send "useral\r"
    }
    "*$*" {
        send "sudo -i\r"
        expect "*password*"
        send "useral\r"
    }
    "*#*" {
        # Sudah berada di root
    }
    timeout {
        send "\r"
    }
}

expect "*#*"

# 2. Setup User & Direktori Prometheus
send "useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true\r"
expect "*#*"

send "mkdir -p /etc/prometheus /var/lib/prometheus /tmp/prom-install\r"
expect "*#*"

# 3. Download Binary Prometheus v2.54.1 dari dalam VM
send "curl -sSL https://github.com/prometheus/prometheus/releases/download/v2.54.1/prometheus-2.54.1.linux-amd64.tar.gz -o /tmp/prom-install/prometheus.tar.gz\r"
expect "*#*"

send "tar -C /tmp/prom-install -xzf /tmp/prom-install/prometheus.tar.gz\r"
expect "*#*"

send "cp /tmp/prom-install/prometheus-2.54.1.linux-amd64/prometheus /usr/local/bin/\r"
expect "*#*"
send "cp /tmp/prom-install/prometheus-2.54.1.linux-amd64/promtool /usr/local/bin/\r"
expect "*#*"
send "chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool\r"
expect "*#*"

# 4. Injeksi Configuration file (prometheus.yml)
send "cat <<'YML' > /etc/prometheus/prometheus.yml\r"
send "global:\r"
send "  scrape_interval: 15s\r"
send "scrape_configs:\r"
send "  - job_name: 'prometheus_internal'\r"
send "    static_configs:\r"
send "      - targets: ['localhost:9090']\r"
send "  - job_name: 'node_exporter'\r"
send "    static_configs:\r"
send "      - targets: ['localhost:9100']\r"
send "YML\r"
expect "*#*"

send "chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus\r"
expect "*#*"

# 5. Buat Systemd Unit Service
send "cat <<'SERVICE' > /etc/systemd/system/prometheus.service\r"
send "[Unit]\r"
send "Description=Prometheus Server\r"
send "Wants=network-online.target\r"
send "After=network-online.target\r"
send "\r"
send "[Service]\r"
send "User=prometheus\r"
send "Group=prometheus\r"
send "Type=simple\r"
send "ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --web.listen-address=0.0.0.0:9090\r"
send "Restart=always\r"
send "\r"
send "[Install]\r"
send "WantedBy=multi-user.target\r"
send "SERVICE\r"
expect "*#*"

# 6. Enable & Start Service Prometheus
send "systemctl daemon-reload && systemctl enable --now prometheus\r"
expect "*#*"

# 7. Cleanup & Keluar dari Console
send "rm -rf /tmp/prom-install\r"
expect "*#*"

send "exit\r"
expect "*$*"
send "exit\r"

# Kirim Ctrl+] (\x1d) untuk exit dari virsh console secara bersih
send "\x1d"
expect eof
EOF

# Otomatis Deteksi IP VM dari KVM DHCP / Guest Agent
echo ""
echo "⏳ Mendeteksi IP Address VM '$NAMEKVM'..."
VM_IP=""

# Method 1: Cek via virsh domifaddr (KVM Guest Agent / ARP)
VM_IP=$(virsh domifaddr "$NAMEKVM" 2>/dev/null | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1 || true)

# Method 2: Fallback via Network DHCP Leases jika Method 1 kosong
if [ -z "$VM_IP" ]; then
    VM_MAC=$(virsh dumpxml "$NAMEKVM" 2>/dev/null | grep -i "mac address" | head -n 1 | cut -d"'" -f2 || true)
    if [ -n "$VM_MAC" ]; then
        VM_IP=$(virsh net-dhcp-leases internet-net 2>/dev/null | grep -i "$VM_MAC" | awk '{print $5}' | cut -d'/' -f1 | head -n 1 || true)
    fi
fi

echo ""
if [ -n "$VM_IP" ]; then
    echo "=========================================================="
    echo "🎉 [JOB 3 SUCCESS] PROMETHEUS BERHASIL DIPASANG DI VM!"
    echo "=========================================================="
    echo "  VM Name        : $NAMEKVM"
    echo "  IP Address     : $VM_IP"
    echo "  Prometheus Web : http://$VM_IP:9090"
    echo "  Node Exporter  : http://$VM_IP:9100/metrics"
    echo "=========================================================="
else
    echo "=========================================================="
    echo "✅ Instalasi Selesai di VM '$NAMEKVM'."
    echo "⚠️  IP VM belum terdeteksi otomatis. Silakan cek IP manual."
    echo "=========================================================="
fi
