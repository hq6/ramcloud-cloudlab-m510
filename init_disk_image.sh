#!/bin/bash

# This script should be run exactly once manually, and then disk image should
# be snapshoted.
################################################################################
# Step 1
# === Software dependencies that need to be installed. ===
KERNEL_RELEASE=`uname -r`
OS_VER="ubuntu`lsb_release -r | cut -d":" -f2 | xargs`"
MLNX_OFED="MLNX_OFED_LINUX-3.4-1.0.0.0-$OS_VER-x86_64"
# Common utilities
apt-get update
apt-get --assume-yes install mosh vim tmux pdsh tree axel ack-grep htop
# NFS
apt-get --assume-yes install nfs-kernel-server nfs-common
# cpupower, hugepages, msr-tools (for rdmsr), i7z
apt-get --assume-yes install linux-tools-common linux-tools-${KERNEL_RELEASE} \
        hugepages cpuset msr-tools i7z
# Dependencies to build the Linux perf tool
apt-get --assume-yes install systemtap-sdt-dev libunwind-dev libaudit-dev \
        libgtk2.0-dev libperl-dev binutils-dev liblzma-dev libiberty-dev
# Install RAMCloud dependencies
apt-get --assume-yes install build-essential git-core doxygen libpcre3-dev \
        protobuf-compiler libprotobuf-dev libcrypto++-dev libevent-dev \
        libboost-all-dev libgtest-dev libzookeeper-mt-dev zookeeper \
        libssl-dev default-jdk ccache

################################################################################
# Step 3
KERNEL_BOOT_PARAMS="default_hugepagesz=1G hugepagesz=1G hugepages=8"

# Update GRUB with our kernel boot parameters
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$KERNEL_BOOT_PARAMS /" /etc/default/grub
update-grub

# Remove ulimit on all machines
cat >> /etc/security/limits.conf <<EOM
* soft memlock unlimited
* hard memlock unlimited
EOM

################################################################################
# Step 3
# Download Mellanox OFED on all machines and install in parallel; avoiding waiting on RCNFS
pushd /local
echo -e "\n===== DOWNLOADING MELLANOX OFED ====="
axel -n 8 -q http://www.mellanox.com/downloads/ofed/MLNX_OFED-3.4-1.0.0.0/$MLNX_OFED.tgz
tar xzf $MLNX_OFED.tgz
# Install Melanox on all machines (must be done before reboot)
echo -e "\n===== INSTALLING MELLANOX OFED ====="
$MLNX_OFED/mlnxofedinstall --force --without-fw-update
popd

# Reboot to let the configuration take effect, but examine the state first.
# reboot
