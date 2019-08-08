#!/bin/bash
set -e

module_nom=${1:?Specify a module name}
module_ver=${2:?Specify a module version}
module_fed=${3:?Specify a Fedora version}

module="$module_nom-$module_ver-$module_fed"

echo "Finding latest tag for module: $module"
tag="$(koji list-tags | grep "${module}" | grep -v '\-build$' | sort | tail -n1)"
echo "Caching builds from tag: $tag"
if [ ! -d ".module-dep-cache/$module" ] ; then
	mkdir -p .module-dep-cache/$module
	pushd .module-dep-cache/$module 2>&1 >/dev/null
	pkgs=$(koji list-pkgs --quiet --tag=$tag | cut -f1 -d' ' | sort)
	for pkg in $pkgs ; do
		if [ "$pkg" = "module-build-macros" ] ; then
			continue
		fi
		koji download-build --arch=noarch --arch=x86_64 --latestfrom=$tag $pkg
	done
	popd 2>&1 >/dev/null
	# Create yum repo
	createrepo_c .module-dep-cache/$module
	# Augment repo with module data
	tstamp=$(echo $tag | rev | cut -f1,2 -d- | rev | sed -e 's/-/./')
	stream=${module_ver/-/_}
	wget -O .module-dep-cache/modulemd.x86_64.yaml https://kojipkgs.fedoraproject.org//packages/$module_nom/$stream/$tstamp/files/module/modulemd.x86_64.txt
	modifyrepo_c --mdtype=modules .module-dep-cache/modulemd.x86_64.yaml .module-dep-cache/$module/repodata
	rm .module-dep-cache/modulemd.x86_64.yaml
fi
cat <<EOF > .module-dep-cache/$module.repo
[$module]
name=$module
baseurl=file://$(pwd)/.module-dep-cache/$module
enabled=1
sslverify=0
gpgcheck=0
priority=5
EOF
echo "Done caching builds from tag: $tag"
