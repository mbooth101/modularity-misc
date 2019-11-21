#!/bin/bash
set -e

module_nom=${1:?Specify a module name}
module_str=${2:?Specify a module stream}
module_fed=${3:?Specify a Fedora version}

module="$module_nom-$module_str-$module_fed"

echo "Finding latest tag for module: $module"
tag="$(koji list-tags | grep "${module}" | grep -v '\-build$' | sort | tail -n1)"
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
	pkgs=$(koji list-pkgs --quiet --tag=$tag | cut -f1 -d' ' | sort)
	for pkg in $pkgs ; do
		if [ "$pkg" = "module-build-macros" ] ; then
			continue
		fi
		koji download-build --arch=noarch --arch=x86_64 --latestfrom=$tag $pkg
	done
	popd 2>&1 >/dev/null
	touch module-cache/$module.cache
fi

# Create yum repo
createrepo_c module-cache/$module
wget https://kojipkgs.fedoraproject.org//packages/$module_nom/$module_str/$module_ver/files/module/modulemd.x86_64.txt -O module-cache/$module-modulemd.txt
modifyrepo_c --mdtype=modules module-cache/$module-modulemd.txt module-cache/$module/repodata

# Generate repo file
mkdir -p module-cache/conf
cat <<EOF > module-cache/conf/$module.repo
[$module]
name=$module
baseurl=file://$(pwd)/module-cache/$module
enabled=1
sslverify=0
gpgcheck=0
priority=5
EOF
echo "Done caching builds from tag: $tag"
