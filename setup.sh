#!/bin/bash

# === Parameters decided by this script. ===
# Directory where the NFS partition will be mounted on NFS clients
SHARED_HOME=/shome

# === Convenience variables ===
KERNEL_RELEASE=`uname -r`
OS_VER="ubuntu`lsb_release -r | cut -d":" -f2 | xargs`"
MLNX_OFED="MLNX_OFED_LINUX-3.4-1.0.0.0-$OS_VER-x86_64"
USERS="root `ls /users`"
KERNEL_BOOT_PARAMS="default_hugepagesz=1G hugepagesz=1G hugepages=8"

# Test if startup has already run.
if [ -f /local/setup_done ]
then
    # Sometimes (e.g. after each experiment extension) the CloudLab management
    # software will replace our authorized_keys settings; restore our settings
    # automatically after reboot.
    for user in $USERS; do
        if [ "$user" = "root" ]; then
            ssh_dir=/root/.ssh
        else
            ssh_dir=/users/$user/.ssh
        fi

        if [ -f $ssh_dir/authorized_keys.old ]; then
            mv $ssh_dir/authorized_keys.old $ssh_dir/authorized_keys
        fi
    done

    # Since we are rebooting NFS server as well, we should make sure to start it up
    if [ $(hostname --short) == "rcnfs" ]
    then
      /etc/init.d/nfs-kernel-server start
    else
      # Mount NFS
      mount -a
    fi
    chmod 777 /dev/nvme0n1
    exit 0
fi

# === Software dependencies that need to be installed. ===
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
  echo "$SHARED_HOME *(rw,sync,no_root_squash)" >> /etc/exports

  # Start the NFS service.
  /etc/init.d/nfs-kernel-server start

  # Generate a list of machines in the cluster; because Yilong does and it
  # might be needed in the scripts run after
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
  # Update GRUB with our kernel boot parameters
  sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$KERNEL_BOOT_PARAMS /" /etc/default/grub
  update-grub

  # Wait until nfs is properly set up
  while [ "$(ssh rcnfs "[ -f /local/setup-nfs-done ] && echo 1 || echo 0")" != "1" ]; do
      sleep 1
  done

  # NFS clients setup: use the publicly-routable IP addresses for both the
  # server and the clients to avoid interference with the experiment.
  rcnfs_ip=`ssh rcnfs "hostname -i"`
  mkdir $SHARED_HOME; mount -t nfs4 $rcnfs_ip:$SHARED_HOME $SHARED_HOME
  echo "$rcnfs_ip:$SHARED_HOME $SHARED_HOME nfs4 rw,sync,hard,intr,addr=`hostname -i` 0 0" >> /etc/fstab

fi

# Download Mellanox OFED on all machines and install in parallel; avoiding waiting on RCNFS
pushd /local
echo -e "\n===== DOWNLOADING MELLANOX OFED ====="
axel -n 8 -q http://www.mellanox.com/downloads/ofed/MLNX_OFED-3.4-1.0.0.0/$MLNX_OFED.tgz
tar xzf $MLNX_OFED.tgz
# Install Melanox on all machines (must be done before reboot)
echo -e "\n===== INSTALLING MELLANOX OFED ====="
$MLNX_OFED/mlnxofedinstall --force --without-fw-update
popd

# Remove ulimit on all machines
cat >> /etc/security/limits.conf <<EOM
* soft memlock unlimited
* hard memlock unlimited
EOM

# Mark as completed
touch /local/setup_done

# Reboot to let the configuration take effects
reboot
