#!/bin/bash
set -e

NAMEKVM="${1:-vm-ubuntu}"

echo "=========================================================="
echo "🌐 [JOB 2] Injecting Network via Virsh Console: $NAMEKVM"
echo "=========================================================="

# Pastikan tool expect terinstall di host
if ! command -v expect &>/dev/null; then
    echo "📥 Installing 'expect' di Host..."
    sudo apt-get install -y expect &>/dev/null || sudo dnf install -y expect &>/dev/null
fi

echo "⏳ Menunggu VM siap menerima input serial console (10s)..."
sleep 10

# Gunakan expect untuk mengirim command langsung ke console VM
expect <<EOF
set timeout 30
spawn virsh console $NAMEKVM

expect {
    "Escape character is" { send "\r" }
}

expect {
    "user-al@ubuntu:~$" { send "sudo -i\r" }
    "root@ubuntu:~#" { send "\r" }
}

expect "root@ubuntu:~#" { send "ip link set enp1s0 up\r" }
expect "root@ubuntu:~#" { send "mkdir -p /etc/systemd/network\r" }
expect "root@ubuntu:~#" { send "echo -e '\[Match\]\nName=enp1s0\n\n\[Network\]\nDHCP=ipv4' > /etc/systemd/network/10-dhcp.network\r" }
expect "root@ubuntu:~#" { send "systemctl restart systemd-networkd\r" }
expect "root@ubuntu:~#" { send "exit\r" }

expect eof
EOF

echo "⏳ Menunggu alokasi IP DHCP dari KVM..."
VM_IP=""
RETRY_COUNT=0
MAX_RETRIES=15

VM_MAC=$(virsh dumpxml "$NAMEKVM" 2>/dev/null | grep -i "mac address" | head -n 1 | cut -d"'" -f2 || true)

while [ -z "$VM_IP" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    sleep 2
    if [ -n "$VM_MAC" ]; then
        VM_IP=$(virsh net-dhcp-leases internet-net 2>/dev/null | grep -i "$VM_MAC" | awk '{print $5}' | cut -d'/' -f1 | head -n 1 || true)
    fi
    RETRY_COUNT=$((RETRY_COUNT+1))
done

echo ""
echo "=========================================================="
echo "🎉 [PIPELINE SUCCESS] VM '$NAMEKVM' ONLINE!"
echo "=========================================================="
echo "  IP Address     : $VM_IP"
echo "  SSH Access     : ssh user-al@$VM_IP"
echo "  Node Exporter  : http://$VM_IP:9100/metrics"
echo "=========================================================="
