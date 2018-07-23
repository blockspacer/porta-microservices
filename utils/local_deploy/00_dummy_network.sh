#!/bin/bash
set -e

echo << EOF > /etc/sysconfig/network-scripts/ifcfg-eth10
DEVICE=lo
IPADDR=10.1.0.1
NETMASK=255.255.255.0
NETWORK=10.1.0.0
# If you're having problems with gated making 127.0.0.0/8 a martian,
# you can change this to something else (255.255.255.255, for example)
BROADCAST=10.255.255.255
ONBOOT=yes
NAME=loopback-1
EOF

