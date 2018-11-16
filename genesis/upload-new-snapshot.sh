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
