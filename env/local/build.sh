#!/bin/bash

# This script builds the images.
# This script is fragile and needs to be kept in sync with chaosnode build instructions.
# This should probably be moved to chaosnode and kept up to date there.
# Note, this builds to minikube's docker. In the event these builds fail becasuse
# the machine is out of space, you may `minikube delete` which will completely remove
# the virtual machine. Normally a build process would push to a container repository
# and not a single virtual machine.

GREEN='\033[0;32m'
NC='\033[0m' # no color

echo_green() {
    echo -e "${GREEN}$@${NC}"
}

# this needs to start minikube to build to minikube's docker server
wait_for_minikube() {
	local retries=20
	local wait_seconds=5
	for i in $(seq $retries 0); do
		minikubeReady=$(minikube status | grep "minikube: Running")
		if [ ! -z "$minikubeReady" ]; then
			echo "Minikube ready"
			break
		else
			echo "Minikube not ready. Retrying $i more times."
			minikube start --vm-driver=hyperkit --disk-size 10g
			sleep $wait_seconds
		fi
	done
}

wait_for_minikube

echo_green "Connecting docker minikube's docker"
eval $(minikube docker-env)

# build chaosnode
if [ ! -f ../../gomu ]; then
    echo "Keyfile gomu not in project root directory."
    exit 1
fi

existed_before=false; [ -d ./chaosnode ] && existed_before=true;
echo_green "Cloning chaosnode"
git clone git@github.com:oneiro-ndev/chaosnode.git
cp ../../gomu chaosnode

echo_green "Building chaosnode"
docker build -t chaosnode --build-arg SSH_KEY_FILE="gomu" ./chaosnode

# build tendermint
echo_green "Building tendermint"
docker build -t tendermint ./chaosnode/tm-docker

# build noms
echo_green "Building noms image"
docker build -t noms ./chaosnode/noms-docker

# clean up
if ! $existed_before; then rm -rf chaosnode; fi
