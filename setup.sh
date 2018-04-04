#!/bin/bash

# === Parameters decided by profile.py ===
# RCNFS partition that will be exported to clients by the NFS server (rcnfs).
NFS_EXPORT_DIR=$1
# RC server partition that will be used for RAMCloud backups.
RC_BACKUP_DIR=$2

# === Paarameters decided by this script. ===
# Directory where the NFS partition will be mounted on NFS clients
SHARED_DIR=/shome

# Other variables
KERNEL_RELEASE=`uname -r`

# Avoid reboot loop
if [ -f /local/setup_done ]
then
  # Post-restart configuration to do for rc machines.
  if [[ $(hostname --short) =~ ^rc[0-9][0-9]$ ]]
  then
    echo -e "\n===== MOUNT HUGEPAGES ====="
    # Mount hugepages, disable THP(Transparent Hugepages) daemon
    # I believe this must be done only after setting the hugepagesz kernel
    # parameter and rebooting.
    hugeadm --create-mounts --thp-never
  fi

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

# Mellanox OFED (Note: Reboot required after installing this).
apt-get --assume-yes install tk8.4 chrpath graphviz tcl8.4 libgfortran3 dkms \
tcl pkg-config gfortran curl libnl1 quilt dpatch swig tk python-libxml2

echo -e "\n===== INSTALLING MELLANOX OFED ====="
OS_VER="ubuntu`lsb_release -r | cut -d":" -f2 | xargs`"
MLNX_OFED="MLNX_OFED_LINUX-3.4-1.0.0.0-$OS_VER-x86_64"
axel -n 8 -q http://www.mellanox.com/downloads/ofed/MLNX_OFED-3.4-1.0.0.0/$MLNX_OFED.tgz
tar xzf $MLNX_OFED.tgz
./$MLNX_OFED/mlnxofedinstall --force --without-fw-update >> ./$MLNX_OFED/install.log

# Set some environment variables
cat >> /etc/profile <<EOM

export EDITOR=vim
EOM

# Disable user prompting for connecting to unseen hosts.
cat >> /etc/ssh/ssh_config <<EOM
    StrictHostKeyChecking no
EOM

# Setup password-less ssh between nodes
for user in $(ls /users/)
do
    ssh_dir=/users/$user/.ssh
    /usr/bin/geni-get key > $ssh_dir/id_rsa
    chmod 600 $ssh_dir/id_rsa
    chown $user: $ssh_dir/id_rsa
    ssh-keygen -y -f $ssh_dir/id_rsa > $ssh_dir/id_rsa.pub
    cat $ssh_dir/id_rsa.pub >> $ssh_dir/authorized_keys
    chmod 644 $ssh_dir/authorized_keys
done

# If this server is the RCNFS server, then NFS export the local partition and
# start the NFS server. Otherwise, wait for the RCNFS server to complete its
# setup and then mount the partition. 
if [ $(hostname --short) == "rcnfs" ]
then
  # Make the file system rwx by all.
  chmod 777 $NFS_EXPORT_DIR

  # Make the NFS exported file system readable and writeable by all hosts in the
  # system (/etc/exports is the access control list for NFS exported file
  # systems, see exports(5) for more information).
	echo "$NFS_EXPORT_DIR *(rw,sync,no_root_squash)" >> /etc/exports

  # Start the NFS service.
  /etc/init.d/nfs-kernel-server start

  # Give it a second to start-up
  sleep 2

  > /local/setup-nfs-done
else
  # Wait until nfs is properly set up
  while [ "$(ssh rcnfs "[ -f /local/setup-nfs-done ] && echo 1 || echo 0")" != "1" ]; do
      sleep 1
  done

	# NFS clients setup: use the publicly-routable IP addresses for both the
  # server and the clients to avoid interference with the experiment.
	rcnfs_ip=`ssh rcnfs "hostname -i"`
	mkdir $SHARED_DIR; mount -t nfs4 $rcnfs_ip:$NFS_EXPORT_DIR $SHARED_DIR
	echo "$rcnfs_ip:$NFS_EXPORT_DIR $SHARED_DIR nfs4 rw,sync,hard,intr,addr=`hostname -i` 0 0" >> /etc/fstab
fi

# Checkout and setup RAMCloud on rcmaster
if [ $(hostname --short) == "rcmaster" ]
then
  cd $SHARED_DIR
  git clone https://github.com/PlatformLab/RAMCloud.git
  cd RAMCloud
  git submodule update --init --recursive
  ln -s ../../hooks/pre-commit .git/hooks/pre-commit

   # Generate private makefile configuration
  mkdir private
  cat >>private/MakefragPrivateTop <<EOL
DEBUG := no
CCACHE := yes
LINKER := gold
DEBUG_OPT := yes
GLIBCXX_USE_CXX11_ABI := yes
DPDK := yes
DPDK_DIR := dpdk
DPDK_SHARED := no
EOL
## Make dpdk
MLNX_DPDK=y scripts/dpdkBuild.sh

  ## Make RAMCloud
  cd ../

  make -j8 DEBUG=no

	# Construct localconfig.py for this cluster setup.
	cd scripts/
	> localconfig.py


  # Set the backup file location
  echo "default_disks = '-f /local/rcbackup/backup.log'" >> localconfig.py
	# First, collect rc server names and IPs in the cluster.
	while read -r ip linkin linkout hostname
	do 
		if [[ $hostname =~ ^rc[0-9]+$ ]] 
		then
			rcnames=("${rcnames[@]}" "$hostname") 
		fi 
	done < /etc/hosts
  IFS=$'\n' rcnames=($(sort <<<"${rcnames[*]}"))
  unset IFS

	echo -n "hosts = [" >> localconfig.py
	for i in $(seq ${#rcnames[@]})
	do
    hostname=${rcnames[$(( i - 1 ))]}
    ipaddress=$(ssh $hostname 'hostname -i')
    tuplestr="(\"$hostname\", \"$ipaddress\", $i)"
		if [[ $i == ${#rcnames[@]} ]]
		then
			echo "$tuplestr]" >> localconfig.py
    else 
			echo -n "$tuplestr, " >> localconfig.py
		fi
	done

fi

# Create backup.log file on each of the rc servers
if [[ $(hostname --short) =~ ^rc[0-9][0-9]$ ]]
then

  # Make the rcbackup directories globally writeable.
  chmod 777 $RC_BACKUP_DIR
  touch $RC_BACKUP_DIR/backup.log
  chmod 777 $RC_BACKUP_DIR/backup.log
    cat >> /etc/security/limits.conf <<EOM
* soft memlock unlimited
* hard memlock unlimited
EOM

    echo -e "\n===== SET KERNEL BOOT PARAMETERS ====="
    # Enable hugepage support for DPDK:
    # http://dpdk.org/doc/guides/linux_gsg/sys_reqs.html
    # The changes will take effects after reboot. m510 is not a NUMA machine.
    # Reserve 1GB hugepages via kernel boot parameters
    kernel_boot_params="default_hugepagesz=1G hugepagesz=1G hugepages=8"

    # Update GRUB with our kernel boot parameters
    sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$kernel_boot_params /" /etc/default/grub
    update-grub

    # Note: We will reboot the rc machines at the end of this script so that the
    # kernel parameter changes can take effect.

    touch /local/setup_done

    echo -e "\n===== REBOOTING ====="
    reboot
fi
