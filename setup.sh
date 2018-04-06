#!/bin/bash

# === Parameters decided by this script. ===
# Directory where the NFS partition will be mounted on NFS clients
SHARED_HOME=/shome

# === Convenience variables ===
USERS="root `ls /users`"

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

# Change user login shell to Bash
for user in $USERS; do
    chsh -s `which bash` $user
done

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
  echo "$SHARED_HOME *(rw,sync,no_root_squash)" >> /etc/exports

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

  # TODO: Only add to fstab once
  echo "$rcnfs_ip:$SHARED_HOME $SHARED_HOME nfs4 rw,sync,hard,intr,addr=`hostname -i` 0 0" >> /etc/fstab

fi

