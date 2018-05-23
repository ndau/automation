#!/bin/bash

# This script builds the images.
# This script is fragile and needs to be kept in sync with chaosnode build instructions.
# This should probably be moved to chaosnode and kept up to date there.

# this needs to start minikube to build to minikube's docker server
retries=20
for i in $(seq $retries 0); do
    minikubeReady=$(minikube status | grep "minikube: Running")
    if [ -z "$(minikubeReady)" ]; then
        echo "Minikube ready"
        break
    else
        echo "Minikube not ready. Retrying $i more times."
        minikube start --vm-driver=hyperkit
        sleep 5
    fi
done
eval $(minikube docker-env)

# build chaosnode
if [ ! -f ./gomu ]; then
    echo "Keyfile gomu not in this directory."
    exit 1
fi
git clone git@github.com:oneiro-ndev/chaosnode.git
cp gomu chaosnode

docker build -t chaosnode --build-arg SSH_KEY_FILE="gomu" ./chaosnode

# build tendermint
docker build -t tendermint ./chaosnode/tm-docker

# initialize tendermint
# TODO: genesis.json is only used here just this once. Maybe there's a 
# better place for it instead of $HOME.
if [ ! -f "$HOME/.tendermint/config/genesis.json" ]; then
    echo "initializing tendermint"
    tendermint init
else
    echo "genesis.json detected"
fi

# build noms
docker build -t noms ./chaosnode/noms-docker
