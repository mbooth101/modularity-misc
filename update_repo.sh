#!/bin/bash

function update_repo() {
	# Create yum repo
	local module=$1
	local repo="module-cache/$module"
	if [ ! -e "$repo/repodata/repomd.xml" ] ; then
		mkdir -p $repo
		createrepo_c $repo
	else
		createrepo_c --update $repo
	fi

	# Generate repo file
	mkdir -p module-cache/conf
	cat <<-EOF > module-cache/conf/$module.repo
	[$module]
	name=$module
	baseurl=file://$(pwd)/$repo
	enabled=1
	sslverify=0
	gpgcheck=0
	priority=5
	module_hotfixes=1
	EOF
}

update_repo $1
