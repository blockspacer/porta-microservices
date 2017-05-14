#!/bin/sh

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
mkdir build || true
cd build
rm -rf ./*
cmake $@ ..
make -j4
