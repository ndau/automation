#!/bin/bash
# This file makes a tar ball from the noms directory and uploads it to s3. It also updates the latest.txt file.

set -e
set -x

# random number to start the ports on
RND=$((10000 + RANDOM % 10000))

# used for temp directory and s3 upload
DATE=$(date '+%Y-%m-%dT%H-%M-%SZ')
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TEMP_DIR="$DIR/tmp-$DATE"

# if there's no NDAUNODE_TAG specified, use these
if [ -z "$NDAUNODE_TAG" ]; then
	NDAUNODE_TAG=$(git ls-remote https://github.com/oneiro-ndev/ndau |\
        grep 'refs/heads/master' | \
        awk '{{print $1}}' | \
        cut -c1-7)
	if [ -z "$NDAUNODE_TAG" ]; then
		errcho "Couldn't fetch ndau's master sha"
		exit 1
	fi
	verrcho "Using chaos master sha: $NDAUNODE_TAG"
fi

if [ -z "$CHAOSNODE_TAG" ]; then
	CHAOSNODE_TAG=$(git ls-remote https://github.com/oneiro-ndev/chaos |\
        grep 'refs/heads/master' | \
        awk '{{print $1}}' | \
        cut -c1-7)
	if [ -z "$CHAOSNODE_TAG" ]; then
		errcho "Couldn't fetch chaos's master sha"
		exit 1
	fi
	verrcho "Using chaos master sha: $CHAOSNODE_TAG"
fi

# Use these images
CHAOS_IMAGE=578681496768.dkr.ecr.us-east-1.amazonaws.com/chaosnode:$CHAOSNODE_TAG
NDAU_IMAGE=578681496768.dkr.ecr.us-east-1.amazonaws.com/ndaunode:$NDAUNODE_TAG

# configy things
CHAOS_NOMS=$NDAUHOME/chaos/noms
NDAU_NOMS=$NDAUHOME/ndau/noms


# let's get started

# reset files
rm -rf "$TEMP_DIR"

# get hashes
CHAOS_HASH=$(docker run \
	--name="chaosnode-hash-$RND" \
	--network="host" \
	--mount src="$NDAUHOME",target="$NDAUHOME",type=bind \
	$CHAOS_IMAGE \
	-echo-hash --spec http://$LH:$CHAOS_NOMS_PORT >&1 )
NDAU_HASH=$(docker run \
	--name="ndaunode-hash-$RND" \
	--network="host" \
	--mount src="$NDAUHOME",target="$NDAUHOME",type=bind \
	$NDAU_IMAGE \
	 -echo-hash --spec http://$LH:$NDAU_NOMS_PORT >&1 )

# zip up the noms databases
(
	cd "$CHAOS_NOMS"
	tar czvf "$TEMP_DIR"/chaos-noms.tgz .
)

(
	cd "$NDAU_NOMS"
	tar czvf "$TEMP_DIR"/ndau-noms.tgz .
)

# update latest timestamp
printf "%s" "$DATE" > "$TEMP_DIR"/latest.txt
aws s3 cp "$TEMP_DIR"/latest.txt s3://ndau-snapshots/latest.txt


# upload tarballs
aws s3 cp "$TEMP_DIR"/ndau-noms.tgz s3://ndau-snapshots/"$DATE"/ndau-noms.tgz
aws s3 cp "$TEMP_DIR"/chaos-noms.tgz s3://ndau-snapshots/"$DATE"/chaos-noms.tgz

exit 0
