#!/bin/bash
set -e

module_nom=${1:?Specify a module name}
module_str=${2:?Specify a module stream}
module_fed=${3:?Specify a Fedora/RHEL version}

if [ "$module_fed" -gt "20" ] ; then
	koji_cmd=koji
	koji_url=https://kojipkgs.fedoraproject.org//packages
else
	koji_cmd=brew
	koji_url=http://download.eng.bos.redhat.com/brewroot/packages
fi

module="$module_nom-$module_str-$module_fed"

echo "Finding latest tag for module: $module"
tag="$(${koji_cmd} list-tags module-${module}\* | grep "${module}" | grep -v '\-build$' | sort | tail -n1)"
if [ -z "$tag" ] ; then
	echo "No tag found"
	exit 1
fi
tag_prefix=module-$module_nom-$module_str-
module_ver=$(echo ${tag#$tag_prefix} | sed -e 's/-/./')

echo "Caching builds from tag: $tag"
if [ ! -f "module-cache/$module.cache" ] ; then
	mkdir -p module-cache/$module
	pushd module-cache/$module 2>&1 >/dev/null
	pkgs=$(${koji_cmd} list-pkgs --quiet --tag=$tag | cut -f1 -d' ' | sort)
	for pkg in $pkgs ; do
		if [ "$pkg" = "module-build-macros" ] ; then
			continue
		fi
		${koji_cmd} download-build --arch=noarch --arch=x86_64 --latestfrom=$tag $pkg
	done
	popd 2>&1 >/dev/null
	touch module-cache/$module.cache
fi

./update_repo.sh $module

echo "Done caching builds from tag: $tag"
