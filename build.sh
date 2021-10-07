#!/bin/bash

set -e

docker build -t docker2qcow2 -f Dockerfile

docker run docker2qcow2 bash -c 'sleep 86400' &
sleep 1
cid=$(docker ps --noheading 2>/dev/null | sed -ne '/docker2qcow2/s/  *.*//p')

if [ -z "$cid" ]; then
    echo "Couldn't find running docker container"
    exit 1
fi

rm -f disk.img
size=1024
dd if=/dev/zero of=disk.img bs=1M count=$size seek=$((size-1))

sfdisk disk.img < partitions.txt

mkdir -p /tmp/disk.d
trap 'sudo bash -xc "docker kill $cid; sync; sync; for f in boot \"\"; do umount /tmp/disk.d/\$f; done; kpartx -d disk.img; losetup -a"' EXIT
sudo bash -ex <<EOF
kpartx -a disk.img
mkfs /dev/mapper/loop0p1
mkfs /dev/mapper/loop0p2
mount /dev/mapper/loop0p2 /tmp/disk.d
mkdir /tmp/disk.d/boot
mount /dev/mapper/loop0p1 /tmp/disk.d/boot
EOF
docker export $cid | sudo tar -C /tmp/disk.d -xf -
docker kill $cid
trap 'sudo bash -xc "sync; sync; grep disk.d /proc/mounts; for f in sys dev proc boot \"\"; do umount /tmp/disk.d/\$f; done; kpartx -d disk.img; losetup -a"' EXIT
sudo bash -ex <<EOF
for f in sys dev proc; do
    mount -o bind /\$f/ /tmp/disk.d/\$f
done
EOF
sudo chroot /tmp/disk.d <<EOF
set -ex
$LOCAL_REPOS
dnf -y install kernel-core grub2-pc grub2-tools kbd
cat <<fstabEOF > /etc/fstab
/dev/sda2      /                       ext4    defaults        1 1
/dev/sda1      /boot                   ext4    defaults        1 1
fstabEOF
grub2-install --target i386-pc --bootloader-id=grub /dev/loop0
grub2-mkconfig > /boot/grub2/grub.cfg
echo "root:root" | chpasswd
rm -f /etc/systemd/system/{getty.target,{systemd-remount-fs,console-getty}.service}
EOF

sync; sync

df -h | grep /tmp/disk.d

trap '' EXIT
sudo bash -x <<EOF
for f in sys dev proc boot ""; do
    umount /tmp/disk.d/\$f
done
kpartx -d disk.img
losetup -a
EOF

qemu-img convert -f raw -O qcow2 disk.img disk.qcow2
