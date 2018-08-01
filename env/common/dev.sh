#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

source "$DIR"/helpers.sh

# install brew if it's not already installed
if [ -z "$(which brew)" ]; then
    echo_green "Installing homebrew"
    /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
else
    echo "homebrew already present"
fi

# install helm if it's not already installed
if [ -z "$(which helm)" ]; then
    echo_green "Installing helm"
    brew install kubernetes-helm
else
    echo "helm already present"
fi

# install kubectl if not already there
if [ -z "$(which kubectl)" ]; then
    echo_green "Installing kubectl"
    brew install kubectl
else
    echo "kubectl already present"
fi

# install minikube if not already there
if [ -z "$(which minikube)" ]; then
    echo_green "Installing minikube"
    brew cask install minikube
else
    echo "minikube already present"
fi

# install jq if not already there
if [ -z "$(which jq)" ]; then
    echo_green "Installing jq"
    brew install jq
else
    echo "jq already present"
fi

# installs the docker machine driver for docker's hypervisor
# https://github.com/kubernetes/minikube/blob/master/docs/drivers.md#hyperkit-driver
if [ -z "$(which docker-machine-driver-hyperkit)" ]; then
    echo_green "installing docker-machine-driver-hyperkit"
    curl -LO https://storage.googleapis.com/minikube/releases/latest/docker-machine-driver-hyperkit \
&& chmod +x docker-machine-driver-hyperkit \
&& sudo mv docker-machine-driver-hyperkit /usr/local/bin/ \
&& sudo chown root:wheel /usr/local/bin/docker-machine-driver-hyperkit \
&& sudo chmod u+s /usr/local/bin/docker-machine-driver-hyperkit
else
    echo "docker-machine-driver-hyperkit already present"
fi
