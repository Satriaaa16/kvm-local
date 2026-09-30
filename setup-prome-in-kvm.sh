#!/bin/bash
set -eo pipefail

PARAM1="${1:-ubuntu}"
PARAM2="$2"

if [ -n "$PARAM2" ]; then
    NAMEKVM="$PARAM1"
    DISTRO_CHOICE="$PARAM2"
elif [[ "$PARAM1" == vm-* ]] \vert{}\vert{} [[ "$PARAM1" == *devops* ]]; then
    NAMEKVM="$PARAM1"
    DISTRO_CHOICE="ubuntu"
else
    DISTRO_CHOICE="$PARAM1"
    NAMEKVM="vm-${DISTRO_CHOICE}"
fi

echo "=========================================================="
echo "📊 [JOB 3] Installing Prometheus Server Inside VM: $NAMEKVM"
echo "=========================================================="

# Pastikan VM running
if [ "$(virsh domstate "$NAMEKVM" 2>/dev/null)" != "running" ]; then
    echo "⚠️  VM '$NAMEKVM' belum running, menyalakan..."
    virsh start "$NAMEKVM"
    sleep 8
fi

echo "⏳ Menyiapkan koneksi serial console ke VM '$NAMEKVM'..."

expect <<EOF
set timeout 180
log_user 1

spawn virsh console $NAMEKVM

# 1. Pancing console agar memunculkan prompt
send "\r\r"
sleep 2

# 2. Handshake Login & Root Privileges
expect {
    "login:" {
        send "user-al\r"
        expect "Password:"
        send "useral\r"
        expect "*$*"
        send "sudo -i\r"
    }
    "user-al@ubuntu:~$" {
        send "sudo -i\r"
    }
    "root@ubuntu:~#" {
        # Sudah di root
    }
    timeout {
        send "\r"
        send "sudo -i\r"
    }
}

# 3. Tangani Password Sudo jika diminta
expect {
    "password for" { send "useral\r"; expect "*#*" }
    "*#*" { }
}

# 4. Setup User & Direktori Prometheus di VM
send "useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true\r"
expect "*#*"

send "mkdir -p /etc/prometheus /var/lib/prometheus /tmp/prom-install\r"
expect "*#*"

# 5. Download & Extract Binary Prometheus v2.54.1
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

# 6. Inject Konfigurasi prometheus.yml
send "echo -e 'global:\n  scrape_interval: 15s\n\nscrape_configs:\n  - job_name: \"prometheus_internal\"\n    static_configs:\n      - targets: [\"localhost:9090\"]\n\n  - job_name: \"node_exporter\"\n    static_configs:\n      - targets: [\"localhost:9100\"]' > /etc/prometheus/prometheus.yml\r"
expect "*#*"

send "chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus\r"
expect "*#*"

# 7. Inject Systemd Unit Service Prometheus
send "echo -e '[Unit]\nDescription=Prometheus Server\nWants=network-online.target\nAfter=network-online.target\n\n[Service]\nUser=prometheus\nGroup=prometheus\nType=simple\nExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --web.listen-address=0.0.0.0:9090\nRestart=always\n\n[Install]\nWantedBy=multi-user.target' > /etc/systemd/system/prometheus.service\r"
expect "*#*"

send "systemctl daemon-reload && systemctl enable --now prometheus\r"
expect "*#*"

# 8. Cleanup & Detach Console
send "rm -rf /tmp/prom-install\r"
expect "*#*"

send "exit\r"
expect "*$*"
The `virsh console` attempt failed because the interactive login prompt timed out while waiting for a response, preventing the script from executing commands inside the virtual machine.

Here is how to fix the issue depending on your goal:

---

### Option 1: Use `virt-customize` or `virt-builder` (Recommended for Automation)
If you are automating VM provisioning, interactive `virsh console` scripts using `expect` or `spawn` are notoriously fragile due to timing issues. Instead, inject files or run commands directly into the VM image offline using `virt-customize`:

```bash
# Shutdown the VM first
virsh shutdown vm-ubuntu

# Execute setup directly on the disk image
virt-customize -a /path/to/vm-ubuntu.qcow2 \
  --upload setup-prome-in-kvm.sh:/tmp/setup.sh \
  --run-command 'chmod +x /tmp/setup.sh && /tmp/setup.sh'

# Start the VM back up
virsh start vm-ubuntu
