#!/bin/bash



clean() {

	# clean up processes
	NOMS_PIDS=$(ps aux | grep "noms" | grep -v "grep" | awk '{print $2}')
	kill -9 $NOMS_PIDS

	CHAOS_PID=$(ps aux | grep "chaosnode" | grep -v "grep" | awk '{print $2}')
	NDAU_PID=$(ps aux | grep "ndaunode" | grep -v "grep" | awk '{print $2}')
	kill -9 $CHAOS_PID
	kill -9 $NDAU_PID

	TM_PIDS=$(ps aux | grep "tendermint" | grep -v "grep" | awk '{print $2}')
	kill -9 $TM_PIDS

	# clean up directories
	rm -rf "$TEMP_DIR"

	rm data.chaos.tar data.chaos.tar.gz
	rm data.ndau.tar data.ndau.tar.gz
}
trap clean EXIT

clean

# exit on any error

# configy things

# noms seems to need this
export NOMS_VERSION_NEXT=1

TEMP_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/tmp"

LH=127.0.0.1

CHAOS_NOMS="$TEMP_DIR"/data.chaos
CHAOS_NOMS_PORT=4200
CHAOS_ABCI_PORT=4201
CHAOS_TM="$TEMP_DIR"/chaos-tm
CHAOS_TM_P2P_LADDR=tcp://$LH:4202
CHAOS_TM_RPC_LADDR=tcp://$LH:4203
CHAOS_LINK=http://$LH:4203

NDAU_NOMS="$TEMP_DIR"/data.ndau
NDAU_HOME="$TEMP_DIR"/ndau-home
NDAU_NOMS_PORT=4300
NDAU_ABCI_PORT=4301
NDAU_TM="$TEMP_DIR"/ndau-tm
NDAU_TM_P2P_LADDR=tcp://$LH:4302
NDAU_TM_RPC_LADDR=tcp://$LH:4303

CHAOS_CMD="$GOPATH/src/github.com/oneiro-ndev/chaos/cmd/chaosnode/chaosnode"
NDAU_CMD="$GOPATH/src/github.com/oneiro-ndev/ndau/cmd/ndaunode/ndaunode"

if [ ! -f "$CHAOS_CMD" ] || [ ! -f "$NDAU_CMD" ]; then
	>&2 echo "please build chaosnode and ndaunode"
	exit 1
fi

# let's get started

# reset files
mkdir "$TEMP_DIR"

# start chaos's noms
mkdir "$CHAOS_NOMS"
noms serve "$CHAOS_NOMS" --port=$CHAOS_NOMS_PORT &

# start ndau's noms
mkdir "$NDAU_NOMS"
noms serve "$NDAU_NOMS" --port=$NDAU_NOMS_PORT &

sleep 2

# get empty hashes
CHAOS_HASH=$($CHAOS_CMD -echo-hash --spec http://$LH:$CHAOS_NOMS_PORT >&1 )
NDAU_HASH=$($NDAU_CMD -echo-hash --spec http://$LH:$NDAU_NOMS_PORT >&1)

# init tendermints
tendermint --home "$CHAOS_TM" init
tendermint --home "$NDAU_TM" init

# update configs
jq ".app_hash=\"$CHAOS_HASH\"" $CHAOS_TM/config/genesis.json > $CHAOS_TM/config/new-genesis.json
diff $CHAOS_TM/config/new-genesis.json $CHAOS_TM/config/genesis.json || true
mv $CHAOS_TM/config/new-genesis.json $CHAOS_TM/config/genesis.json
cat $CHAOS_TM/config/genesis.json


jq ".app_hash=\"$NDAU_HASH\"" $NDAU_TM/config/genesis.json > $NDAU_TM/config/new-genesis.json
mv $NDAU_TM/config/new-genesis.json $NDAU_TM/config/genesis.json

# start tendermints
tendermint node --home "$CHAOS_TM" \
	--proxy_app tcp://$LH:$CHAOS_ABCI_PORT \
	--p2p.laddr $CHAOS_TM_P2P_LADDR \
	--rpc.laddr $CHAOS_TM_RPC_LADDR &

tendermint node --home "$NDAU_TM" \
	--proxy_app tcp://$LH:$NDAU_ABCI_PORT \
	--p2p.laddr $NDAU_TM_P2P_LADDR \
	--rpc.laddr $NDAU_TM_RPC_LADDR &

# fire up chaosnode
$CHAOS_CMD -addr "$LH:$CHAOS_ABCI_PORT" --spec http://$LH:$CHAOS_NOMS_PORT &

sleep 5 # let it get ready

# make mocks
NDAUHOME="$NDAU_HOME" $NDAU_CMD -make-mocks --spec http://$LH:$NDAU_NOMS_PORT

CFG_TOML=$NDAU_HOME/ndau/config.toml
gsed -i '1,2d' $CFG_TOML
echo -e "UseMock = \"\"\n$(cat $CFG_TOML)" > $CFG_TOML
echo -e "ChaosAddress = \"$CHAOS_LINK\"\n$(cat $CFG_TOML)" > $CFG_TOML

# make chaos mocks
NDAUHOME="$NDAU_HOME" $NDAU_CMD -make-chaos-mocks --spec http://$LH:$NDAU_NOMS_PORT

PROJECT_ROOT=$TEMP_DIR/..

tar cvf data.chaos.tar $CHAOS_NOMS
gzip data.chaos.tar
base64 -i data.chaos.tar.gz > data.chaos.b64

tar cvf data.ndau.tar $NDAU_NOMS
gzip data.ndau.tar
base64 -i data.ndau.tar.gz > data.ndau.b64

exit 0
