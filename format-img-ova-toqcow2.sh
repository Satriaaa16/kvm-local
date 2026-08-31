tar -xvf image/$image -C image/

export imageqc=$(basename "$image" .ova )
echo $imageqc

qemu-img convert -O qcow2 image/*.vmdk image/$imageqc.qcow2

cp image/$imageqc.qcow2 /var/lib/libvirt/images/

## https://www.obriain.com/primers/ova2kvm.php
