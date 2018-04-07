#!/bin/bash

# This script should be run exactly once manually, and then disk image should
# be snapshoted.
################################################################################
# Step 1
# === Software dependencies that need to be installed. ===
KERNEL_RELEASE=`uname -r`
# Common utilities
apt-get update
apt-get --assume-yes install mosh vim tmux pdsh tree axel ack-grep htop
# NFS
apt-get --assume-yes install nfs-kernel-server nfs-common
# cpupower, msr-tools (for rdmsr), i7z
apt-get --assume-yes install linux-tools-common linux-tools-${KERNEL_RELEASE} \
        cpuset msr-tools i7z
# Dependencies to build the Linux perf tool
apt-get --assume-yes install systemtap-sdt-dev libunwind-dev libaudit-dev \
        libgtk2.0-dev libperl-dev binutils-dev liblzma-dev libiberty-dev
# Install RAMCloud dependencies
apt-get --assume-yes install build-essential git-core doxygen libpcre3-dev \
        protobuf-compiler libprotobuf-dev libcrypto++-dev libevent-dev \
        libboost-all-dev libgtest-dev libzookeeper-mt-dev zookeeper \
        libssl-dev default-jdk ccache

################################################################################
# Step 2
# Remove ulimit on all machines
cat >> /etc/security/limits.conf <<EOM
* soft memlock unlimited
* hard memlock unlimited
EOM
################################################################################
