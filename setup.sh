#!/bin/bash

# === Parameters decided by this script. ===
# Directory where the NFS partition will be mounted on NFS clients
SHARED_HOME=/shome

# === Convenience variables ===
USERS="root `ls /users`"

################################################################################
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
# Remove ulimit on all machines
cat >> /etc/security/limits.conf <<EOM
* soft memlock unlimited
* hard memlock unlimited
EOM

################################################################################
# Setup password-less ssh between nodes
for user in $USERS;
do
    if [ "$user" = "root" ]; then
        ssh_dir=/root/.ssh
    else
        ssh_dir=/users/$user/.ssh
    fi
    /usr/bin/geni-get key > $ssh_dir/id_rsa
    chmod 600 $ssh_dir/id_rsa
    chown $user: $ssh_dir/id_rsa
    ssh-keygen -y -f $ssh_dir/id_rsa > $ssh_dir/id_rsa.pub
    cat $ssh_dir/id_rsa.pub >> $ssh_dir/authorized_keys
    chmod 644 $ssh_dir/authorized_keys
    cat >>$ssh_dir/config <<EOL
    Host *
         StrictHostKeyChecking no
EOL
    chmod 644 $ssh_dir/config
done

################################################################################
# Misc settings.
# Change user login shell to Bash
for user in $USERS; do
    chsh -s `which bash` $user
done

# Update permissions on backup drive
chmod 777 /local/rcbackup

# Set CPU scaling governor to "performance"
cpupower frequency-set -g performance

################################################################################
# Setup NFS
# If this server is the RCNFS server, then NFS export the local partition and
# start the NFS server. Otherwise, wait for the RCNFS server to complete its
# setup and then mount the partition. 
if [ $(hostname --short) == "rcnfs" ]
then
  # Make the file system rwx by all.
  chmod 777 $SHARED_HOME

  # Make the NFS exported file system readable and writeable by all hosts in the
  # system (/etc/exports is the access control list for NFS exported file
  # systems, see exports(5) for more information).
  if [[ -z "$(grep no_root_squash /etc/exports)" ]]; then
      echo "$SHARED_HOME *(rw,sync,no_root_squash)" >> /etc/exports
  fi

  # Avoid the need for a reboot.
  exportfs -a

  # Start the NFS service.
  /etc/init.d/nfs-kernel-server start

  # Generate a list of machines in the cluster
  pushd $SHARED_HOME
  > rc-hosts.txt
  let num_rcxx=$(geni-get manifest | grep -o "<node " | wc -l)-2
  for i in $(seq "$num_rcxx")
  do
      printf "rc%02d\n" $i >> rc-hosts.txt
  done
  printf "rcmaster\n" >> rc-hosts.txt
  printf "rcnfs\n" >> rc-hosts.txt
  popd

  > /local/setup-nfs-done
else
  # Wait until nfs is properly set up
  while [ "$(ssh rcnfs "[ -f /local/setup-nfs-done ] && echo 1 || echo 0")" != "1" ]; do
      sleep 1
  done

  # NFS clients setup: use the publicly-routable IP addresses for both the
  # server and the clients to avoid interference with the experiment.
  rcnfs_ip=`ssh rcnfs "hostname -i"`
  mkdir -p $SHARED_HOME; mount -t nfs4 $rcnfs_ip:$SHARED_HOME $SHARED_HOME

  # Only update fstab if it does not already include NFS.
  if [[ -z "$(grep nfs4 /etc/fstab)" ]]; then
      echo "$rcnfs_ip:$SHARED_HOME $SHARED_HOME nfs4 rw,sync,hard,intr,addr=`hostname -i` 0 0" >> /etc/fstab
  fi
fi
