#!/bin/bash

# This script builds the images.
# This script is fragile and needs to be kept in sync with chaosnode build instructions.
# This should probably be moved to chaosnode and kept up to date there.
# This pushes to ECR.

source ./common.sh
me=`basename "$0"`
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# build chaosnode
if [ ! -f $DIR/../../gomu ]; then
    err $me "Keyfile `gomu` not in project root."
    exit 1
fi

existed_before=false; [ -d $DIR/chaosnode ] && existed_before=true;
echo_green "Cloning chaosnode"
git clone git@github.com:oneiro-ndev/chaosnode.git
cp $DIR/../../gomu chaosnode

echo_green "Building chaosnode"
docker build -t 578681496768.dkr.ecr.us-east-1.amazonaws.com/chaosnode  --build-arg SSH_KEY_FILE="gomu" $DIR/chaosnode
docker push 578681496768.dkr.ecr.us-east-1.amazonaws.com/chaosnode

# build tendermint
echo_green "Building tendermint"
docker build -t 578681496768.dkr.ecr.us-east-1.amazonaws.com/tendermint $DIR/chaosnode/tm-docker
docker push 578681496768.dkr.ecr.us-east-1.amazonaws.com/tendermint

# build noms
echo_green "Building noms image"
docker build -t 578681496768.dkr.ecr.us-east-1.amazonaws.com/noms  $DIR/chaosnode/noms-docker
docker push 578681496768.dkr.ecr.us-east-1.amazonaws.com/noms

# clean up
if ! $existed_before; then rm -rf $DIR/chaosnode; fi
