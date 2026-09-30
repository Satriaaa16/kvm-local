#!/bin/bash
set -e

# ==========================================================
# INPUT PARAMETERS (Selaras 100% dengan requirement.sh & create-kvm.sh)
# Usage di Pipeline:
#   1. Default (Tanpa Password):
#      ./set-user-password.sh ubuntu
#   2. Opsional (Dengan Password Custom):
#      ./set-user-password.sh ubuntu --password rahasia123
# ==========================================================
DISTRO_CHOICE="${1:-ubuntu}"
FLAG="${2}"
CUSTOM_PASS="${3}"

# Auto-mapping nama VM & Disk sesuai standar create-kvm.sh
NAMEKVM="vm-${DISTRO_CHOICE}"
VM_DISK_DIR="/home/satria16alan/Dokumen/kvm/vms"
VM_DISK="${VM_DISK_DIR}/${NAMEKVM}.qcow2"

# 1. LOGIKA KONDISIONAL BILA DISK BELUM ADA
if [ ! -f "$VM_DISK" ]; then
    echo "=========================================================="
    echo "⚠️  File disk '$VM_DISK' belum ditemukan!"
    echo "🔄 Memanggil 'requirement.sh' & 'create-kvm.sh' untuk $DISTRO_CHOICE..."
    echo "=========================================================="

    ./requirement.sh "$DISTRO_CHOICE"
    ./create-kvm.sh "$DISTRO_CHOICE"
fi

# 2. MATIKAN VM SEBENTAR AGAR DISK TIDAK TERKUNCI OLEH KVM
echo "🛑 Memastikan VM '$NAMEKVM' offline sebelum di-customize..."
virsh destroy "$NAMEKVM" 2>/dev/null || true

# 3. PENENTUAN MODE: DEFAULT (PASSWORDLESS) VS WITH PASSWORD
if [ "$FLAG" == "--password" ] && [ -n "$CUSTOM_PASS" ]; then
    MODE_INFO="WITH PASSWORD ($CUSTOM_PASS)"
    PASS_ARGS=(
      --password "user-al:password:${CUSTOM_PASS}"
      --root-password "password:${CUSTOM_PASS}"
    )
    EXTRA_CMDS=()
else
    MODE_INFO="PASSWORDLESS (FULL CONSOLE & SSH ACCESS)"
    PASS_ARGS=()
    EXTRA_CMDS=(
      --run-command 'passwd -d user-al'
      --run-command 'passwd -d root'
      --run-command 'sed -i "s/#PermitEmptyPasswords no/PermitEmptyPasswords yes/g" /etc/ssh/sshd_config || true'
      --run-command 'sed -i "s/PermitEmptyPasswords no/PermitEmptyPasswords yes/g" /etc/ssh/sshd_config || true'
      --run-command 'sed -i "s/nullok_secure/nullok/g" /etc/pam.d/common-auth || true'
      --run-command 'sed -i "s/pam_unix.so/pam_unix.so nullok/g" /etc/pam.d/common-auth || true'
      --run-command 'sed -i "s/pam_unix.so nullok nullok/pam_unix.so nullok/g" /etc/pam.d/common-auth || true'
    )
fi

echo "=========================================================="
echo "🔧 [CUSTOMIZE] Mode: $MODE_INFO"
echo "   Target VM  : $NAMEKVM"
echo "   Target Disk: $VM_DISK"
echo "=========================================================="

# 4. INJECT CREDENTIALS & SUDO PRIVILEGES
virt-customize -a "$VM_DISK" \
  --run-command 'useradd -m -s /bin/bash user-al || true' \
  "${PASS_ARGS[@]}" \
  "${EXTRA_CMDS[@]}" \
  --run-command 'usermod -aG sudo user-al || true' \
  --run-command 'echo "user-al ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user-al' \
  --run-command 'chmod 440 /etc/sudoers.d/user-al' \
  --run-command 'systemctl enable systemd-networkd systemd-resolved || true'

# 5. NYALAKAN KEMBALI VM
echo "🚀 Nyalakan kembali VM '$NAMEKVM'..."
virsh start "$NAMEKVM" 2>/dev/null || true

# 6. SUMMARY OUTPUT PIPELINE
echo ""
echo "=========================================================="
echo "✅ [SUCCESS] CREDENTIALS SUCCESSFULLY APPLIED!"
echo "=========================================================="
echo "  Target VM   : $NAMEKVM"
echo "  Target Disk : $VM_DISK"
echo "  Config Mode : $MODE_INFO"
echo "----------------------------------------------------------"
echo "  USER ACCESS :"
echo "    Username  : user-al"
if [ "$FLAG" == "--password" ] && [ -n "$CUSTOM_PASS" ]; then
    echo "    Password  : $CUSTOM_PASS"
else
    echo "    Password  : (NONE / Cukup tekan Enter saat diminta Password)"
fi
echo "    Sudo      : YES (NOPASSWD)"
echo "=========================================================="
