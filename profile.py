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

# The possible set of node-types this cluster can be configured with. Currently 
# only m510 machines are supported.
hardware_types = [ ("m510", "m510 (CloudLab Utah, Intel Xeon-D)") ]

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
request.addResource(rclan)

# Setup node names so that existing RAMCloud scripts can be used on the
# cluster.
hostnames = ["rcmaster", "rcnfs"]
for i in range(params.num_rcnodes):
    hostnames.append("rc%02d" % (i + 1))

# Setup the cluster one node at a time.
for host in hostnames:
    node = RSpec.RawPC(host)
    node.hardware_type = params.hardware_type
    node.disk_image = "urn:publicid:IDN+utah.cloudlab.us+image+ramcloud-PG0:ramcloud-m510-dpdk-hugepage"

    if host == "rcnfs":
        # Ask for a 200GB file system mounted at /shome on rcnfs
        nfs_bs = node.Blockstore("bs", "/shome")
        nfs_bs.size = "200GB"

    node.addService(RSpec.Execute(shell="sh",
        command="sudo /local/repository/setup.sh"))

    request.addResource(node)

    # Add this node to the LAN.
    iface = node.addInterface("eth0")
    rclan.addInterface(iface)

# Generate the RSpec
pc.printRequestRSpec(request)
