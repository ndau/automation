#!/bin/bash
# This file makes a tar ball from the noms directory and uploads it to s3. It also updates the latest.txt file.

set -e
set -x

# used for temp directory and s3 upload

DATE=$(date '+%Y-%m-%dT%H-%M-%SZ')
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TEMP_DIR="$DIR/tmp-$DATE"

if [ "$1" == "-v" ]; then
 VERBOSE=true
fi

# echo to stderr
errcho() {
 >&2 echo "$@"
}

# verbose errecho
verrcho() {
 if $VERBOSE; then errcho "$@"; fi
}

if [ -z "$SNAPSHOT_BUCKET" ]; then
	SNAPSHOT_BUCKET="ndau-snapshots"
fi

if [ -z "$NETWORK_NAME" ]; then
	errcho "Env var NETWORK_NAME, not set."
	exit 1
fi

# if there's no NDAUNODE_TAG specified, use these
if [ -z "$NDAUNODE_TAG" ]; then
	NDAUNODE_TAG=$(git ls-remote https://github.com/ndau/ndau |\
        grep 'refs/heads/master' | \
        awk '{{print $1}}' | \
        cut -c1-7)
	if [ -z "$NDAUNODE_TAG" ]; then
		errcho "Couldn't fetch ndau's master sha"
		exit 1
	fi
	verrcho "Using ndau master sha: $NDAUNODE_TAG"
fi

# configy things
NDAU_NOMS=~/.localnet/data/noms-ndau-0

# let's get started

# reset files
mkdir -p "$TEMP_DIR"

# zip up the noms databases
(
	cd "$NDAU_NOMS"
	tar czvf "$TEMP_DIR"/ndau-noms.tgz .
)

# upload tarballs
aws s3 cp "$TEMP_DIR/ndau-noms.tgz" "s3://$SNAPSHOT_BUCKET/$NETWORK_NAME/$DATE/ndau-noms.tgz"

rm -rf "$TEMP_DIR"
exit 0
