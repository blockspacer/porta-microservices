#!/bin/sh

set -e

run()
{
	for I in $1
	do
		cmd=`which $I`
		if test -n "$cmd"
		then
			break;
		fi
	done
}

uncrustify -c ./etc/uncrustify.cfg --no-backup $(find . -type f -name "*.cxx" -o -name "*.hxx" | xargs)
echo "STATUS: Building microservices"
mkdir build || true
cd build
rm -rf ./*
cmake $@ ..
make -j4
echo "STATUS: Building microservices - complete"
cd ..
echo "STATUS: Building rpc-proxy"
./build-rpc-proxy.sh
echo "STATUS: Building rpc-proxy - complete"
