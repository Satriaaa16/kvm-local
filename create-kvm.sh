tar -xvf $vm.ova

qemu-img convert -O qcow2 $vm.vmdk $vm.qcow2

cp $vm.qcow2 /virt/kvm/images

## https://www.obriain.com/primers/ova2kvm.php
