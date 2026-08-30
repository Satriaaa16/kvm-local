tar -xvf image/$image.ova

cd image
export image="*.vmdk"
cd ../
basename $image .vmdk

qemu-img convert -O qcow2 image/$image.vmdk image/$image.qcow2

cp image/$image.qcow2 /var/lib/libvirt/images/

## https://www.obriain.com/primers/ova2kvm.php
