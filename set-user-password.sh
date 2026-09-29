#!/bin/bash
virt-customize -a image/$image.qcow2 \
  --run-command 'useradd -m -s /bin/bash user-al || true' \
  --password user-al:password:useral \
  --run-command 'usermod -aG sudo user-al || true' \
  --root-password password:useral \
  --run-command 'mkdir -p /etc/network/interfaces.d' \
  --write '/etc/network/interfaces.d/eth0:auto eth0iface eth0 inet dhcp' \
  --run-command 'systemctl enable systemd-networkd || true'
