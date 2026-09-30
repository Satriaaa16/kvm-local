#!/bin/bash
set -e

NAMEKVM="${1:-vm-ubuntu}"

echo "=========================================================="
echo "🌐 [JOB 2] Injecting Network via Virsh Console: $NAMEKVM"
echo "=========================================================="

echo "⏳ Menunggu VM booting sempurna (5 detik)..."
sleep 5

# Eksekusi expect dengan penanganan prompt autologin
expect <<'EOF'
set timeout 20
spawn virsh console vm-ubuntu

# 1. Pancing console tekan ENTER sampai dapat prompt
send "\r"
expect {
    "user-al@ubuntu:~$" { send "sudo -i\r" }
    "root@ubuntu:~#" { send "\r" }
    timeout { send "\r"; exp_continue }
}

# 2. Masukkan password sudo jika diminta (Sudo NOPASSWD di-handle aman)
expect {
    "password for user-al:" { send "useral\r" }
    "root@ubuntu:~#" { send "\r" }
}

# 3. Naikan Link Interface
expect "root@ubuntu:~#" { send "ip link set enp1s0 up\r" }
sleep 1

# 4. Injeksi Config systemd-networkd DHCP
expect "root@ubuntu:~#" { send "mkdir -p /etc/systemd/network\r" }
sleep 1

expect "root@ubuntu:~#" { send "echo -e '\[Match\]\nName=enp1s0\n\n\[Network\]\nDHCP=ipv4' > /etc/systemd/network/10-dhcp.network\r" }
sleep 1

# 5. Restart Network Service
expect "root@ubuntu:~#" { send "systemctl restart systemd-networkd systemd-resolved\r" }
sleep 3

# 6. Fallback trigger DHCP jika systemd-networkd lambat
expect "root@ubuntu:~#" { send "dhclient enp1s0 2>/dev/null || true\r" }
sleep 2

# 7. Keluar dari Root & Console
expect "root@ubuntu:~#" { send "exit\r" }
expect "user-al@ubuntu:~$" { send "exit\r" }

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
    if [ -z "$VM_IP" ]; then
        VM_IP=$(virsh domifaddr "$NAMEKVM" 2>/dev/null | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1 || true)
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
    echo "❌ IP Belum tertangkap di DHCP Leases KVM."
    exit 1
fi
