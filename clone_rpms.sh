#!/bin/bash

script_location=$( (cd $(dirname $0) && pwd) )

module=$(ls *.yaml | cut -f1 -d.)

mkdir -p rpms
pushd rpms 2>&1 >/dev/null

rm -f need_branch
for pkg in $(grep -B1 --no-group-separator buildorder ../$module.yaml | grep -v buildorder | sed -e 's/:$//') ; do
	if [ ! -d "$pkg" ] ; then
		fedpkg clone $pkg
	fi
	(cd $pkg ; git pull ; if ! fedpkg switch-branch $module ; then echo $pkg >> ../need_branch ; fi)
done

popd 2>&1 >/dev/null
