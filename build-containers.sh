#!/bin/sh

set -e

work_dir=`pwd`

echo "STATUS: Building docker containers"
echo "STATUS: Building rpc-proxy docker container"
cp -r $work_dir/certs build/go/bin/
cp $work_dir/src/rpc-proxy/Dockerfile build/go/bin/
cd build/go/bin/
docker build -t maxkondr/rpc-proxy .
cd $work_dir
echo "STATUS: Building rpc-proxy docker container - complete"

echo "STATUS: Building MS Account docker container"
cp -r $work_dir/certs build/src/account/
cp $work_dir/src/account/Dockerfile build/src/account/
cd build/src/account/
docker build -t maxkondr/service-account .
cd $work_dir
echo "STATUS: Building MS Account docker container - complete"

echo "STATUS: Building MS Customer docker container"
cp -r $work_dir/certs build/src/customer/
cp $work_dir/src/customer/Dockerfile build/src/customer/
cd build/src/customer/
docker build -t maxkondr/service-customer .
cd $work_dir
echo "STATUS: Building MS Customer docker container - complete"
