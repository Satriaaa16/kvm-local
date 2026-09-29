#!/bin/bash
set -e

# ==========================================================
# INPUT PARAMETER
# Usage: ./set-user-password.sh [distro_atau_nama_vm]
# ==========================================================
INPUT_NAME="${1:-ubuntu}"

# 1. Deteksi file disk yang ada di folder vms
if [ -f "/home/satria16alan/Dokumen/kvm/vms/${INPUT_NAME}.qcow2" ]; then
    NAMEKVM="$INPUT_NAME"
elif [ -f "/home/satria16alan/Dokumen/kvm/vms/vm-${INPUT_NAME}.qcow2" ]; then
    NAMEKVM="vm-${INPUT_NAME}"
else
    # Jika file tidak ditemukan, kita set calon namanya
    NAMEKVM="vm-${INPUT_NAME}"
fi

VM_DISK="/home/satria16alan/Dokumen/kvm/vms/${NAMEKVM}.qcow2"

# 2. LOGIKA KONDISIONAL (ADA vs TIDAK ADA FILE)
if [ ! -f "$VM_DISK" ]; then
    echo "=========================================================="
    echo "⚠️  File disk '$VM_DISK' belum ada!"
    echo "🔄 Otomatis memanggil 'create-kvm.sh $INPUT_NAME' untuk membuat VM..."
    echo "=========================================================="
    
    # Pastikan requirement image sudah ada sebelum create
    ./requirement.sh "$INPUT_NAME"
    
    # Buat VM dan disk overlay-nya
    ./create-kvm.sh "$INPUT_NAME"
fi

# 3. MATIKAN VM SEBENTAR AGAR DISK TIDAK TERKUNCI
echo "🛑 Memastikan VM '$NAMEKVM' offline sebelum di-customize..."
virsh destroy "$NAMEKVM" 2>/dev/null || true

# 4. SETELAH FILE PASTI ADA -> INJECT CREDENTIALS
echo "=========================================================="
echo "🔧 [CUSTOMIZE] Injecting credentials & network setup to:"
echo "   $VM_DISK"
echo "=========================================================="

virt-customize -a "$VM_DISK" \
  --run-command 'useradd -m -s /bin/bash user-al || true' \
  --password user-al:useral \
  --root-password password:useral \
  --run-command 'usermod -aG sudo user-al || true' \
  --run-command 'echo "user-al ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user-al' \
  --run-command 'chmod 440 /etc/sudoers.d/user-al' \
  --run-command 'systemctl enable systemd-networkd systemd-resolved || true'

# 5. NYALAKAN KEMBALI VM
echo "🚀 Nyalakan kembali VM '$NAMEKVM'..."
virsh start "$NAMEKVM" 2>/dev/null || true

# 6. SUMMARY KREDENSIAL YANG DI-INJECT
echo ""
echo "=========================================================="
echo "✅ [SUCCESS] CREDENTIALS SUCCESSFULLY INJECTED!"
echo "=========================================================="
echo "  Target VM   : $NAMEKVM"
echo "  Target Disk : $VM_DISK"
echo "----------------------------------------------------------"
echo "  USER ACCESS :"
echo "    Username  : user-al"
echo "    Password  : useral"
echo "    Sudo      : YES (NOPASSWD)"
echo "----------------------------------------------------------"
echo "  ROOT ACCESS :"
echo "    Username  : root"
echo "    Password  : useral"
echo "=========================================================="
