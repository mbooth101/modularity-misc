#!/bin/bash

# Call like this:
# ./mock_build.sh <module_name> [<rank>] [<rank_pkgs_override>]

# Generate build order
./gen_build_order_graph.py ../$1/$1.yaml
source ./build_order_graph.sh

# Pass in a rank to build up to
BUILD_RANK=${2:-""}

# Pass in a list of packages to override the definition of the given rank
BUILD_RANK_OVERRIDE=${3:-""}

BUILDERS=${4:-4}

# Fedora base platform version
PLATFORM=31

MODULE=$MODULE_NAME-$MODULE_STREAM-$PLATFORM

MOCKBUILD_DIR=module-mockbuild
DISTGIT_DIR=rpms
BUILD_SRC_DIR=$DISTGIT_DIR/$MODULE
BUILD_RESULT_DIR=$MOCKBUILD_DIR/$MODULE

mkdir -p $BUILD_SRC_DIR $BUILD_RESULT_DIR $MOCKBUILD_DIR/conf
mv $MODULE_NAME-$MODULE_STREAM.yaml $MOCKBUILD_DIR/$MODULE.yaml

function build_srpm() {
	local MOCK_CONFIG=$MOCKBUILD_DIR/$MODULE-mock-$1.cfg

	# Generate new mock config file
	cat > $MOCK_CONFIG.new <<EOF
config_opts['root'] = 'mock-$PLATFORM-$1'
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

	# Build in mock
	set -e
	rm -f $BUILD_SRC_DIR/$2/*.rpm
	mock -r $MOCK_CONFIG --init
	if [ -n "$3" ] ; then
		mock -r $MOCK_CONFIG --pm-cmd module enable $MODULE_NAME
		mock -r $MOCK_CONFIG --install $3
	fi
	mock -r $MOCK_CONFIG --no-clean --no-cleanup-after --resultdir=$BUILD_SRC_DIR/$2 --buildsrpm --spec $BUILD_SRC_DIR/$2/*.spec --sources $BUILD_SRC_DIR/$2
	SRPM="$(cd $BUILD_SRC_DIR/$2 && ls *.src.rpm)"
	mock -r $MOCK_CONFIG --no-clean --no-cleanup-after --resultdir=$BUILD_SRC_DIR/$2 --rebuild $BUILD_SRC_DIR/$2/$SRPM
	cp -pr $BUILD_SRC_DIR/$2/*.rpm $BUILD_RESULT_DIR
	set +e
}

FIFO=
FIFO_LOCK=

function __queue_worker() {
	local WORKER_ID=$1
	local START_LOG=$2
	local START_LOCK=$3

	# Open pipe for reading
	exec 3<$FIFO
	exec 4<$FIFO_LOCK

	# Signal that we have started
	exec 5<$START_LOCK
	flock 5
	echo $WORKER_ID >> $START_LOG
	flock -u 5
	exec 5<&-
	echo "Worker $WORKER_ID started"

	# Attempt to read a build job from the pipe until EOF is encountered
	while true ; do
		flock 4
		local PKG=
		read -su 3 PKG
		local READ_RESULT=$?
		flock -u 4

		if [[ $READ_RESULT -eq 0 ]] ; then
			# Run the build job in a subshell to avoid killing the
			# worker process by accident
			echo "Worker $WORKER_ID building $PKG"
			if [ "$PKG" = "module-build-macros" ] ; then
				( build_srpm $WORKER_ID $PKG )
			else
				( build_srpm $WORKER_ID $PKG module-build-macros )
			fi
			local BUILD_RESULT=$?
			echo "Worker $WORKER_ID built $PKG with result $BUILD_RESULT"
		else
			break
		fi
	done

	# Clean up FDs
	exec 3<&-
	exec 4<&-

	echo "Worker $WORKER_ID exited"
}

function __queue_cleanup() {
	exec 10<&-
	rm $FIFO $FIFO_LOCK
}

function queue_close() {
	trap '' 0
	__queue_cleanup
	wait
}

function queue_open() {
	local NUM_WORKERS=$1

	# Create pipe and lock file in temporary location
	FIFO=$(mktemp -t queue-fifo-XXXX)
	FIFO_LOCK=$(mktemp -t queue-lock-XXXX)
	rm $FIFO
	mkfifo $FIFO

	# Start worker processes
	local START_LOG=$(mktemp -t queue-worker-start-log-XXXX)
	local START_LOCK=$(mktemp -t queue-worker-start-lock-XXXX)
	for (( i=0; i<$NUM_WORKERS; i++ )) ; do
		__queue_worker $i $START_LOG $START_LOCK &
	done

	# Open pipe for writing
	exec 10>$FIFO

	# Clean up on exit
	trap __queue_cleanup 0

	# Wait for worker process to start
	exec 11<$START_LOCK
	while true ; do
		flock 11
		local NUM_STARTED=$(wc -l $START_LOG | cut -d' ' -f1)
		flock -u 11
		if [[ $NUM_STARTED -eq $NUM_WORKERS ]] ; then
			break
		fi
	done
	exec 11<&-
	rm $START_LOG $START_LOCK
}

function queue_build() {
	local PKG=$1
	echo "$PKG" 1>&10
}

# Generate macro package
if [ ! -d "$BUILD_SRC_DIR/module-build-macros" ] ; then
	DATE="$(date -u +%Y%m%d%H%M%S)"
	mkdir -p $BUILD_SRC_DIR/module-build-macros
	sed -e "s/@@PLATFORM@@/$PLATFORM/g" -e "s/@@DATE@@/$DATE/" -e "s/@@MODULE@@/$MODULE/" -e "s/@@MODULE_STREAM@@/$MODULE_STREAM/" \
		module-build-macros.spec.template > $BUILD_SRC_DIR/module-build-macros/module-build-macros.spec
	sed -e "s/@@PLATFORM@@/$PLATFORM/g" -e "s/@@DATE@@/$DATE/" -e "s/@@MODULE@@/$MODULE/" -e "s/@@MODULE_STREAM@@/$MODULE_STREAM/" \
		macros.modules.template > $BUILD_SRC_DIR/module-build-macros/macros.modules
	echo "$BUILD_OPTS" >> $BUILD_SRC_DIR/module-build-macros/macros.modules
fi

for RANK in $RANKS ; do
	CURRENT_RANK=$(echo -n $RANK | cut -f2 -d_)
	# Build all packages in the rank
	CURRENT_RANK_PKGS="${!RANK}"
	if [ "$BUILD_RANK" = "$CURRENT_RANK" ] ; then
		if [ -n "$BUILD_RANK_OVERRIDE" ] ; then
			CURRENT_RANK_PKGS="$BUILD_RANK_OVERRIDE"
		fi
	fi
	echo "Building Rank: $CURRENT_RANK (${CURRENT_RANK_PKGS})"
	if [ "$CURRENT_RANK" = "0" ] ; then
		queue_open 1
	else
		queue_open $BUILDERS
	fi
	for PKGREF in ${CURRENT_RANK_PKGS} ; do
		PKG=$(echo "$PKGREF" | cut -d@ -f1)
		REF=$(echo "$PKGREF" | cut -d@ -f2)
		do_build="true"
		# Clone package
		if [ ! -d "$BUILD_SRC_DIR/$PKG" ] ; then
			# Not previously cloned
			pushd $BUILD_SRC_DIR 2>&1 >/dev/null
			fedpkg clone $PKG
			(cd $PKG && fedpkg switch-branch $REF && fedpkg --release=f$PLATFORM sources)
			popd 2>&1 >/dev/null
		else
			# Already cloned, was it already built?
			SRC_RPM=$(cd $BUILD_SRC_DIR/$PKG && ls *.src.rpm 2>/dev/null)
			if [ -n "$SRC_RPM" ] ; then
				if [ -f "$BUILD_RESULT_DIR/$SRC_RPM" ] ; then
					# SRPM already exists in results dir, so it was probably already built
					do_build="false"
				fi
			else
				(cd $BUILD_SRC_DIR/$PKG && fedpkg --release=f$PLATFORM sources)
			fi
		fi
		if [ "$do_build" = "true" ] ; then
			echo "Queuing $PKG"
			queue_build $PKG
		else
			echo "Skipping $PKG"
		fi
	done
	queue_close
	./update_repo.py $MODULE $MOCKBUILD_DIR
	# Exit once the given build rank is reached
	if [ -n "$BUILD_RANK" ] ; then
		if [ "$BUILD_RANK" = "$CURRENT_RANK" ] ; then
			break
		fi
	fi
done
