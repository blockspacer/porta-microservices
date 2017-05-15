#!/usr/bin/bash

set -e
GOPATH=`pwd`/build/go
echo "STATUS: Creating temporary GOPATH=$GOPATH"
mkdir -p $GOPATH
mkdir -p $GOPATH/bin
GOPATH=$GOPATH
GOBIN=$GOPATH/bin
export GOPATH
export GOBIN
export PATH=$PATH:$GOBIN

work_dir=`pwd`
echo "STATUS: Installing Go dependencies"
go get -d github.com/grpc-ecosystem/grpc-gateway/...
cd $GOPATH/src/github.com/grpc-ecosystem/grpc-gateway
if [ "`git show-ref refs/heads/fork-master`" == "" ]; then
    git remote add fork https://github.com/maxkondr/grpc-gateway.git
    git fetch fork
    git checkout -b fork-master fork/master
fi

go get -u github.com/grpc-ecosystem/grpc-gateway/protoc-gen-grpc-gateway
go get -u github.com/golang/protobuf/protoc-gen-go
go get -u google.golang.org/grpc
echo "STATUS: Installing Go dependencies - complete"
cd $work_dir

proto_path=`pwd`/proto
cd $proto_path
proto_files=$(find . -name '*.proto' | ls | awk -F. '{print $1}' | xargs)
cd $work_dir
src_proxy_dir=`pwd`/src/rpc-proxy
google_api_path=`pwd`/googleapi/googleapis
dst_stub_dir=$GOPATH/src/ba-microservices/rpc-stubs
dst_proxy_dir=$GOPATH/src/ba-microservices/rpc-proxy
protoc=$(which protoc)
include_dirs="-I/usr/local/include \
-I. \
-I$GOPATH/src
-I$google_api_path"

mkdir -p $dst_proxy_dir || true

rm -f $GOPATH/bin/rpc-proxy || true

for pr in $proto_files
do
    stub_dir="$dst_stub_dir/$pr"
    mkdir -p $stub_dir || true
    echo "STATUS: Generating Go stubs for $pr"
    $protoc $include_dirs --go_out=plugins=grpc:$stub_dir --proto_path=$proto_path "$proto_path/$pr.proto"
    echo "STATUS: Generating Go stubs for $pr - complete"

    echo "STATUS: Generating Go gRPC stubs for $pr"
    $protoc $include_dirs --grpc-gateway_out=request_context=true:$stub_dir --proto_path=$proto_path "$proto_path/$pr.proto"
    echo "STATUS: Generating Go gRPC stubs for $pr - complete"

    cd $stub_dir
    go get .
done;

echo "STATUS: Generating reverse proxy"
cp -R $src_proxy_dir/* $dst_proxy_dir
cd $dst_proxy_dir
go get .
echo "STATUS: Generating reverse proxy - complete"
