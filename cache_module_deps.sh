#!/bin/bash
set -e

module_nom=${1:?Specify a module name}
module_ver=${2:?Specify a module version}
module_fed=${3:?Specify a Fedora version}

module="$module_nom-$module_ver-$module_fed"

echo "Finding latest tag for module: $module"
tag="$(koji list-tags | grep "${module}" | grep -v '\-build$' | sort | tail -n1)"
echo "Caching builds from tag: $tag"
if [ ! -f "module-dep-cache/$module.cache" ] ; then
	mkdir -p module-dep-cache/$module
	pushd module-dep-cache/$module 2>&1 >/dev/null
	pkgs=$(koji list-pkgs --quiet --tag=$tag | cut -f1 -d' ' | sort)
	for pkg in $pkgs ; do
		if [ "$pkg" = "module-build-macros" ] ; then
			continue
		fi
		koji download-build --arch=noarch --arch=x86_64 --latestfrom=$tag $pkg
	done
	popd 2>&1 >/dev/null
	touch module-dep-cache/$module.cache
fi

# Create yum repo
rm -rf module-dep-cache/repo/repodata
mkdir -p module-dep-cache/repo
cp -pr module-dep-cache/$module/* module-dep-cache/repo
createrepo_c module-dep-cache/repo

# Generate repo file
cat <<EOF > module-dep-cache/module-cache.repo
[module-cache]
name=module-cache
baseurl=file://$(pwd)/module-dep-cache/repo
enabled=1
sslverify=0
gpgcheck=0
priority=5
EOF
echo "Done caching builds from tag: $tag"
