#!/bin/bash
set -e

# Variable dari create-kvm.sh
VM_DISK="/home/satria16alan/Dokumen/kvm/vms/${NAMEKVM}.qcow2"

echo "🔧 [CUSTOMIZE] Injecting credentials & network setup to $VM_DISK..."

virt-customize -a "$VM_DISK" \
  --run-command 'useradd -m -s /bin/bash user-al || true' \
  --password user-al:password:useral \
  --run-command 'usermod -aG sudo user-al || true' \
  --root-password password:useral \
  --run-command 'echo "user-al ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user-al' \
  --run-command 'chmod 440 /etc/sudoers.d/user-al' \
  --run-command 'systemctl enable systemd-networkd systemd-resolved || true'
