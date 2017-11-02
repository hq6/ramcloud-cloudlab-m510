#!/bin/bash

# General system software update
apt-get update

# Install common utilities
apt-get --assume-yes install mosh vim tmux pdsh tree axel

# NFS stuff
apt-get --assume-yes install nfs-kernel-server nfs-common

# Java stuff
apt-get --assume-yes install openjdk-7-jdk maven

# Collect rc server names and IPs in the cluster
while read -r ip linkin linkout hostname
do 
  if [[ $hostname =~ ^rc[0-9]+$ ]] 
  then
    rcnames=("${rcnames[@]}" "$hostname") 
    rcips=("${rcips[@]}" "$ip") 
  fi 
done < /etc/hosts

IFS=$'\n' rcnames=($(sort <<<"${rcnames[*]}"))
IFS=$'\n' rcips=($(sort <<<"${rcips[*]}"))
unset IFS

# Set some environment variables
cat > /etc/profile <<EOM

export JAVA_HOME=/usr/lib/jvm/java-1.7.0-openjdk-amd64
export EDITOR=vim
export RCIPS="${rcips[@]}"
export RCNAMES="${rcnames[@]}"
export HOSTNAMES="rcmaster rcnfs ${rcnames[@]}"
EOM

# Modify ssh config
cat > /etc/ssh/ssh_config <<EOM
    StrictHostKeyChecking no
EOM

# Copy root key 
for user in $(ls /users/)
do 
  cat ~/.ssh/authorized_keys >> /users/$user/.ssh/authorized_keys
  cp ~/.ssh/id_rsa /users/$user/.ssh/
  chown $user:ramcloud-PG0 /users/$user/.ssh/id_rsa
done
