#!/bin/bash

set -e
set -x

# random number to start the ports on
RND=$((10000 + RANDOM % 10000))

# used for temp directory and s3 upload
DATE=$(date '+%Y-%m-%dT%H-%M-%SZ')
TEMP_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/tmp-$DATE"

clean() (

	set +e
	set +x

	# clean up processes
	docker kill chaos-noms-$RND || true
	docker kill ndau-noms-$RND || true
	docker kill chaosnode-hash-$RND || true
	docker kill ndaunode-hash-$RND || true
	docker kill chaos-tendermint-init-$RND || true
	docker kill ndau-tendermint-init-$RND || true
	docker kill chaos-tendermint-$RND || true
	docker kill ndau-tendermint-$RND || true
	docker kill chaosnode-$RND || true
	docker kill ndaunode-make-mocks-$RND || true


)

trap clean EXIT

! clean

# configy things



TEMP_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/tmp-$DATE"

LH=127.0.0.1
CHAOS_NOMS="$TEMP_DIR"/chaos-noms
CHAOS_REDIS="$TEMP_DIR"/chaos-redis
CHAOS_NOMS_PORT=$((0 + RND))
CHAOS_ABCI_PORT=$((1 + RND))
CHAOS_TM="$TEMP_DIR"/chaos-tm
CHAOS_TM_P2P_LADDR=tcp://$LH:$((2 + RND))
CHAOS_TM_RPC_LADDR=tcp://$LH:$((3 + RND))
CHAOS_LINK=http://$LH:$((3 + RND))

NDAU_NOMS="$TEMP_DIR"/ndau-noms
NDAU_REDIS="$TEMP_DIR"/ndau-redis
NDAU_HOME="$TEMP_DIR"/ndau-home
NDAU_NOMS_PORT=$((4 + RND))
NDAU_ABCI_PORT=$((5 + RND))
NDAU_TM="$TEMP_DIR"/ndau-tm
NDAU_TM_P2P_LADDR=tcp://$LH:$((6 + RND))
NDAU_TM_RPC_LADDR=tcp://$LH:$((7 + RND))

NDAU_REDIS_PORT=$((8 + RND))
NDAU_REDIS_ADDR=$LH:$NDAU_REDIS_PORT
CHAOS_REDIS_PORT=$((9 + RND))
CHAOS_REDIS_ADDR=$LH:$CHAOS_REDIS_PORT

NOMS_IMAGE=578681496768.dkr.ecr.us-east-1.amazonaws.com/noms:0.0.1
CHAOS_IMAGE=578681496768.dkr.ecr.us-east-1.amazonaws.com/chaosnode:b07872d
NDAU_IMAGE=578681496768.dkr.ecr.us-east-1.amazonaws.com/ndaunode:a5a5468
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

# start chaos's redis
docker run -d \
	--name="chaos-redis-$RND" \
	--network="host" \
	--mount src="$CHAOS_REDIS",target="/data",type=bind \
	$REDIS_IMAGE \
	--port $CHAOS_REDIS_PORT

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

# update configs
jq ".app_hash=\"$CHAOS_HASH\"" "$CHAOS_TM"/config/genesis.json > "$CHAOS_TM"/config/new-genesis.json
diff "$CHAOS_TM"/config/new-genesis.json "$CHAOS_TM"/config/genesis.json
mv "$CHAOS_TM"/config/new-genesis.json "$CHAOS_TM"/config/genesis.json
cat "$CHAOS_TM"/config/genesis.json


jq ".app_hash=\"$NDAU_HASH\"" "$NDAU_TM"/config/genesis.json > "$NDAU_TM"/config/new-genesis.json
mv "$NDAU_TM"/config/new-genesis.json "$NDAU_TM"/config/genesis.json

# start tendermints
docker run -d \
	--name="chaos-tendermint-$RND" \
	--network="host" \
	--mount src="$CHAOS_TM",target="$CHAOS_TM",type=bind \
	$TENDERMINT_IMAGE \
	node --home "$CHAOS_TM" \
	--proxy_app tcp://$LH:$CHAOS_ABCI_PORT \
	--p2p.laddr $CHAOS_TM_P2P_LADDR \
	--rpc.laddr $CHAOS_TM_RPC_LADDR

docker run -d \
	--name="ndau-tendermint-$RND" \
	--network="host" \
	--mount src="$NDAU_TM",target="$NDAU_TM",type=bind \
	$TENDERMINT_IMAGE \
	node --home "$NDAU_TM" \
	--proxy_app tcp://$LH:$NDAU_ABCI_PORT \
	--p2p.laddr $NDAU_TM_P2P_LADDR \
	--rpc.laddr $NDAU_TM_RPC_LADDR

# fire up chaosnode
docker run -d \
	--name="chaosnode-$RND" \
	--network="host" \
	-e NDAUHOME="$NDAU_HOME" \
	--mount src="$NDAU_HOME",target="$NDAU_HOME",type=bind \
	$CHAOS_IMAGE \
	-addr "$LH:$CHAOS_ABCI_PORT" \
	-index $CHAOS_REDIS_ADDR \
	-spec http://$LH:$CHAOS_NOMS_PORT

# make config.toml by running make-mocks
docker run \
	--name="ndaunode-make-mocks-$RND" \
	--network="host" \
	-e NDAUHOME="$NDAU_HOME" \
	--mount src="$NDAU_HOME",target="$NDAU_HOME",type=bind \
	$NDAU_IMAGE \
	-make-mocks \
	-index $NDAU_REDIS_ADDR \
	-spec http://$LH:$NDAU_NOMS_PORT


sleep 10 # let it get ready

CFG_TOML=$NDAU_HOME/ndau/config.toml

# use gsed if availabile
SED="sed"
which gsed && SED=gsed

$SED -i '1,2d' "$CFG_TOML"
echo -e "UseMock = \"\"\n$(cat "$CFG_TOML")" > "$CFG_TOML"
echo -e "ChaosAddress = \"$CHAOS_LINK\"\n$(cat "$CFG_TOML")" > "$CFG_TOML"

cat $CFG_TOML

# make chaos mocks
docker run \
	--name="ndaunode-make-chaos-mocks-$RND" \
	--network="host" \
	-e NDAUHOME="$NDAU_HOME" \
	--mount src="$NDAU_HOME",target="$NDAU_HOME",type=bind \
	$NDAU_IMAGE \
	-make-chaos-mocks \
	-index $CHAOS_REDIS_ADDR \
	-spec http://$LH:$NDAU_NOMS_PORT


# Shut down tendermints
docker kill chaos-tendermint-$RND
docker kill ndau-tendermint-$RND


# get hashes
docker run \
	--name="chaosnode-last-hash-$RND" \
	--network="host" \
	-e NDAUHOME="$NDAU_HOME" \
	--mount src="$CHAOS_NOMS",target="$CHAOS_NOMS",type=bind \
	$CHAOS_IMAGE \
	-index $CHAOS_REDIS_PORT \
	 -echo-hash --spec http://$LH:$CHAOS_NOMS_PORT  > "$TEMP_DIR"/chaos-hash

docker run \
	--name="ndaunode-last-hash-$RND" \
	--network="host" \
	-e NDAUHOME="$NDAU_HOME" \
	--mount src="$NDAU_NOMS",target="$NDAU_NOMS",type=bind \
	$NDAU_IMAGE \
	-index $CHAOS_REDIS_ADDR \
	-echo-hash --spec http://$LH:$NDAU_NOMS_PORT  > "$TEMP_DIR"/ndau-hash

# if ted tool isn't there, build it
ted_dir="$TEMP_DIR"/../../ted
ted="$ted_dir"/ted
[ -x "$ted" ] || ( cd "$ted_dir"; go build .)

# get svi variables
"$ted" --file "$CFG_TOML" --path "SystemVariableIndirect.Namespace" > "$TEMP_DIR"/svi-namespace
"$ted" --file "$CFG_TOML" --path "SystemVariableIndirect.Key" > "$TEMP_DIR"/svi-key

echo "Config.toml"
cat "$CFG_TOML"

# zip up the noms databases
(
	cd "$CHAOS_NOMS"
	tar czvf "$TEMP_DIR"/chaos-noms.tgz .
)

(
	cd "$NDAU_NOMS"
	tar czvf "$TEMP_DIR"/ndau-noms.tgz .
)

(
	cd "$CHAOS_TM"/data
	tar czvf "$TEMP_DIR"/chaos-tm.tgz .
)

(
	cd "$NDAU_TM"/data
	tar czvf "$TEMP_DIR"/ndau-tm.tgz .
)

# update latest timestamp
printf "%s" "$DATE" > "$TEMP_DIR"/latest.txt
aws s3 cp "$TEMP_DIR"/latest.txt s3://ndau-snapshots/latest.txt

# upload svi variables
aws s3 cp "$TEMP_DIR"/svi-namespace s3://ndau-snapshots/"$DATE"/svi-namespace

# upload tarballs
aws s3 cp "$TEMP_DIR"/ndau-noms.tgz s3://ndau-snapshots/"$DATE"/ndau-noms.tgz
aws s3 cp "$TEMP_DIR"/chaos-noms.tgz s3://ndau-snapshots/"$DATE"/chaos-noms.tgz
aws s3 cp "$TEMP_DIR"/ndau-tm.tgz s3://ndau-snapshots/"$DATE"/ndau-tendermint.tgz
aws s3 cp "$TEMP_DIR"/chaos-tm.tgz s3://ndau-snapshots/"$DATE"/chaos-tendermint.tgz

exit 0
