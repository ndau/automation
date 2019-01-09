#!/bin/bash

read -r -d '' USAGE <<'EOF'
./nodegroup.sh RELEASE 10000 [-t] [-g] [-r] [-s] [-v] [-h]

This file starts a nodegroup using docker. It can also create a genesis snapshot for
  * noms databases,
  * tendermint's leveldb files,
  * svi-namespace and
  * updates the latest.txt file.

Arguments
  RELEASE just a name (the default is a timestamp). Has to be the first argument
    This will be used to name the temp directory `rel-RELEASE`.
	To use a timestamp, set the release value to the string `timestamp`.
  BASE_PORT port to start allocating ports for services, noms, etc.
    (the default is random between 10000-20000)
  --tendermint-init | -t  initializes tendermint and then quits.
  --genesis | -g     	  starts from scratch and goes through genesis.
  --run | -r              uses pretious RELEASE directory and leaves the nodegroup running
                            until the user hits a key.
  --snapshot | -s         make a snapshot.
  --latest | -l           include latest.txt with snapshot.
  --upload-snapshot | -u  upload a snapshot to s3.
  --verbose | -v 	      print extra debugging information.
  --help | -h 		      prints this usage message.

Environment variables
  The following environment variables may be used to specify which ecr images get used.
  They area 7 digit hex hashes that reference a specific image in ECR.
  `COMMANDS_TAG`, `NDAUNODE_TAG`, `CHAOSNODE_TAG`
EOF

# set -e # exit on error

# echo to stderr
errcho() {
	>&2 echo -e "$@"
}

# verbose errecho
verrcho() {
	if $VERBOSE; then errcho "$@"; fi
}

# print variable
var_print() {
	local k=$1
	local v=${!k}
	errcho "$k=$v"
}

# save container names here and clean them up on exit
CONTAINER_NAMES=()

# kill the docker containers we created
clean() (

	errcho "\n\nShutting down"

	set +e # don't exit on error
	set +x # echo commands

	# kill all the containers that we dealt with
	for one_container in "${CONTAINER_NAMES[@]}"; do
		verrcho "killing $one_container"
		docker kill $one_container 2> /dev/null
	done

)

# when the script exits, run the clean function
trap clean EXIT

# use gsed if availabile
SED="sed"
which gsed && SED=gsed

if [ "$#" -lt 2 ]; then
	errcho "$USAGE"
	exit 1
fi

GENESIS=false
RUN=false
USE_LATEST=false
VERBOSE=false
SNAPSHOT=false
UPLOAD_TO_S3=false
TENDERMINT_INIT=false
RELEASE=$1; shift
BASE_PORT=$1; shift
while [ "$1" != "" ]; do
    case $1 in
        -t | --tendermint-init )
			# just init tendermint, then quit.
		    TENDERMINT_INIT=true
            ;;
        -r | --run )
			# leave running
		    RUN=true
            ;;
        -g | --genesis )
			# do genesis as a part of starting
		    GENESIS=true
            ;;
        -s | --snapshot )
			SNAPSHOT=true
            ;;
        -u | --upload-snapshot )
			UPLOAD_TO_S3=true
            ;;
        -l | --latest )
			USE_LATEST=true
            ;;
        -v | --verbose )
			# turn on verbose mode
		    VERBOSE=true
            ;;
        -h | --help )
		    errcho "$USAGE"
            exit 0
            ;;
        * )
		    errcho "$USAGE"
            exit 1
    esac
    shift
done

var_print TENDERMINT_INIT
var_print RUN
var_print GENESIS
var_print SNAPSHOT
var_print UPLOAD_TO_S3
var_print RELEASE
var_print BASE_PORT

# this project root
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# Make sure we have the files we need to genesis
if [ ! -f "$DIR"/genesis.toml ] || [ ! -f "$DIR"/assc.toml ]; then
	errcho "Missing files $DIR/genesis.toml or $DIR/assc.toml"
	exit 1
fi

# make sure we have the genesis tools for genesis
if ! which genesis; then
	errcho "Please `go install` the genesis tool first."
	exit 1
fi

# TEMP_DIR is used as a temp directory and s3 upload
# allow specified RELEASE environment variable to override directory name.
if [ ! "$RELEASE" == "timestamp" ]; then
	TEMP_DIR="$DIR/rel-$RELEASE"
	SNAPSHOT_NAME=$RELEASE
	LATEST=false
else
	SNAPSHOT_NAME=$(date '+%Y-%m-%dT%H-%M-%SZ')
	TEMP_DIR="$DIR/rel-$SNAPSHOT_NAME"
	LATEST=SNAPSHOT_NAME
fi

# If genesising, check if the temp directory already exists
if [ -d "$TEMP_DIR" ] && $GENESIS; then
	errcho "Cannot genesis into already existing $TEMP_DIR, did you mean to use -g?"
	exit 1
fi

# configy things

# random number used as BASE_PORT when none provided, and as a
RND=$((10000 + RANDOM % 10000))
if [ -z "$BASE_PORT" ]; then
	BASE_PORT=RND
fi

# stamp adds this run's random number for docker purposes
stamp() {
	echo "$1-$RND"
}

PC=0 # port count
IH=$(docker run busybox ip route | awk '/default/ { print $3 }') # internal host

errcho "Config"

var_print RND

CHAOS_NOMS="$TEMP_DIR"/chaos-noms; var_print CHAOS_NOMS
CHAOS_REDIS="$TEMP_DIR"/chaos-redis; var_print CHAOS_REDIS
CHAOS_NOMS_PORT=$((PC++ + BASE_PORT)); var_print CHAOS_NOMS_PORTS
CHAOS_REDIS_PORT=$((PC++ + BASE_PORT)); var_print CHAOS_REDIS_PORT
CHAOS_REDIS_ADDR=$IH:$CHAOS_REDIS_PORT; var_print CHAOS_REDIS_ADDR
CHAOS_TM="$TEMP_DIR"/chaos-tm; var_print CHAOS_TM
CHAOS_TM_P2P_PORT=$((PC++ + BASE_PORT)); var_print CHAOS_TM_P2P_PORT
CHAOS_TM_RPC_PORT=$((PC++ + BASE_PORT)); var_print CHAOS_TM_RPC_PORT
CHAOS_TM_P2P_LADDR=tcp://0.0.0.0:$CHAOS_TM_P2P_PORT; var_print CHAOS_TM_P2P_LADDR
CHAOS_TM_RPC_LADDR=tcp://0.0.0.0:$CHAOS_TM_RPC_PORT; var_print CHAOS_TM_RPC_LADDR
CHAOS_ABCI_PORT=$((PC++ + BASE_PORT)); var_print CHAOS_ABCI_PORT
CHAOS_LINK=http://$IH:$CHAOS_TM_RPC_PORT; var_print CHAOS_LINK

NDAU_NOMS="$TEMP_DIR"/ndau-noms; var_print NDAU_NOMS
NDAU_REDIS="$TEMP_DIR"/ndau-redis; var_print NDAU_REDIS
NDAU_HOME="$TEMP_DIR"/ndau-home; var_print NDAU_HOME
NDAU_NOMS_PORT=$((PC++ + BASE_PORT)); var_print NDAU_NOMS_PORT
NDAU_ABCI_PORT=$((PC++ + BASE_PORT)); var_print NDAU_ABCI_PORT
NDAU_TM="$TEMP_DIR"/ndau-tm; var_print NDAU_TM
NDAU_TM_P2P_PORT=$((PC++ + BASE_PORT)); var_print NDAU_TM_P2P_PORT
NDAU_TM_P2P_LADDR=tcp://0.0.0.0:$NDAU_TM_P2P_PORT; var_print NDAU_TM_P2P_LADDR
NDAU_TM_RPC_PORT=$((PC++ + BASE_PORT)); var_print NDAU_TM_RPC_PORT
NDAU_TM_RPC_LADDR=tcp://0.0.0.0:$NDAU_TM_RPC_PORT; var_print NDAU_TM_RPC_LADDR
NDAU_REDIS_PORT=$((PC++ + BASE_PORT)); var_print NDAU_REDIS_PORT
NDAU_REDIS_ADDR=$IH:$NDAU_REDIS_PORT; var_print NDAU_REDIS_ADDR

LOGS_DIR="$TEMP_DIR"/logs; var_print LOGS_DIR
SNAPSHOT_DIR="$TEMP_DIR"/snapshots; var_print SNAPSHOT_DIR

# location of ndaunode's config.toml
CFG_TOML=$NDAU_HOME/ndau/config.toml; var_print CFG_TOML

var_print TEMP_DIR
var_print BASE_PORT

# use commands tag for CHAOSNODE_TAG and NDAUNODE_TAG if it's there
if [ ! -z "$COMMANDS_TAG" ]; then
	NDAUNODE_TAG=$COMMANDS_TAG
	CHAOSNODE_TAG=$COMMANDS_TAG
fi

# if there's no NDAUNODE_TAG specified, use these
if [ -z "$NDAUNODE_TAG" ] || [ -z "$CHAOSNODE_TAG" ]; then

	COMMANDS_TAG=$(git ls-remote https://github.com/oneiro-ndev/commands |\
        grep 'refs/heads/master' | \
        awk '{{print $1}}' | \
        cut -c1-7)

	if [ -z "$COMMANDS_TAG" ]; then
		errcho "Couldn't fetch commands' master sha"
		exit 1
	fi

	if [ -z "$NDAUNODE_TAG" ]; then
		NDAUNODE_TAG="$COMMANDS_TAG"
	fi
	if [ -z "$CHAOSNODE_TAG" ]; then
		CHAOSNODE_TAG="$COMMANDS_TAG"
	fi

fi

# Use these images
ECR=578681496768.dkr.ecr.us-east-1.amazonaws.com
NOMS_IMAGE=$ECR/noms:0.0.1; var_print NOMS_IMAGE
CHAOS_IMAGE=$ECR/chaosnode:$CHAOSNODE_TAG; var_print CHAOS_IMAGE
NDAU_IMAGE=$ECR/ndaunode:$NDAUNODE_TAG; var_print NDAU_IMAGE
TENDERMINT_IMAGE=$ECR/tendermint:v0.25.0; var_print TENDERMINT_IMAGE
REDIS_IMAGE=redis:4.0.11-alpine3.8; var_print REDIS_IMAGE



# define functions for readability in the following section

# persistent containers. usually stick around, container names saved for cleanup.
run_ndaunode() {
	basename="ndaunode"
	container_name=$( stamp $basename )
	CONTAINER_NAMES+=("$container_name")
	verrcho "$container_name"
	docker run -d \
		--name="$container_name" \
		-e NDAUHOME="$NDAU_HOME" \
		-w "$NDAU_HOME" \
		-p $NDAU_ABCI_PORT:$NDAU_ABCI_PORT \
		--mount src="$NDAU_HOME",target="$NDAU_HOME",type=bind \
		$NDAU_IMAGE \
			-index $NDAU_REDIS_ADDR \
			-addr 0.0.0.0:$NDAU_ABCI_PORT \
			-spec http://$IH:$NDAU_NOMS_PORT
	docker logs -f "$container_name" &> "$LOGS_DIR"/$basename &
}

run_chaosnode() {
	basename="chaosnode"
	container_name=$( stamp $basename )
	CONTAINER_NAMES+=("$container_name")
	verrcho "$container_name"
	docker run -d \
		--name="$container_name" \
		-e NDAUHOME="$NDAU_HOME" \
		-w "$NDAU_HOME" \
		--mount src="$NDAU_HOME",target="$NDAU_HOME",type=bind \
		-p $CHAOS_ABCI_PORT:$CHAOS_ABCI_PORT \
		$CHAOS_IMAGE \
			-index $CHAOS_REDIS_ADDR \
			-addr 0.0.0.0:$CHAOS_ABCI_PORT \
			-spec http://$IH:$CHAOS_NOMS_PORT
	docker logs -f "$container_name" &> "$LOGS_DIR"/$basename &
}

run_chaos_redis() {
	basename="chaos-redis"
	container_name=$( stamp $basename )
	CONTAINER_NAMES+=("$container_name")
	verrcho "$container_name"
	docker run -d \
		--name="$container_name" \
		--mount src="$CHAOS_REDIS",target="/data",type=bind \
		-p $CHAOS_REDIS_PORT:$CHAOS_REDIS_PORT \
		$REDIS_IMAGE \
		--port $CHAOS_REDIS_PORT
	docker logs -f "$container_name" &> "$LOGS_DIR"/$basename &
}

run_chaos_noms() {
	basename="chaos-noms"
	container_name=$( stamp $basename )
	CONTAINER_NAMES+=("$container_name")
	verrcho "$container_name"
	docker run -d \
		--name="$container_name" \
		--mount src="$CHAOS_NOMS",target="$CHAOS_NOMS",type=bind \
		-p $CHAOS_NOMS_PORT:$CHAOS_NOMS_PORT \
		-e NOMS_VERSION_NEXT=1 \
		$NOMS_IMAGE \
		serve "$CHAOS_NOMS" --port="$CHAOS_NOMS_PORT"
	docker logs -f "$container_name" &> "$LOGS_DIR"/$basename &
}

run_ndau_noms() {
	basename="ndau-noms"
	container_name=$( stamp $basename )
	CONTAINER_NAMES+=("$container_name")
	verrcho "$container_name"
	docker run -d \
		--name="$container_name" \
		--mount src="$NDAU_NOMS",target="$NDAU_NOMS",type=bind \
		-e NOMS_VERSION_NEXT=1 \
		-p $NDAU_NOMS_PORT:$NDAU_NOMS_PORT \
		$NOMS_IMAGE \
		serve "$NDAU_NOMS" --port=$NDAU_NOMS_PORT
	docker logs -f "$container_name" &> "$LOGS_DIR"/$basename &
}

run_ndau_redis() {
	basename="ndau-redis"
	container_name=$( stamp $basename )
	CONTAINER_NAMES+=("$container_name")
	verrcho "$container_name"
	docker run -d \
		--name="$container_name" \
		--mount src="$NDAU_REDIS",target="/data",type=bind \
		-p $NDAU_REDIS_PORT:$NDAU_REDIS_PORT \
		$REDIS_IMAGE \
		--port $NDAU_REDIS_PORT
	docker logs -f "$container_name" &> "$LOGS_DIR"/$basename &
}


# transient. Deleted immediately upon completion of the container's process.
get_chaos_hash() {
	basename="chaosnode-hash"
	container_name=$( stamp $basename )
	verrcho "$container_name"
	docker run \
		--name="$container_name" \
		--mount src="$CHAOS_NOMS",target="$CHAOS_NOMS",type=bind \
		$CHAOS_IMAGE \
		-echo-hash \
		--spec http://$IH:$CHAOS_NOMS_PORT \
		-index $CHAOS_REDIS_ADDR >&1
	docker logs "$container_name" &> "$LOGS_DIR"/$basename &
	docker rm $(docker ps -aq --filter name=$container_name) &> /dev/null
}

get_ndau_hash() {
	basename="ndaunode-hash"
	container_name=$( stamp $basename )
	verrcho "$container_name"
	docker run \
		--name="$container_name" \
		--mount src="$NDAU_NOMS",target="$NDAU_NOMS",type=bind \
		$NDAU_IMAGE \
		-echo-hash \
		--spec http://$IH:$NDAU_NOMS_PORT \
		-index $NDAU_REDIS_ADDR >&1 | tr -d '\n'
	docker logs "$container_name" &> "$LOGS_DIR"/$basename &
	docker rm $(docker ps -aq --filter name=$container_name)  &> /dev/null
}

init_chaos_tendermint() {
	basename="chaos-tendermint-init"
	container_name=$( stamp $basename )
	verrcho "$container_name"
	docker run \
		--name="$container_name" \
		--mount src="$CHAOS_TM",target="$CHAOS_TM",type=bind \
		$TENDERMINT_IMAGE \
		--home "$CHAOS_TM" init
	docker logs "$container_name" &> "$LOGS_DIR"/$basename &
}

init_ndau_tendermint() {
	basename="ndau-tendermint-init"
	container_name=$( stamp $basename )
	docker run \
		--name="$container_name" \
		--mount src="$NDAU_TM",target="$NDAU_TM",type=bind \
		$TENDERMINT_IMAGE \
		--home "$NDAU_TM" init
	docker logs "$container_name" &> "$LOGS_DIR"/$basename &
}

run_ndau_tendermint() {
	basename="ndau-tendermint"
	container_name=$( stamp $basename )
	CONTAINER_NAMES+=("$container_name")
	verrcho "$container_name"
	docker run -d \
		--name="$container_name" \
		-p $NDAU_TM_RPC_PORT:$NDAU_TM_RPC_PORT \
		-p $NDAU_TM_P2P_PORT:$NDAU_TM_P2P_PORT \
		--mount src="$NDAU_TM",target="$NDAU_TM",type=bind \
		$TENDERMINT_IMAGE \
		node \
		--home "$NDAU_TM" \
		--proxy_app tcp://$IH:$NDAU_ABCI_PORT \
		--p2p.laddr $NDAU_TM_P2P_LADDR \
		--rpc.laddr $NDAU_TM_RPC_LADDR
	docker logs -f "$container_name" &> "$LOGS_DIR"/$basename &
}

make_ndau_config_toml() {
	basename="ndaunode-conf"
	container_name=$( stamp $basename )
	verrcho "$container_name"
	docker run \
		--name="$container_name" \
		-e NDAUHOME="$NDAU_HOME" \
		-w "$NDAU_HOME" \
		--mount src="$NDAU_HOME",target="$NDAU_HOME",type=bind \
		$NDAU_IMAGE \
			-index $NDAU_REDIS_ADDR \
			-spec http://$IH:$NDAU_NOMS_PORT  \
			--update-conf-from "$NDAU_HOME"/genesis.toml
	docker logs "$container_name" &> "$LOGS_DIR"/$basename &
}

run_chaos_tendermint() {
	basename="chaos-tendermint"
	container_name=$( stamp $basename )
	CONTAINER_NAMES+=("$container_name")
	verrcho "$container_name"
	docker run -d \
		--name="$container_name" \
		-p $CHAOS_TM_RPC_PORT:$CHAOS_TM_RPC_PORT \
		-p $CHAOS_TM_P2P_PORT:$CHAOS_TM_P2P_PORT \
		--mount src="$CHAOS_TM",target="$CHAOS_TM",type=bind \
		$TENDERMINT_IMAGE \
		node --home "$CHAOS_TM" \
		--proxy_app tcp://$IH:$CHAOS_ABCI_PORT \
		--p2p.laddr $CHAOS_TM_P2P_LADDR \
		--rpc.laddr $CHAOS_TM_RPC_LADDR
	docker logs -f "$container_name" &> "$LOGS_DIR"/$basename &
}

install_special_accounts() {
	cp "$DIR"/assc.toml "$NDAU_HOME"
	basename="ndaunode-accts"
	container_name=$( stamp $basename )
	verrcho "$container_name"
	docker run \
		--name="$container_name" \
		-e NDAUHOME="$NDAU_HOME" \
		--mount src="$NDAU_HOME",target="$NDAU_HOME",type=bind \
		$NDAU_IMAGE \
		-index $NDAU_REDIS_ADDR \
		-spec http://$IH:$NDAU_NOMS_PORT  \
		--update-chain-from "$NDAU_HOME"/assc.toml
	docker logs "$container_name" &> "$LOGS_DIR"/$basename &
}

write_chaos_last_hash() {
	basename="chaosnode-last-hash"
	container_name=$( stamp $basename )
	verrcho "$container_name"
	docker run \
		--name="$container_name" \
		-e NDAUHOME="$NDAU_HOME" \
		--mount src="$CHAOS_NOMS",target="$CHAOS_NOMS",type=bind \
		$CHAOS_IMAGE \
		-index $CHAOS_REDIS_PORT \
		-echo-hash \
		--spec http://$IH:$CHAOS_NOMS_PORT > "$TEMP_DIR"/chaos-hash
	docker logs "$container_name" &> "$LOGS_DIR"/$basename &
}

write_ndau_last_hash() {
	basename="ndaunode-last-hash"
	container_name=$( stamp $basename )
	verrcho "$container_name"
	docker run \
		--name="$container_name" \
		-e NDAUHOME="$NDAU_HOME" \
		--mount src="$NDAU_NOMS",target="$NDAU_NOMS",type=bind \
		$NDAU_IMAGE \
		-index $NDAU_REDIS_ADDR \
		-echo-hash \
		--spec http://$IH:$NDAU_NOMS_PORT  > "$TEMP_DIR"/ndau-hash
	docker logs "$container_name" &> "$LOGS_DIR"/$basename &
}

make_snapshot() {

	# if ted tool isn't there, build it
	ted_dir="$TEMP_DIR"/../../ted
	ted="$ted_dir"/ted
	verrcho "ted: $ted"
	[ -x "$ted" ] || ( cd "$ted_dir"; go build .)
	[ -x "$ted" ] || (errcho "Could not build ted tool"; exit 1)

	# get svi variables
	"$ted" --file "$CFG_TOML" --path "SystemVariableIndirect.Namespace" > "$SNAPSHOT_DIR"/svi-namespace

	verrcho "svi-namespace: $(cat "$SNAPSHOT_DIR"/svi-namespace)"

	# zip up the noms databases
	(
		cd "$CHAOS_NOMS"
		tar czvf "$SNAPSHOT_DIR"/chaos-noms.tgz .
	)
	(
		cd "$NDAU_NOMS"
		tar czvf "$SNAPSHOT_DIR"/ndau-noms.tgz .
	)

	# zip up the tendermint databases
	(
		cd "$CHAOS_TM"/data
		tar czvf "$SNAPSHOT_DIR"/chaos-tm.tgz ./blockstore.db ./state.db
	)
	(
		cd "$NDAU_TM"/data
		tar czvf "$SNAPSHOT_DIR"/ndau-tm.tgz ./blockstore.db ./state.db
	)

	# copy genesises
	(
		cd "$CHAOS_TM"
		tar czvf "$SNAPSHOT_DIR"/chaos-genesis.tgz "$CHAOS_TM"/config/genesis.json
	)
	(
		cd "$NDAU_TM"
		tar czvf "$SNAPSHOT_DIR"/ndau-genesis.tgz "$NDAU_TM"/config/genesis.json
	)

	# make latest
	if $USE_LATEST; then
		printf $LATEST > "$SNAPSHOT_DIR"/latest.txt
	fi

}

update_genesis_app_hash() {

	# get hashes
	CHAOS_HASH=$(get_chaos_hash)
	NDAU_HASH=$(get_ndau_hash)

	errcho "chaos app hash: $CHAOS_HASH, ndau app hash: $NDAU_HASH"

	# update genesis configs with app hash
	jq ".app_hash=\"$CHAOS_HASH\"" "$CHAOS_TM"/config/genesis.json > "$CHAOS_TM"/config/new-genesis.json
	diff "$CHAOS_TM"/config/new-genesis.json "$CHAOS_TM"/config/genesis.json
	mv "$CHAOS_TM"/config/new-genesis.json "$CHAOS_TM"/config/genesis.json

	jq ".app_hash=\"$NDAU_HASH\"" "$NDAU_TM"/config/genesis.json > "$NDAU_TM"/config/new-genesis.json
	diff "$NDAU_TM"/config/new-genesis.json "$NDAU_TM"/config/genesis.json
	mv "$NDAU_TM"/config/new-genesis.json "$NDAU_TM"/config/genesis.json

}

upload_snapshot() {
	aws s3 cp "$SNAPSHOT_DIR"/latest.txt s3://ndau-snapshots/latest.txt

	# upload tarballs
	aws s3 cp "$SNAPSHOT_DIR"/ndau-noms.tgz s3://ndau-snapshots/"$SNAPSHOT_NAME"/ndau-noms.tgz
	aws s3 cp "$SNAPSHOT_DIR"/chaos-noms.tgz s3://ndau-snapshots/"$SNAPSHOT_NAME"/chaos-noms.tgz
	aws s3 cp "$SNAPSHOT_DIR"/ndau-tm.tgz s3://ndau-snapshots/"$SNAPSHOT_NAME"/ndau-tm.tgz
	aws s3 cp "$SNAPSHOT_DIR"/chaos-tm.tgz s3://ndau-snapshots/"$SNAPSHOT_NAME"/chaos-tm.tgz

	# upload hashes
	aws s3 cp "$SNAPSHOT_DIR"/ndau-hash s3://ndau-snapshots/"$SNAPSHOT_NAME"/ndau-hash
	aws s3 cp "$SNAPSHOT_DIR"/chaos-hash s3://ndau-snapshots/"$SNAPSHOT_NAME"/chaos-hash

	# upload hashes
	aws s3 cp "$SNAPSHOT_DIR"/chaos-genesis.tgz s3://ndau-snapshots/"$SNAPSHOT_NAME"/chaos-genesis.tgz
	aws s3 cp "$SNAPSHOT_DIR"/ndau-genesis.tgz s3://ndau-snapshots/"$SNAPSHOT_NAME"/ndau-genesis.tgz

}

# let's get started

# prepare directories
mkdir -p "$TEMP_DIR" || true
mkdir -p "$NDAU_HOME" || true
mkdir -p "$CHAOS_NOMS" || true
mkdir -p "$NDAU_NOMS" || true
mkdir -p "$CHAOS_TM" || true
mkdir -p "$NDAU_TM" || true
mkdir -p "$CHAOS_REDIS" || true
mkdir -p "$NDAU_REDIS" || true
mkdir -p "$LOGS_DIR" || true
mkdir -p "$SNAPSHOT_DIR" || true

if $GENESIS || $TENDERMINT_INIT; then
	# init chaos's noms directory with genesis tool
	# this writes variables generated with the generate tool
	# to chaos' noms directory
	genesis -g "$DIR"/genesis.toml -n "$CHAOS_NOMS"
fi

# start chaos and ndau dependencies
run_chaos_noms
run_chaos_redis
run_ndau_noms
run_ndau_redis

sleep 5

if $GENESIS || $TENDERMINT_INIT; then

	# init tendermints
	init_chaos_tendermint
	init_ndau_tendermint

	update_genesis_app_hash


	# allow localhost for testing
	NDAU_CFG_TOML=$NDAU_TM/config/config.toml
	$SED -i '/addr_book_strict/d' "$NDAU_CFG_TOML"
	echo -e "addr_book_strict = false\n$(cat "$NDAU_CFG_TOML")" > "$NDAU_CFG_TOML"

	CHAOS_CFG_TOML=$CHAOS_TM/config/config.toml
	$SED -i '/addr_book_strict/d' "$CHAOS_CFG_TOML"
	echo -e "addr_book_strict = false\n$(cat "$CHAOS_CFG_TOML")" > "$CHAOS_CFG_TOML"

	# allow unsafe rouets like dial peers
	$SED -i '/unsafe/d' "$NDAU_CFG_TOML"
	echo -e "unsafe = true\n$(cat "$NDAU_CFG_TOML")" > "$NDAU_CFG_TOML"

	$SED -i '/unsafe/d' "$CHAOS_CFG_TOML"
	echo -e "unsafe = true\n$(cat "$CHAOS_CFG_TOML")" > "$CHAOS_CFG_TOML"

	# update genesis configs with app hash
	jq ".chain_id=\"chaos-$RELEASE\"" "$CHAOS_TM"/config/genesis.json > "$CHAOS_TM"/config/new-genesis.json
	$VERBOSE && diff "$CHAOS_TM"/config/new-genesis.json "$CHAOS_TM"/config/genesis.json
	mv "$CHAOS_TM"/config/new-genesis.json "$CHAOS_TM"/config/genesis.json

	jq ".chain_id=\"ndau-$RELEASE\"" "$NDAU_TM"/config/genesis.json > "$NDAU_TM"/config/new-genesis.json
	$VERBOSE && diff "$NDAU_TM"/config/new-genesis.json "$NDAU_TM"/config/genesis.json
	mv "$NDAU_TM"/config/new-genesis.json "$NDAU_TM"/config/genesis.json

	if $TENDERMINT_INIT; then
		errcho "Tendermint initialized. Quitting now."
		exit 0
	fi

fi

if $GENESIS; then
	# copy genesis to somewhere accessible to the container
	cp "$DIR"/genesis.toml "$NDAU_HOME"/genesis.toml

	# make ndaunode's config.toml from genesis.toml
	make_ndau_config_toml

	# use hash thing
	install_special_accounts

	#
	update_genesis_app_hash

fi

# This will update chaosaddress to keep up with different dockerhost changes.

if [ ! -f "$CFG_TOML" ]; then
	touch "$CFG_TOML"
	cat <<- EOF > "$CFG_TOML"
	ChaosAddress = ""
	ChaosTimeout = 500

	[SystemVariableIndirect]
	Namespace = ""
	Key = ""
	EOF
fi

if $RUN; then

	# add new ChaosAddress lines (this may change due to docker's internal host changing)
	$SED -i '/ChaosAddress/d' "$CFG_TOML"
	echo -e "ChaosAddress = \"$CHAOS_LINK\"\n$(cat "$CFG_TOML")" > "$CFG_TOML"

	$SED -i '/ChaosAddress/d' "$CFG_TOML"
	echo -e "ChaosAddress = \"$CHAOS_LINK\"\n$(cat "$CFG_TOML")" > "$CFG_TOML"

	# run ndaunode
	run_ndaunode

	# run odosnode
	run_chaosnode

	sleep 5 # let the nodes warm up

	# start ndau tendermint
	run_ndau_tendermint

	# start chaos tendermint
	run_chaos_tendermint

	read -p "Nodegroup running. Press any key to continue..." -n1 -s

fi

if $SNAPSHOT; then
	# get hashes
	write_chaos_last_hash
	write_ndau_last_hash

	# Get tarballs from directories
	make_snapshot
fi

if ! $UPLOAD_TO_S3; then
	errcho "Not uploading to S3"
	exit 0
else
	errcho "Uploading to S3"
	upload_snapshot
fi

exit 0
