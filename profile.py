"""
Allocate a cluster of CloudLab machines for RAMCloud, specifically on CloudLab 
Utah m510 machines.

Instructions:
All machines will share an nfs filesystem mounted at /shome. This filesystem
is exported by a special node called `rcnfs'.

The RAMCloud repository is automatically cloned to /shome/RAMCloud, compiled,
and setup with a scripts/localconfig.py customized for the instantiated
experiment. 
"""

import re

import geni.aggregate.cloudlab as cloudlab
import geni.portal as portal
import geni.rspec.pg as RSpec
import geni.urn as urn

# Allows for general parameters like disk image to be passed in. Useful for
# setting up the cloudlab dashboard for this profile.
pc = portal.Context()

# The possible set of base disk-images that this cluster can be booted with.
# The second field of every tupule is what is displayed on the cloudlab
# dashboard.
images = [ ("UBUNTU14-64-STD", "Ubuntu 14.04"),
           ("UBUNTU16-64-STD", "Ubuntu 16.04") ]

# The possible set of node-types this cluster can be configured with. Currently 
# only m510 machines are supported.
hardware_types = [ ("m510", "m510 (CloudLab Utah, Intel Xeon-D)") ]

# Default the disk image to 64-bit Ubuntu 15.04
pc.defineParameter("image", "Disk Image",
        portal.ParameterType.IMAGE, images[1], images,
        "Specify the base disk image that all the nodes of the cluster " +\
        "should be booted with.")

pc.defineParameter("hardware_type", "Hardware Type",
                   portal.ParameterType.NODETYPE,
                   hardware_types[0], hardware_types)

# Default the cluster size to 5 nodes (minimum requires to support a 
# replication factor of 3 and an independent coordinator). 
pc.defineParameter("num_rcnodes", "Cluster Size",
        portal.ParameterType.INTEGER, 5, [],
        "Specify the number of RAMCloud servers. For a replication factor " +\
        "of 3 and without machine sharing enabled, the minimum number of " +\
        "RAMCloud servers is 5 (1 master " +\
        "+ 3 backups + 1 coordinator). Note that the total " +\
        "number of servers in the experiment will be this number + 2 (one " +\
        "additional server for rcmaster, and one for rcnfs). To check " +\
        "availability of nodes, visit " +\
        "\"https://www.cloudlab.us/cluster-graphs.php\"")

params = pc.bindParameters()

# Create a Request object to start building the RSpec.
request = RSpec.Request()

# Create a local area network.
rclan = RSpec.LAN()
rclan.best_effort = True

# It's not clear what these options do but they sound like they will make
# performance less predictable if true; need to ask jde.
rclan.vlan_tagging = False
rclan.link_multiplexing = False

request.addResource(rclan)

# Setup node names so that existing RAMCloud scripts can be used on the
# cluster.
rcxx_backup_dir = "/local/rcbackup"
hostnames = ["rcmaster", "rcnfs"]
for i in range(params.num_rcnodes):
    hostnames.append("rc%02d" % (i + 1))

# Setup the cluster one node at a time.
for host in hostnames:
    node = RSpec.RawPC(host)
    node.hardware_type = params.hardware_type
    node.disk_image = urn.Image(cloudlab.Utah, "emulab-ops:%s" % params.image)

    if host == "rcnfs":
        # Ask for a 200GB file system mounted at /shome on rcnfs
        nfs_bs = node.Blockstore("bs", "/shome")
        nfs_bs.size = "200GB"

    # Create a backup partition for RCXX.
    pattern = re.compile("^rc[0-9][0-9]$")
    if pattern.match(host):
        # Ask for a 200GB file system for RAMCloud backups
        backup_bs = node.Blockstore(host + "backup_bs", rcxx_backup_dir)
        backup_bs.size = "200GB"

    node.addService(RSpec.Execute(shell="sh",
        command="sudo /local/repository/setup.sh"))

    request.addResource(node)

    # Add this node to the LAN.
    iface = node.addInterface("eth0")
    rclan.addInterface(iface)

# Generate the RSpec
pc.printRequestRSpec(request)
