#!/bin/bash
set -e

# Call like this:
# ./mock_build.sh <module_name> <rank>

# Generate build order
./gen_build_order_graph.py ../$1/$1.yaml
source ./build_order_graph.sh

# Pass in a rank to build up to
BUILD_RANK=${2:-""}

# Pass in a list of packages to override the definition of the given rank
BUILD_RANK_OVERRIDE=${3:-""}

# Fedora base platform version
PLATFORM=32

MODULE=$MODULE_NAME-$MODULE_STREAM-$PLATFORM

MOCKBUILD_DIR=module-mockbuild
DISTGIT_DIR=rpms
BUILD_SRC_DIR=$DISTGIT_DIR/$MODULE
BUILD_RESULT_DIR=$MOCKBUILD_DIR/$MODULE
MOCK_CONFIG=$MOCKBUILD_DIR/$MODULE-mock.cfg

mkdir -p $BUILD_SRC_DIR $BUILD_RESULT_DIR $MOCKBUILD_DIR/conf
mv $MODULE_NAME-$MODULE_STREAM.yaml $MOCKBUILD_DIR/$MODULE.yaml

# Generate mock config
cat > $MOCK_CONFIG.new <<EOF
config_opts['root'] = 'mock-$PLATFORM'
config_opts['module_enable'] = $BUILD_REQS
config_opts['target_arch'] = 'x86_64'
config_opts['legal_host_arches'] = ('x86_64',)
config_opts['chroot_setup_cmd'] = 'install @buildsys-build java-1.8.0-openjdk-devel'
config_opts['dist'] = 'fc$PLATFORM'  # only useful for --resultdir variable subst
config_opts['extra_chroot_dirs'] = [ '/run/lock', ]
config_opts['releasever'] = '$PLATFORM'
config_opts['package_manager'] = 'dnf'
config_opts['dnf.conf'] = """
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
reposdir=$(pwd)/module-cache/conf,$(pwd)/$MOCKBUILD_DIR/conf
[fedora]
name=fedora
metalink=https://mirrors.fedoraproject.org/metalink?repo=fedora-\$releasever&arch=\$basearch
enabled=1
priority=99
cost=2000
gpgcheck=0
skip_if_unavailable=False
[updates]
name=updates
metalink=https://mirrors.fedoraproject.org/metalink?repo=updates-released-f\$releasever&arch=\$basearch
enabled=1
priority=99
cost=2000
gpgcheck=0
skip_if_unavailable=False
"""
EOF

# Only replace mock config if it changed (speeds up mock root initialisation)
if [ -f "$MOCK_CONFIG" ] ; then
	if [ "$(md5sum $MOCK_CONFIG.new | cut -f1 -d' ')" = "$(md5sum $MOCK_CONFIG | cut -f1 -d' ')" ] ; then
		rm $MOCK_CONFIG.new
	else
		mv $MOCK_CONFIG.new $MOCK_CONFIG
	fi
else
	mv $MOCK_CONFIG.new $MOCK_CONFIG
fi

function build_srpm() {
	# Build if not already built
	rm -f $BUILD_SRC_DIR/$1/*.src.rpm
	mock -r $MOCK_CONFIG --init
	if [ -n "$2" ] ; then
		mock -r $MOCK_CONFIG --pm-cmd module enable $MODULE_NAME
		mock -r $MOCK_CONFIG --install $2
	fi
	mock -r $MOCK_CONFIG --no-clean --no-cleanup-after --resultdir=$BUILD_SRC_DIR/$1 --buildsrpm --spec $BUILD_SRC_DIR/$1/*.spec --sources $BUILD_SRC_DIR/$1
	SRPM="$(cd $BUILD_SRC_DIR/$1 && ls *.src.rpm)"
	if [ ! -f "$BUILD_RESULT_DIR/$SRPM" ] ; then
		mock -r $MOCK_CONFIG --no-clean --resultdir=$BUILD_RESULT_DIR --rebuild $BUILD_SRC_DIR/$1/$SRPM
	fi
}

function update_repo() {
	# Regenerate repository data to include newly built artifacts
	createrepo_c $BUILD_RESULT_DIR
	./fettle_yaml.py $BUILD_RESULT_DIR.yaml $BUILD_RESULT_DIR $BUILD_RESULT_DIR-modulemd.txt
	modifyrepo_c --mdtype=modules $BUILD_RESULT_DIR-modulemd.txt $BUILD_RESULT_DIR/repodata
	if [ ! -f "$MOCKBUILD_DIR/conf/$MODULE.repo" ] ; then
		cat <<EOF > $MOCKBUILD_DIR/conf/$MODULE.repo
[$MODULE]
name=$MODULE
baseurl=file://$(pwd)/$BUILD_RESULT_DIR
enabled=1
sslverify=0
gpgcheck=0
priority=1
EOF
	fi
}

# Build macro package
if [ ! -f "$BUILD_RESULT_DIR/module-build-macros-0.1-1.module_f$PLATFORM.noarch.rpm" ] ; then
	DATE="$(date -u +%Y%m%d%H%M%S)"
	mkdir -p $BUILD_SRC_DIR/module-build-macros
	sed -e "s/@@PLATFORM@@/$PLATFORM/g" -e "s/@@DATE@@/$DATE/" -e "s/@@MODULE@@/$MODULE/" -e "s/@@MODULE_STREAM@@/$MODULE_STREAM/" \
		module-build-macros.spec.template > $BUILD_SRC_DIR/module-build-macros/module-build-macros.spec
	sed -e "s/@@PLATFORM@@/$PLATFORM/g" -e "s/@@DATE@@/$DATE/" -e "s/@@MODULE@@/$MODULE/" -e "s/@@MODULE_STREAM@@/$MODULE_STREAM/" \
		macros.modules.template > $BUILD_SRC_DIR/module-build-macros/macros.modules
	echo "$BUILD_OPTS" >> $BUILD_SRC_DIR/module-build-macros/macros.modules
	build_srpm module-build-macros
	update_repo
fi

for RANK in $RANKS ; do
	CURRENT_RANK=$(echo -n $RANK | cut -f2 -d_)
	BUILT_RANK=0
	if [ -f "$BUILD_RESULT_DIR.rank" ] ; then
		BUILT_RANK="$(cat $BUILD_RESULT_DIR.rank)"
	fi
	if [ "$CURRENT_RANK" -le "$BUILT_RANK" ] ; then
		# Skip if rank is already built
		echo "Skipping Rank: $CURRENT_RANK"
	else
		# Build all packages in the rank
		RANK_TO_BUILD="${!RANK}"
		if [ "$BUILD_RANK" = "$CURRENT_RANK" ] ; then
			if [ -n "$BUILD_RANK_OVERRIDE" ] ; then
				RANK_TO_BUILD="$BUILD_RANK_OVERRIDE"
			fi
		fi
		echo "Building Rank: $CURRENT_RANK (${RANK_TO_BUILD})"
		for PKG in ${RANK_TO_BUILD} ; do
			# Clone package
			if [ ! -d "$BUILD_SRC_DIR/$PKG" ] ; then
				pushd $BUILD_SRC_DIR 2>&1 >/dev/null
				fedpkg clone $PKG
				(cd $PKG && fedpkg switch-branch $MODULE_NAME && fedpkg --release=f$PLATFORM sources)
				popd 2>&1 >/dev/null
			fi
			build_srpm $PKG module-build-macros
		done
		update_repo
		# Note which rank we finished if not overridden
		if [ -z "$BUILD_RANK_OVERRIDE" ] ; then
			echo -n $CURRENT_RANK > $BUILD_RESULT_DIR.rank
		fi
	fi
	# Exit once the build rank is reached
	if [ -n "$BUILD_RANK" ] ; then
		if [ "$BUILD_RANK" = "$CURRENT_RANK" ] ; then
			break
		fi
	fi
done

