#!/bin/bash
# This file creates a genesis snapshot for noms databases, svi-namespace, svi-key and updates the latest.txt file.
#   -v for verbose mode

# docker running conventions
# Each docker image is run either with the -d or no -d flag. This means it will either run in detached mode,
# (in the background), or it will run in the foreground.
# In the example below there are several other options set.
# docker run \
#	--name="$container_name" \
#	--network="host" \
#	-e NDAUHOME="$NDAU_HOME" \
#	-w "$NDAU_HOME" \
#	--mount src="$NDAU_HOME",target="$NDAU_HOME",type=bind \
#	$NDAU_IMAGE \
#		-index $CHAOS_REDIS_ADDR \
#		-spec http://$LH:$NDAU_NOMS_PORT  \
#		--update-conf-from "$NDAU_HOME"/genesis.toml
#
#   $container_name is there so the name can be added to an array of container names to clean up at the end
#     of this script's execution. `trap clean EXIT`
#   --network="host" means that it will share the network interface of the host machine. This is generally considered
#     not a best practice, but is fine for our purposes. We don't run in production like this.
#   -e NDAUHOME="$NDAU_HOME" sets an environment variable accessible inside the container.
#	-w "$NDAU_HOME" sets the current working directory for when the container starts.
#	--mount src="$NDAU_HOME",target="$NDAU_HOME",type=bind simply shares our local directory specified with $NDAU_HOME
#     and makes it available at the same path within the container.
#   $NDAU_IMAGE This is the name of the docker image that is actually going to run.
#   The rest of the options are for the ndau image itself.
#
#   Docker gotcha: If you're trying to use a different entrypoint than the one specified in the image's dockerfile,
#   you have to use an odd argument sequence. This is how your command should look:
#      `docker run --entrypoint "/bin/ls" $NDAU_IMAGE -al /root/config`
#   This starts the $NDAU_IMAGE and executes `/bin/ls -al /root/config`. Little weird, huh? LFMF.

set -e

# echo to stderr
errcho() {
	>&2 echo "$@"
}

# verbose errecho
verrcho() {
	if $VERBOSE; then errcho "$@"; fi
}

if [ "$1" == "-v" ]; then
	VERBOSE=true
fi

# random number to start the ports on
RND=$((10000 + RANDOM % 10000))

# used for temp directory and s3 upload
DATE=$(date '+%Y-%m-%dT%H-%M-%SZ')
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TEMP_DIR="$DIR/tmp-$DATE"

# save container names here and clean them up on exit
CONTAINER_NAMES=()

clean() (

	set +e
	set +x

	# kill all the containers that we dealt with
	for one_container in "${CONTAINER_NAMES[@]}"; do
		verrcho "killing $one_container"
		docker kill $one_container
	done

)

trap clean EXIT

if [ ! -f "$DIR"/genesis.toml ] || [ ! -f "$DIR"/assc.toml ]; then
	errcho "Missing files"
	exit 1
fi

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

verrcho "Config"
verrcho "CHAOS_NOMS=$CHAOS_NOMS"
verrcho "CHAOS_REDIS=$CHAOS_REDIS"
verrcho "CHAOS_NOMS_PORT=$CHAOS_NOMS_PORT"
verrcho "CHAOS_TM=$CHAOS_TM"
verrcho "CHAOS_LINK=$CHAOS_LINK"
verrcho
verrcho "NDAU_NOMS=$NDAU_NOMS"
verrcho "NDAU_REDIS=$NDAU_REDIS"
verrcho "NDAU_HOME=$NDAU_HOME"
verrcho "NDAU_NOMS_PORT=$NDAU_NOMS_PORT"
verrcho "NDAU_ABCI_PORT=$NDAU_ABCI_PORT"
verrcho "NDAU_TM=$NDAU_TM"
verrcho "NDAU_TM_P2P_LADDR=$NDAU_TM_P2P_LADDR"
verrcho "NDAU_TM_RPC_LADDR=$NDAU_TM_RPC_LADDR"
verrcho
verrcho "NDAU_REDIS_PORT=$NDAU_REDIS_PORT"
verrcho "NDAU_REDIS_ADDR=$NDAU_REDIS_ADDR"
verrcho "CHAOS_REDIS_PORT=$CHAOS_REDIS_PORT"
verrcho "CHAOS_REDIS_ADDR=$CHAOS_REDIS_ADDR"


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
NOMS_IMAGE=578681496768.dkr.ecr.us-east-1.amazonaws.com/noms:0.0.1
CHAOS_IMAGE=578681496768.dkr.ecr.us-east-1.amazonaws.com/chaosnode:$CHAOSNODE_TAG
NDAU_IMAGE=578681496768.dkr.ecr.us-east-1.amazonaws.com/ndaunode:$NDAUNODE_TAG
TENDERMINT_IMAGE=578681496768.dkr.ecr.us-east-1.amazonaws.com/tendermint:v0.25.0
REDIS_IMAGE=redis:4.0.11-alpine3.8

# let's get started

# prepare directories
mkdir "$TEMP_DIR"
mkdir "$NDAU_HOME"
mkdir "$CHAOS_NOMS"
mkdir "$NDAU_NOMS"
mkdir -p "$CHAOS_TM"
mkdir -p "$NDAU_TM"
mkdir -p "$CHAOS_REDIS"
mkdir -p "$NDAU_REDIS"

# init chaos's noms directory with genesis tool
genesis -g "$DIR"/genesis.toml -n "$CHAOS_NOMS"

# start chaos's noms
container_name="chaos-noms-$RND"
CONTAINER_NAMES+=("$container_name")
verrcho "$container_name"
docker run -d \
	--name="$container_name" \
	--network="host" \
	--mount src="$CHAOS_NOMS",target="$CHAOS_NOMS",type=bind \
	-e NOMS_VERSION_NEXT=1 \
	$NOMS_IMAGE \
	serve "$CHAOS_NOMS" --port=$CHAOS_NOMS_PORT

# start ndau's noms
container_name="ndau-noms-$RND"
CONTAINER_NAMES+=("$container_name")
verrcho "$container_name"
docker run -d \
	--name="$container_name" \
	--network="host" \
	--mount src="$NDAU_NOMS",target="$NDAU_NOMS",type=bind \
	-e NOMS_VERSION_NEXT=1 \
	$NOMS_IMAGE \
	serve "$NDAU_NOMS" --port=$NDAU_NOMS_PORT


docker run -d \
	--name="$container_name" \
	--network="host" \
	--mount src="$NDAU_NOMS",target="$NDAU_NOMS",type=bind \
	-e NOMS_VERSION_NEXT=1 \
	$NOMS_IMAGE \
	serve "$NDAU_NOMS" --port=$NDAU_NOMS_PORT


# start ndau's redis
container_name="ndau-redis-$RND"
CONTAINER_NAMES+=("$container_name")
verrcho "$container_name"
docker run -d \
	--name="$container_name" \
	--network="host" \
	--mount src="$NDAU_REDIS",target="/data",type=bind \
	$REDIS_IMAGE \
	--port $NDAU_REDIS_PORT

sleep 2

# get hashes
container_name="chaosnode-hash-$RND"
CONTAINER_NAMES+=("$container_name")
verrcho "$container_name"
CHAOS_HASH=$(docker run \
	--name="$container_name" \
	--network="host" \
	--mount src="$CHAOS_NOMS",target="$CHAOS_NOMS",type=bind \
	$CHAOS_IMAGE \
	-echo-hash --spec http://$LH:$CHAOS_NOMS_PORT \
	-index $CHAOS_REDIS_ADDR >&1 )
errcho "CHAOS_HASH=$CHAOS_HASH"

container_name="ndaunode-hash-$RND"
CONTAINER_NAMES+=("$container_name")
verrcho "$container_name"
NDAU_HASH=$(docker run \
	--name="$container_name" \
	--network="host" \
	--mount src="$NDAU_NOMS",target="$NDAU_NOMS",type=bind \
	$NDAU_IMAGE \
	 -echo-hash --spec http://$LH:$NDAU_NOMS_PORT \
	 -index $NDAU_REDIS_ADDR >&1 )
errcho "NDAU_HASH=$NDAU_HASH"

# init tendermints
container_name="chaos-tendermint-init-$RND"
CONTAINER_NAMES+=("$container_name")
verrcho "$container_name"
docker run \
	--name="$container_name" \
	--network="host" \
	--mount src="$CHAOS_TM",target="$CHAOS_TM",type=bind \
	$TENDERMINT_IMAGE \
	--home "$CHAOS_TM" init
container_name="ndau-tendermint-init-$RND"
CONTAINER_NAMES+=("$container_name")
docker run \
	--name="$container_name" \
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
container_name="ndau-tendermint-$RND"
CONTAINER_NAMES+=("$container_name")
verrcho "$container_name"
docker run -d \
	--name="$container_name" \
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

# make config.toml from genesis.toml
container_name="ndaunode-conf-$RND"
CONTAINER_NAMES+=("$container_name")
verrcho "$container_name"
docker run \
	--name="$container_name" \
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

# delete UseMock and ChaosAddress lines
$SED -i '/UseMock/d' "$CFG_TOML"
$SED -i '/ChaosAddress/d' "$CFG_TOML"

# add new UseMock and ChaosAddress lines
echo -e "UseMock = \"\"\n$(cat "$CFG_TOML")" > "$CFG_TOML"
echo -e "ChaosAddress = \"$CHAOS_LINK\"\n$(cat "$CFG_TOML")" > "$CFG_TOML"

# Shut ndau tendermint
docker kill ndau-tendermint-$RND

# use hash thing
cp "$DIR"/assc.toml "$NDAU_HOME"
container_name="ndaunode-accts-$RND"
CONTAINER_NAMES+=("$container_name")
verrcho "$container_name"
docker run \
	--name="$container_name" \
	--network="host" \
	-e NDAUHOME="$NDAU_HOME" \
	--mount src="$NDAU_HOME",target="$NDAU_HOME",type=bind \
	$NDAU_IMAGE \
	-index $CHAOS_REDIS_ADDR \
	-spec http://$LH:$NDAU_NOMS_PORT  \
	--update-chain-from "$NDAU_HOME"/assc.toml

# get hashes
container_name="chaosnode-last-hash-$RND"
CONTAINER_NAMES+=("$container_name")
verrcho "$container_name"
docker run \
	--name="$container_name" \
	--network="host" \
	-e NDAUHOME="$NDAU_HOME" \
	--mount src="$CHAOS_NOMS",target="$CHAOS_NOMS",type=bind \
	$CHAOS_IMAGE \
	-index $CHAOS_REDIS_PORT \
	-echo-hash --spec http://$LH:$CHAOS_NOMS_PORT > "$TEMP_DIR"/chaos-hash

container_name="ndaunode-last-hash-$RND"
CONTAINER_NAMES+=("$container_name")
verrcho "$container_name"
docker run \
	--name="$container_name" \
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
[ -x "$ted" ] || (errcho "Could not build ted tool"; exit 1)

# get svi variables
"$ted" --file "$CFG_TOML" --path "SystemVariableIndirect.Namespace" > "$TEMP_DIR"/svi-namespace
"$ted" --file "$CFG_TOML" --path "SystemVariableIndirect.Key" > "$TEMP_DIR"/svi-key

verrcho "svi-namespace: $(cat "$TEMP_DIR"/svi-namespace)"
verrcho "svi-key: $(cat "$TEMP_DIR"/svi-key)"

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
