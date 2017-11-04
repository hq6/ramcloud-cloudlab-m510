CloudLab Profile for Running RAMCloud on m510 Machines
======================================================

CloudLab profile for running a RAMCloud cluster with a configurable number of
nodes on CloudLab Utah m510 machines. Setup scripts take care of downloading,
compiling, and configuring RAMCloud on an NFS filesystem mounted on all the
machines.

## Instructions for Use ##
* ssh into `rcmaster`
* `cd /shome/RAMCloud`
* Startup cluster with 4 master servers and a replication factor of 3 using the
  basic+udp transport:
  * `sudo ./scripts/cluster.py -s 4 -r 3 --transport=basic+udp --verbose`
* Running clusterperf:
  * `sudo ./scripts/clusterperf.py --transport=basic+udp --verbose -b 1`

## Details ##
* Cluster consists of:
```
rcmaster : Node from which clusters are started via RAMCloud/scripts/cluster.py
rcnfs : Node from which the NFS mount is served.
rcXX : Nodes on which the master, backup, coordinator, and clients are run.
```
* The `rcnfs` node exports an NFS shared filesystem mounted at `/shome` on
  `rcmaster` and all `rcXX` machines.
* Each of the `rcXX` machines have a 200GB partition mounted at
  `/local/rcbackup`, in which a file has been created `backup.log` to be used
  by backups for the recovery log. Starting up a cluster.
* For convenience, tmux is started automatically when logging into `rcmaster`.
