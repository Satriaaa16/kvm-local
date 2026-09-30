#!/bin/bash
set -e

# ==========================================================
# INPUT PARAMETER FLEXIBLE & AUTO-NAMING (Sesuai all-create-set.sh)
# Usage:
#   1. ./setup-network.sh ubuntu             -> Nama VM target: "vm-ubuntu"
#   2. ./setup-network.sh my-custom-vm debian -> Nama VM target: "my-custom-vm"
#   3. ./setup-network.sh                    -> Default: "vm-ubuntu"
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

echo "=========================================================="
echo "🌐 [JOB 2] Injecting Network via Virsh Console: $NAMEKVM"
echo "=========================================================="

echo "⏳ Menunggu VM '$NAMEKVM' booting sempurna (8 detik)..."
sleep 8

# Eksekusi expect dengan passing $NAMEKVM secara dinamis
expect <<EOF
set timeout 30
spawn virsh console $NAMEKVM

# 1. Pancing console dengan ENTER ganda
send "\r\r"

# 2. Tangani Login (jika belum autologin) maupun Prompt langsung
expect {
    "login:" {
        send "user-al\r"
        expect "Password:"
        send "useral\r"
        exp_continue
    }
    "user-al@ubuntu:~$" {
        send "sudo -i\r"
    }
    "root@ubuntu:~#" {
        send "\r"
    }
    timeout {
        send "\r"
        exp_continue
    }
}

# 3. Tangani Sudo Password jika diminta
expect {
    "\[sudo\] password for user-al:" { send "useral\r" }
    "root@ubuntu:~#" { send "\r" }
}

# 4. Naikan Link Interface enp1s0
expect "root@ubuntu:~#" { send "ip link set enp1s0 up\r" }
sleep 1

# 5. Injeksi Config systemd-networkd DHCP
expect "root@ubuntu:~#" { send "mkdir -p /etc/systemd/network\r" }
sleep 1

expect "root@ubuntu:~#" { send "echo -e '\[Match\]\nName=enp1s0\n\n\[Network\]\nDHCP=ipv4' > /etc/systemd/network/10-dhcp.network\r" }
sleep 1

# 6. Restart Network Service
expect "root@ubuntu:~#" { send "systemctl restart systemd-networkd systemd-resolved\r" }
sleep 3

# 7. Fallback Trigger DHCP
expect "root@ubuntu:~#" { send "dhclient enp1s0 2>/dev/null || true\r" }
sleep 2

# 8. Keluar dari Root & Console secara bersih
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
    echo "  VM Name        : $NAMEKVM"
    echo "  IP Address     : $VM_IP"
    echo "  SSH Access     : ssh user-al@$VM_IP"
    echo "  Node Exporter  : http://$VM_IP:9100/metrics"
    echo "=========================================================="
else
    echo "❌ IP Belum tertangkap di DHCP Leases KVM."
    exit 1
fi
