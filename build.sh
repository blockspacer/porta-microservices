#!/bin/sh

set -e

work_dir=`pwd`

# uncrustify -c ./etc/uncrustify.cfg --no-backup $(find . -type f -name "*.cxx" -o -name "*.hxx" | xargs)
echo "STATUS: Building microservices"
mkdir build || true
cd build
rm -rf ./*
cmake $@ ..
make -j4
echo "STATUS: Building microservices - complete"
cd $work_dir

echo "STATUS: Building rpc-proxy"
./build-rpc-proxy.sh
echo "STATUS: Building rpc-proxy - complete"

echo "STATUS: Building containers"
./build-containers.sh
echo "STATUS: Building containers"
