tar -xvf image/$image.ova

cd image
export image="*.vmdk"
echo $image
cd ../
export image=$(basename $image .vmdk)
evho $image

qemu-img convert -O qcow2 image/$image.vmdk image/$image.qcow2

cp image/$image.qcow2 /var/lib/libvirt/images/

## https://www.obriain.com/primers/ova2kvm.php
