#!/bin/bash
# This file creates a genesis snapshot for noms databases, svi-namespace, svi-key and updates the latest.txt file.


set -e
set -x

# random number to start the ports on
RND=$((10000 + RANDOM % 10000))

# used for temp directory and s3 upload
DATE=$(date '+%Y-%m-%dT%H-%M-%SZ')
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TEMP_DIR="$DIR/tmp-$DATE"

clean() (

	set +e
	set +x

	# kill all the containers that we dealt with
	docker kill chaos-noms-$RND
	docker kill ndau-noms-$RND
	docker kill chaosnode-hash-$RND
	docker kill ndaunode-hash-$RND
	docker kill chaos-tendermint-init-$RND
	docker kill ndau-tendermint-init-$RND
	docker kill chaos-tendermint-$RND
	docker kill ndau-tendermint-$RND
	docker kill chaosnode-$RND
	docker kill ndaunode-make-mocks-$RND
	docker kill ndau-redis-$RND
)

trap clean EXIT

! clean

# configy things
LH=127.0.0.1
CHAOS_NOMS="$TEMP_DIR"/chaos-noms
CHAOS_REDIS="$TEMP_DIR"/chaos-redis
CHAOS_NOMS_PORT=$((0 + RND))
CHAOS_TM="$TEMP_DIR"/chaos-tm
CHAOS_LINK=http://$LH:$((1 + RND))

NDAU_NOMS="$TEMP_DIR"/ndau-noms
NDAU_REDIS="$TEMP_DIR"/ndau-redis
NDAU_HOME="$TEMP_DIR"/ndau-home
NDAU_NOMS_PORT=$((2 + RND))
NDAU_ABCI_PORT=$((3 + RND))
NDAU_TM="$TEMP_DIR"/ndau-tm
NDAU_TM_P2P_LADDR=tcp://$LH:$((4 + RND))
NDAU_TM_RPC_LADDR=tcp://$LH:$((5 + RND))

NDAU_REDIS_PORT=$((6 + RND))
NDAU_REDIS_ADDR=$LH:$NDAU_REDIS_PORT
CHAOS_REDIS_PORT=$((7 + RND))
CHAOS_REDIS_ADDR=$LH:$CHAOS_REDIS_PORT

# if there's no NDAUNODE_TAG specified, use these
if [ ! -z "$NDAUNODE_TAG" ]; then
	NDAUNODE_TAG=$(git ls-remote https://github.com/oneiro-ndev/ndau |\
        grep 'refs/heads/master' | \
        awk '{{print $1}}' | \
        cut -c1-7)
	echo "Using chaos master $NDAUNODE_TAG"
fi


if [ ! -z "$CHAOSNODE_TAG" ]; then
	CHAOSNODE_TAG=$(git ls-remote https://github.com/oneiro-ndev/ndau |\
        grep 'refs/heads/master' | \
        awk '{{print $1}}' | \
        cut -c1-7)
	echo "Using chaos master $CHAOSNODE_TAG"
fi

# Use these images
NOMS_IMAGE=578681496768.dkr.ecr.us-east-1.amazonaws.com/noms:0.0.1
CHAOS_IMAGE=578681496768.dkr.ecr.us-east-1.amazonaws.com/chaosnode:$CHAOSNODE_TAG
NDAU_IMAGE=578681496768.dkr.ecr.us-east-1.amazonaws.com/ndaunode:$NDAUNODE_TAG
TENDERMINT_IMAGE=578681496768.dkr.ecr.us-east-1.amazonaws.com/tendermint:v0.25.0
REDIS_IMAGE=redis:4.0.11-alpine3.8

# let's get started

# reset files
rm -rf "$TEMP_DIR"
mkdir "$TEMP_DIR"
mkdir "$NDAU_HOME"
mkdir "$CHAOS_NOMS"
mkdir "$NDAU_NOMS"
mkdir -p "$CHAOS_TM"
mkdir -p "$NDAU_TM"
mkdir -p "$CHAOS_REDIS"
mkdir -p "$NDAU_REDIS"

# init chaos's noms with genesis tool
genesis -g "$DIR"/genesis.toml -n "$CHAOS_NOMS"

# start chaos's noms
docker run -d \
	--name="chaos-noms-$RND" \
	--network="host" \
	--mount src="$CHAOS_NOMS",target="$CHAOS_NOMS",type=bind \
	-e NOMS_VERSION_NEXT=1 \
	$NOMS_IMAGE \
	serve "$CHAOS_NOMS" --port=$CHAOS_NOMS_PORT

# start ndau's noms
docker run -d \
	--name="ndau-noms-$RND" \
	--network="host" \
	--mount src="$NDAU_NOMS",target="$NDAU_NOMS",type=bind \
	-e NOMS_VERSION_NEXT=1 \
	$NOMS_IMAGE \
	serve "$NDAU_NOMS" --port=$NDAU_NOMS_PORT

# start ndau's redis
docker run -d \
	--name="ndau-redis-$RND" \
	--network="host" \
	--mount src="$NDAU_REDIS",target="/data",type=bind \
	$REDIS_IMAGE \
	--port $NDAU_REDIS_PORT

sleep 2

# get hashes
CHAOS_HASH=$(docker run \
	--name="chaosnode-hash-$RND" \
	--network="host" \
	--mount src="$CHAOS_NOMS",target="$CHAOS_NOMS",type=bind \
	$CHAOS_IMAGE \
	-echo-hash --spec http://$LH:$CHAOS_NOMS_PORT \
	-index $CHAOS_REDIS_ADDR >&1 )
NDAU_HASH=$(docker run \
	--name="ndaunode-hash-$RND" \
	--network="host" \
	--mount src="$NDAU_NOMS",target="$NDAU_NOMS",type=bind \
	$NDAU_IMAGE \
	 -echo-hash --spec http://$LH:$NDAU_NOMS_PORT \
	 -index $NDAU_REDIS_ADDR >&1 )

# init tendermints
docker run \
	--name="chaos-tendermint-init-$RND" \
	--network="host" \
	--mount src="$CHAOS_TM",target="$CHAOS_TM",type=bind \
	$TENDERMINT_IMAGE \
	--home "$CHAOS_TM" init
docker run \
	--name="ndau-tendermint-init-$RND" \
	--network="host" \
	--mount src="$NDAU_TM",target="$NDAU_TM",type=bind \
	$TENDERMINT_IMAGE \
	--home "$NDAU_TM" init

# update genesis configs with app hash
jq ".app_hash=\"$CHAOS_HASH\"" "$CHAOS_TM"/config/genesis.json > "$CHAOS_TM"/config/new-genesis.json
mv "$CHAOS_TM"/config/new-genesis.json "$CHAOS_TM"/config/genesis.json
jq ".app_hash=\"$NDAU_HASH\"" "$NDAU_TM"/config/genesis.json > "$NDAU_TM"/config/new-genesis.json
mv "$NDAU_TM"/config/new-genesis.json "$NDAU_TM"/config/genesis.json

# start ndau tendermint
docker run -d \
	--name="ndau-tendermint-$RND" \
	--network="host" \
	--mount src="$NDAU_TM",target="$NDAU_TM",type=bind \
	$TENDERMINT_IMAGE \
	node --home "$NDAU_TM" \
	--proxy_app tcp://$LH:$NDAU_ABCI_PORT \
	--p2p.laddr $NDAU_TM_P2P_LADDR \
	--rpc.laddr $NDAU_TM_RPC_LADDR

sleep 10 # let it get ready


# copy genesis to somewhere accessible to the container
cp "$DIR"/genesis.toml "$NDAU_HOME"/genesis.toml

# make config.toml
docker run \
	--name="ndaunode-conf-$RND" \
	--network="host" \
	-e NDAUHOME="$NDAU_HOME" \
	-w "$NDAU_HOME" \
	--mount src="$NDAU_HOME",target="$NDAU_HOME",type=bind \
	$NDAU_IMAGE \
		-index $CHAOS_REDIS_ADDR \
		-spec http://$LH:$NDAU_NOMS_PORT  \
		--update-conf-from "$NDAU_HOME"/genesis.toml

CFG_TOML=$NDAU_HOME/ndau/config.toml

# use gsed if availabile
SED="sed"
which gsed && SED=gsed

$SED -i '1,2d' "$CFG_TOML"
echo -e "UseMock = \"\"\n$(cat "$CFG_TOML")" > "$CFG_TOML"
echo -e "ChaosAddress = \"$CHAOS_LINK\"\n$(cat "$CFG_TOML")" > "$CFG_TOML"

# Shut ndau tendermint
docker kill ndau-tendermint-$RND


# use hash thing
cp "$DIR"/assc.toml "$NDAU_HOME"
docker run \
	--name="ndaunode-accts-$RND" \
	--network="host" \
	-e NDAUHOME="$NDAU_HOME" \
	--mount src="$NDAU_HOME",target="$NDAU_HOME",type=bind \
	$NDAU_IMAGE \
	-index $CHAOS_REDIS_ADDR \
	-spec http://$LH:$NDAU_NOMS_PORT  \
	--update-chain-from "$NDAU_HOME"/assc.toml

# get hashes
docker run \
	--name="chaosnode-last-hash-$RND" \
	--network="host" \
	-e NDAUHOME="$NDAU_HOME" \
	--mount src="$CHAOS_NOMS",target="$CHAOS_NOMS",type=bind \
	$CHAOS_IMAGE \
	-index $CHAOS_REDIS_PORT \
	-echo-hash --spec http://$LH:$CHAOS_NOMS_PORT > "$TEMP_DIR"/chaos-hash

docker run \
	--name="ndaunode-last-hash-$RND" \
	--network="host" \
	-e NDAUHOME="$NDAU_HOME" \
	--mount src="$NDAU_NOMS",target="$NDAU_NOMS",type=bind \
	$NDAU_IMAGE \
	-index $CHAOS_REDIS_ADDR \
	-echo-hash --spec http://$LH:$NDAU_NOMS_PORT  > "$TEMP_DIR"/ndau-hash

# Shut down noms
docker kill ndau-noms-$RND

# if ted tool isn't there, build it
ted_dir="$TEMP_DIR"/../../ted
ted="$ted_dir"/ted
[ -x "$ted" ] || ( cd "$ted_dir"; go build .)

# get svi variables
"$ted" --file "$CFG_TOML" --path "SystemVariableIndirect.Namespace" > "$TEMP_DIR"/svi-namespace
"$ted" --file "$CFG_TOML" --path "SystemVariableIndirect.Key" > "$TEMP_DIR"/svi-key

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

# upload svi variables
aws s3 cp "$TEMP_DIR"/svi-namespace s3://ndau-snapshots/svi-namespace
aws s3 cp "$TEMP_DIR"/svi-key s3://ndau-snapshots/svi-key

# upload tarballs
aws s3 cp "$TEMP_DIR"/ndau-noms.tgz s3://ndau-snapshots/"$DATE"/ndau-noms.tgz
aws s3 cp "$TEMP_DIR"/chaos-noms.tgz s3://ndau-snapshots/"$DATE"/chaos-noms.tgz

exit 0
