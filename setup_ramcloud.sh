#!/bin/bash

# This script clones RAMCloud and sets up localconfig.py

SHARED_HOME=/shome

#Clone RAMCloud
cd $SHARED_HOME
git clone https://github.com/PlatformLab/RAMCloud.git
cd RAMCloud
git submodule update --init --recursive
ln -s ../../hooks/pre-commit .git/hooks/pre-commit

# Construct localconfig.py for this cluster setup.
let num_rcxx=$(geni-get manifest | grep -o "<node " | wc -l)-2
/local/repository/localconfigGen.py $num_rcxx > scripts/localconfig.py
