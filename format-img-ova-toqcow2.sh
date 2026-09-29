tar -xvf image/$image.ova

qemu-img convert -O qcow2 image/$image.vmdk image/$image.qcow2

cp image/$image.qcow2 /var/lib/libvirt/images/

## https://www.obriain.com/primers/ova2kvm.php
