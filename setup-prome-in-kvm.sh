#!/bin/bash
set -eo pipefail

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

if [ "$(virsh domstate "$NAMEKVM" 2>/dev/null || echo "stopped")" != "running" ]; then
    echo "⚠️  VM '$NAMEKVM' belum running, menyalakan..."
    virsh start "$NAMEKVM" || true
    sleep 8
fi

echo "⏳ Menyiapkan koneksi serial console ke VM '$NAMEKVM'..."

expect <<EOF
set timeout 180
log_user 1

spawn virsh console $NAMEKVM

# 1. Tunggu koneksi serial aktif lalu pancing ENTER sampai prompt login muncul
expect "Escape character is"
sleep 2
send "\r\r"

# 2. Handshake Login TTY Berurutan & Presisi
expect {
    "login:" {
        send "user-al\r"
        expect "Password:"
        send "useral\r"
        expect {
            "*$*" {
                send "sudo -i\r"
                expect {
                    "password for" { send "useral\r" }
                    "*#*" { }
                }
            }
            "*#*" { }
        }
    }
    "*$*" {
        send "sudo -i\r"
        expect {
            "password for" { send "useral\r" }
            "*#*" { }
        }
    }
    "*#*" {
        # Sudah posisi root
    }
}

# Pastikan sudah di prompt Root (#) sebelum lanjut
expect "*#*"

# 3. Setup User & Direktori Prometheus di dalam VM
send "useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true\r"
expect "*#*"

send "mkdir -p /etc/prometheus /var/lib/prometheus /tmp/prom-install\r"
expect "*#*"

# 4. Download & Extract Binary Prometheus v2.54.1
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

# 5. Inject Konfigurasi prometheus.yml (Aman tanpa quotes clash)
send "echo -e 'global:\n  scrape_interval: 15s\n\nscrape_configs:\n  - job_name: prometheus_internal\n    static_configs:\n      - targets: [localhost:9090]\n\n  - job_name: node_exporter\n    static_configs:\n      - targets: [localhost:9100]' > /etc/prometheus/prometheus.yml\r"
expect "*#*"

send "chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus\r"
expect "*#*"

# 6. Inject Systemd Unit Service Prometheus
send "echo -e '[Unit]\nDescription=Prometheus Server\nWants=network-online.target\nAfter=network-online.target\n\n[Service]\nUser=prometheus\nGroup=prometheus\nType=simple\nExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --web.listen-address=0.0.0.0:9090\nRestart=always\n\n[Install]\nWantedBy=multi-user.target' > /etc/systemd/system/prometheus.service\r"
expect "*#*"

send "systemctl daemon-reload && systemctl enable --now prometheus\r"
expect "*#*"

# 7. Cleanup & Exit Console
send "rm -rf /tmp/prom-install\r"
expect "*#*"

send "exit\r"
expect "*$*"
send "exit\r"

send "\x1d"
expect eof
EOF

# Deteksi IP VM
echo ""
echo "⏳ Deteksi IP VM '$NAMEKVM'..."
VM_IP=""
VM_IP=$(virsh domifaddr "$NAMEKVM" 2>/dev/null | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1 || true)

if [ -z "$VM_IP" ]; then
    VM_MAC=$(virsh dumpxml "$NAMEKVM" 2>/dev/null | grep -i "mac address" | head -n 1 | cut -d"'" -f2 || true)
    if [ -n "$VM_MAC" ]; then
        VM_IP=$(virsh net-dhcp-leases internet-net 2>/dev/null | grep -i "$VM_MAC" | awk '{print $5}' | cut -d'/' -f1 | head -n 1 || true)
    fi
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
    echo "=========================================================="
    echo "✅ Instalasi Selesai di VM '$NAMEKVM'."
    echo "=========================================================="
fi
