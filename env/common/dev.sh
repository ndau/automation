#!/bin/bash

source ./helpers.sh

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# install brew if it's not already installed
if [ -z "$(which brew)" ]; then
    echo_green "Installing homebrew"
    /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
else
    echo "homebrew already present"
fi

# get the right sed
sed="sed"
sed --version > /dev/null 2>&1
if [ $? != 0 ]; then
    which gsed >/dev/null
    if [ $? != 0 ]; then
        echo_green "Installing gnu-sed"
        brew install gnu-sed
    else
        echo "sed is ok"
    fi
else
    echo "sed is ok"
fi

# Check gomu
if [ ! -f $DIR/../../gomu ]; then
    echo "Keyfile gomu not in project root directory."
    exit 1
fi

# check tendermint
REQUIRE_TENDERMINT_VERSION="0.18.0"

# install tendermint if not already there
if [ -z "$(which tendermint)" ]; then
    echo_green "Installing tendermint"
    go get -u github.com/golang/dep/... && \
    mkdir -p $GOPATH/src/github.com/tendermint && \
    git clone https://github.com/tendermint/tendermint.git \
    $GOPATH/src/github.com/tendermint/tendermint && \
    cd $GOPATH/src/github.com/tendermint/tendermint && \
    git checkout "v${REQUIRE_TENDERMINT_VERSION}" && \
    dep ensure && \
    go install -v -a -ldflags '-extldflags "-static"' ./cmd/tendermint
else
    echo "Tendermint already installed"
    if [ "$(tendermint version)" == "$REQUIRED_TENDERMINT_VERSION" ]; then
        echo "Wanted Tendermint version ${REQUIRED_TENDERMINT_VERSION}, got $(tendermint version)."
        exit 1
    fi
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
