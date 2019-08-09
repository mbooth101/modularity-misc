#!/bin/bash

set -e

# Generate build order
./gen_build_order_graph.py ../tycho/tycho.yaml
source ./build_order_graph.sh

# Pass is a rank to build up to
BUILD_RANK=${1:-""}

MODULE=$(echo $MODULE | cut -d. -f1)
BUILD_SRC_DIR=rpms/source/$MODULE
BUILD_RESULT_DIR=rpms/results/$MODULE
mkdir -p $BUILD_SRC_DIR $BUILD_RESULT_DIR

# Fedora base platform version
PLATFORM=30

# Generate mock config
cat > rpms/mock-$PLATFORM.cfg <<EOF
config_opts['root'] = 'mock-$PLATFORM'
config_opts['target_arch'] = 'x86_64'
config_opts['legal_host_arches'] = ('x86_64',)
config_opts['chroot_setup_cmd'] = 'install @buildsys-build java-1.8.0-openjdk-devel'
config_opts['dist'] = 'fc$PLATFORM'  # only useful for --resultdir variable subst
config_opts['extra_chroot_dirs'] = [ '/run/lock', ]
config_opts['releasever'] = '$PLATFORM'
config_opts['package_manager'] = 'dnf'
config_opts['yum.conf'] = """
[main]
keepcache=1
debuglevel=2
reposdir=/dev/null
logfile=/var/log/yum.log
retries=20
obsoletes=1
gpgcheck=0
assumeyes=1
syslog_ident=mock
syslog_device=
install_weak_deps=0
metadata_expire=0
best=1
module_platform_id=platform:f$PLATFORM
reposdir=$(pwd)/.module-dep-cache,$(pwd)/rpms/results
[fedora]
name=fedora
metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-\$releasever&arch=\$basearch
enabled=1
priority=99
gpgcheck=0
skip_if_unavailable=False
"""
EOF

for RANK in $RANKS ; do
	CURRENT_RANK=$(echo -n $RANK | cut -f2 -d_)
	BUILT_RANK=0
	if [ -f "$BUILD_RESULT_DIR/rank" ] ; then
		BUILT_RANK="$(cat $BUILD_RESULT_DIR/rank)"
	fi
	if [ "$CURRENT_RANK" -le "$BUILT_RANK" ] ; then
		# Skip if rank is already built
		echo "Skipping Rank: $CURRENT_RANK"
	else
		# Build all packages in the rank
		echo "Building Rank: $CURRENT_RANK"
		for PKG in ${!RANK} ; do
			# Clone package
			if [ ! -d "$BUILD_SRC_DIR/$PKG" ] ; then
				pushd $BUILD_SRC_DIR 2>&1 >/dev/null
				fedpkg clone $PKG
				(cd $PKG && fedpkg switch-branch $MODULE)
				popd 2>&1 >/dev/null
			fi
			# Regenerate source RPM
			pushd $BUILD_SRC_DIR/$PKG 2>&1 >/dev/null
			rm -f *.src.rpm
			fedpkg --release=f$PLATFORM srpm
			SRPM=$(ls *.src.rpm)
			popd 2>&1 >/dev/null
			# Build
			if [ ! -f "$BUILD_RESULT_DIR/$SRPM" ] ; then
				mock -r rpms/mock-$PLATFORM.cfg --resultdir=$BUILD_RESULT_DIR --rebuild $BUILD_SRC_DIR/$PKG/$SRPM
			fi
		done
		# Update repo data to include newly built rank
		createrepo_c $BUILD_RESULT_DIR
		cat <<EOF > $(pwd)/$BUILD_RESULT_DIR.repo
[$MODULE]
name=$MODULE
baseurl=file://$(pwd)/$BUILD_RESULT_DIR
enabled=1
sslverify=0
gpgcheck=0
priority=1
EOF
		echo -n $CURRENT_RANK > $BUILD_RESULT_DIR/rank
	fi
	# Exit once the build rank is reached
	if [ -n "$BUILD_RANK" ] ; then
		if [ "$BUILD_RANK" = "$CURRENT_RANK" ] ; then
			break
		fi
	fi
done

