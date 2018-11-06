#!/bin/bash

set -x
set -e

# used for temp directory and s3 upload
DATE=$(date '+%Y-%m-%dT%H:%M:%SZ')
TEMP_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/tmp-$DATE"


clean() (

	set +x
	# clean up processes
	# shellcheck disable=2046
	kill -9 $(cat "$TEMP_DIR"/pids/* | tr "\n" " ")

)

trap clean EXIT

! clean

# configy things

# noms seems to need this
export NOMS_VERSION_NEXT=1

# random number to start the ports on
RND=$((10000 + RANDOM % 10000))


LH=127.0.0.1
CHAOS_NOMS="$TEMP_DIR"/chaos-noms
CHAOS_NOMS_PORT=$((0 + RND))
CHAOS_ABCI_PORT=$((1 + RND))
CHAOS_TM="$TEMP_DIR"/chaos-tm
CHAOS_TM_P2P_LADDR=tcp://$LH:$((2 + RND))
CHAOS_TM_RPC_LADDR=tcp://$LH:$((3 + RND))
CHAOS_LINK=http://$LH:$((3 + RND))

NDAU_NOMS="$TEMP_DIR"/ndau-noms
NDAU_HOME="$TEMP_DIR"/ndau-home
NDAU_NOMS_PORT=$((4 + RND))
NDAU_ABCI_PORT=$((5 + RND))
NDAU_TM="$TEMP_DIR"/ndau-tm
NDAU_TM_P2P_LADDR=tcp://$LH:$((6 + RND))
NDAU_TM_RPC_LADDR=tcp://$LH:$((7 + RND))

CHAOS_CMD="$GOPATH/src/github.com/oneiro-ndev/chaos/cmd/chaosnode/chaosnode"
NDAU_CMD="$GOPATH/src/github.com/oneiro-ndev/ndau/cmd/ndaunode/ndaunode"

if [ ! -f "$CHAOS_CMD" ] || [ ! -f "$NDAU_CMD" ]; then
	>&2 echo "please build chaosnode and ndaunode"
	exit 1
fi

# let's get started

# reset files
mkdir "$TEMP_DIR"
mkdir "$TEMP_DIR"/pids

# start chaos's noms
mkdir "$CHAOS_NOMS"
(
	cd "$CHAOS_NOMS"
	noms serve . --port=$CHAOS_NOMS_PORT &
	echo $! > "$TEMP_DIR"/pids/chaos-noms
)

# start ndau's noms
mkdir "$NDAU_NOMS"
(
	cd "$NDAU_NOMS"
	noms serve . --port=$NDAU_NOMS_PORT &
	echo $! > "$TEMP_DIR"/pids/ndau-noms
)
sleep 2

# get empty hashes
CHAOS_HASH=$($CHAOS_CMD -echo-hash --spec http://$LH:$CHAOS_NOMS_PORT >&1 )
NDAU_HASH=$($NDAU_CMD -echo-hash --spec http://$LH:$NDAU_NOMS_PORT >&1)

# init tendermints
tendermint --home "$CHAOS_TM" init
tendermint --home "$NDAU_TM" init

# update configs
jq ".app_hash=\"$CHAOS_HASH\"" "$CHAOS_TM"/config/genesis.json > "$CHAOS_TM"/config/new-genesis.json
diff "$CHAOS_TM"/config/new-genesis.json "$CHAOS_TM"/config/genesis.json || true # will return 1 for no newline
mv "$CHAOS_TM"/config/new-genesis.json "$CHAOS_TM"/config/genesis.json
cat "$CHAOS_TM"/config/genesis.json


jq ".app_hash=\"$NDAU_HASH\"" "$NDAU_TM"/config/genesis.json > "$NDAU_TM"/config/new-genesis.json
mv "$NDAU_TM"/config/new-genesis.json "$NDAU_TM"/config/genesis.json

# start tendermints
tendermint node --home "$CHAOS_TM" \
	--proxy_app tcp://$LH:$CHAOS_ABCI_PORT \
	--p2p.laddr $CHAOS_TM_P2P_LADDR \
	--rpc.laddr $CHAOS_TM_RPC_LADDR &
echo $! > "$TEMP_DIR"/pids/chaos-tm

tendermint node --home "$NDAU_TM" \
	--proxy_app tcp://$LH:$NDAU_ABCI_PORT \
	--p2p.laddr $NDAU_TM_P2P_LADDR \
	--rpc.laddr $NDAU_TM_RPC_LADDR &
echo $! > "$TEMP_DIR"/pids/ndau-tm

# fire up chaosnode
$CHAOS_CMD -addr "$LH:$CHAOS_ABCI_PORT" --spec http://$LH:$CHAOS_NOMS_PORT &
echo $! > "$TEMP_DIR"/pids/chaosnode

sleep 5 # let it get ready

# make mocks
NDAUHOME="$NDAU_HOME" $NDAU_CMD -make-mocks --spec http://$LH:$NDAU_NOMS_PORT

CFG_TOML=$NDAU_HOME/ndau/config.toml

# use gsed if availabile
SED="sed"
which gsed && SED=gsed

$SED -i '1,2d' "$CFG_TOML"
echo -e "UseMock = \"\"\n$(cat "$CFG_TOML")" > "$CFG_TOML"
echo -e "ChaosAddress = \"$CHAOS_LINK\"\n$(cat "$CFG_TOML")" > "$CFG_TOML"

# make chaos mocks
NDAUHOME="$NDAU_HOME" $NDAU_CMD -make-chaos-mocks --spec http://$LH:$NDAU_NOMS_PORT

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
aws s3 cp "$TEMP_DIR"/ndau-tm.tgz s3://ndau-snapshots/"$DATE"/ndau-tm.tgz
aws s3 cp "$TEMP_DIR"/chaos-tm.tgz s3://ndau-snapshots/"$DATE"/chaos-tm.tgz

exit 0
