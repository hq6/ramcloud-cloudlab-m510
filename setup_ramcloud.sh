#!/bin/bash

# This script clones RAMCloud and sets up DPDK.

SHARED_HOME=/shome

#Clone RAMCloud
cd $SHARED_HOME
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

# Construct localconfig.py for this cluster setup.
let num_rcxx=$(geni-get manifest | grep -o "<node " | wc -l)-2
/local/repository/localconfigGen.py $num_rcxx > scripts/localconfig.py


## Make dpdk
MLNX_DPDK=y scripts/dpdkBuild.sh
