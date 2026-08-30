tar -xvf image/$image.ova

vmdk-files=$(ls image/*vmdk | head -n 1)

vmdk_file=$(ls image/*.vmdk | head -n 1)

image-qcow=$(baseline image/$image.ova ova)

qemu-img convert -f vmdk -O qcow2 "image/$image.vmdk" "image/$image-qcow.qcow2"

sudo cp "image/$image.qcow2" /var/lib/libvirt/images/

## https://www.obriain.com/primers/ova2kvm.php
