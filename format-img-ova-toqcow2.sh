tar -xvf image/$image -C image/

export image-out=$(basename "$image" .ova )

qemu-img convert -O qcow2 image/*.vmdk image/$image-out.qcow2

cp image/$image-out.qcow2 /var/lib/libvirt/images/

## https://www.obriain.com/primers/ova2kvm.php
