#!/bin/bash

sudo apt-get update
sudo apt-get install --assume-yes \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg-agent \
        software-properties-common

BINDIR=$HOME/bin
mkdir -p $BINDIR
export PATH=$BINDIR:$PATH

wget https://downloads.mender.io/mender-cli/1.12.0/linux/mender-cli -O $BINDIR/mender-cli
chmod +x $BINDIR/mender-cli

wget https://downloads.mender.io/mender-artifact/3.11.2/linux/mender-artifact -O $BINDIR/mender-artifact
chmod +x $BINDIR/mender-artifact