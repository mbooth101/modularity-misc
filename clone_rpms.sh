#!/bin/bash

script_location=$( (cd $(dirname $0) && pwd) )

module=$(ls *.yaml | cut -f1 -d.)

mkdir -p rpms
pushd rpms 2>&1 >/dev/null
current_pkg=
for pkg in $(grep -B1 -A1 --no-group-separator buildorder ../$module.yaml | grep -v buildorder | sed -e 's/:$//' -e 's/ //g') ; do
	if [[ $pkg = ref:* ]] ; then
		ref=${pkg#ref:}
		(cd $current_pkg && fedpkg switch-branch $ref)
	else
		current_pkg=$pkg
		if [ ! -d "$pkg" ] ; then
			fedpkg clone $pkg
		fi
	fi
done

popd 2>&1 >/dev/null
