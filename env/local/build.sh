#!/bin/bash

# This script builds the images.
# This script is fragile and needs to be kept in sync with chaosnode build instructions.
# This should probably be moved to chaosnode and kept up to date there.
# Note, this builds to minikube's docker. In the event these builds fail becasuse
# the machine is out of space, you may `minikube delete` which will completely remove
# the virtual machine. Normally a build process would push to a container repository
# and not a single virtual machine.

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck source=../common/helpers.sh
source "$DIR"/../common/helpers.sh

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
			minikube start --vm-driver=hyperkit --disk-size 20g
			sleep $wait_seconds
		fi
	done
}

wait_for_minikube

echo_green "Connecting docker minikube's docker"
eval "$(minikube docker-env)"

# build chaosnode
if [ ! -f ../../github_chaos_deploy ]; then
    echo "Key file github_chaos_deploy not in project root directory."
    exit 1
fi

chaos_existed_before=false; [ -d ./chaos ] && chaos_existed_before=true;
echo_green "Cloning chaos"
git clone git@github.com:oneiro-ndev/chaos.git
cp ../../github_chaos_deploy chaos

echo_green "Building chaosnode"
docker build -t chaosnode --build-arg ./chaos

ndau_existed_before=false; [ -d ./ndau ] && ndau_existed_before=true;
echo_green "Cloning ndau"
git clone git@github.com:oneiro-ndev/ndau.git
cp ../../github_chaos_deploy ndau

echo_green "Building ndau"
docker build -t ndaunode --build-arg ./ndau

# build tendermint
echo_green "Building tendermint"
docker build -t tendermint ./chaos/tm-docker

# build noms
echo_green "Building noms image"
docker build -t noms ./chaos/noms-docker

# clean up
if ! $chaos_existed_before; then rm -rf chaos; fi
if ! $ndau_existed_before; then rm -rf ndau; fi
