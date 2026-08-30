tar -xvf image/$image.ova > disk-output.txt

awk 'NR==2' disk-output.txt > vmdk.txt

export vmdk=vmdk.txt


qemu-img convert -O qcow2 image/ubuntu-$vmdk.vmdk image/$image.qcow2

cp image/$image.qcow2 /var/lib/libvirt/images/

## https://www.obriain.com/primers/ova2kvm.php
