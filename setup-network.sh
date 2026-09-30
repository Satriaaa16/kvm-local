#!/bin/bash
set -e

NAMEKVM="${1:-vm-ubuntu}"

echo "=========================================================="
echo "🌐 [JOB 2] Injecting Network via Virsh Console: $NAMEKVM"
echo "=========================================================="

echo "⏳ Menunggu VM booting sempurna (8 detik)..."
sleep 8

# Eksekusi expect dengan penanganan prompt ketat
expect <<EOF
set timeout 15
spawn virsh console $NAMEKVM

# 1. Pancing console dengan ENTER
expect {
    "Escape character is" { send "\r"; exp_continue }
    "ubuntu login:" { send "user-al\r"; exp_continue }
    "Password:" { send "useral\r"; exp_continue }
    "user-al@ubuntu:~$" { send "sudo -i\r" }
    "root@ubuntu:~#" { send "\r" }
}

# 2. Masukkan password sudo jika diminta
expect {
    "[sudo] password for user-al:" { send "useral\r" }
    "root@ubuntu:~#" { send "\r" }
}

# 3. Eksekusi Perintah Network
expect "root@ubuntu:~#" { send "ip link set enp1s0 up\r" }
sleep 1

expect "root@ubuntu:~#" { send "mkdir -p /etc/systemd/network\r" }
sleep 1

expect "root@ubuntu:~#" { send "echo -e '\[Match\]\nName=enp1s0\n\n\[Network\]\nDHCP=ipv4' > /etc/systemd/network/10-dhcp.network\r" }
sleep 1

expect "root@ubuntu:~#" { send "systemctl restart systemd-networkd systemd-resolved\r" }
sleep 2

expect "root@ubuntu:~#" { send "exit\r" }
sleep 1

expect "user-al@ubuntu:~$" { send "exit\r" }

expect eof
EOF

echo "⏳ Menunggu alokasi IP DHCP dari KVM..."
VM_IP=""
RETRY_COUNT=0
MAX_RETRIES=10

VM_MAC=$(virsh dumpxml "$NAMEKVM" 2>/dev/null | grep -i "mac address" | head -n 1 | cut -d"'" -f2 || true)

while [ -z "$VM_IP" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    sleep 2
    if [ -n "$VM_MAC" ]; then
        VM_IP=$(virsh net-dhcp-leases internet-net 2>/dev/null | grep -i "$VM_MAC" | awk '{print $5}' | cut -d'/' -f1 | head -n 1 || true)
    fi
    RETRY_COUNT=$((RETRY_COUNT+1))
done

echo ""
if [ -n "$VM_IP" ]; then
    echo "=========================================================="
    echo "🎉 [JOB 2 SUCCESS] NETWORK UP & IP ALLOCATED!"
    echo "=========================================================="
    echo "  IP Address     : $VM_IP"
    echo "  SSH Access     : ssh user-al@$VM_IP"
    echo "  Node Exporter  : http://$VM_IP:9100/metrics"
    echo "=========================================================="
else
    echo "❌ IP Belum tertangkap, silakan cek manual via console."
fi
