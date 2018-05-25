#!/bin/bash

# This script brings up the chaos node in kubernetes.

# gnu sed is required
sed=sed
sed --version > /dev/null 2>&1
if [ $? != 0 ]; then
    which gsed >/dev/null
    if [ $? != 0 ]; then
        (
            >&2 echo "You have a broken version of sed, and gsed is not installed"
            >&2 echo "This is common on OSX. Try `brew install gnu-sed`"
            exit 1
        )
    fi
    sed=gsed
    echo "using $sed as sed"
fi

# install noms
kubectl apply -f manifests/noms-deployment.yaml
kubectl apply -f manifests/noms-service.yaml

# install chaosnode
kubectl apply -f manifests/chaosnode-deployment.yaml
kubectl apply -f manifests/chaosnode-service.yaml

# get empty-hash
kubectl apply -f manifests/empty-hash-get-job.yaml

# get empty hash get job's pod name
retries=5
for i in $(seq $retries 0); do
    podname=$(
        kubectl get pods --selector=job-name=empty-hash-get-job --output=json |\
        jq -r ".items[0].metadata.name"
    )
    if [ "$podname" != "null" ]; then
        echo "Got chaosnode podname: $podname"
        break
    else
        echo "chaosnode pod not available. Retrying $i more times."
        sleep 5
    fi
done

# get the empty hash get job's log and extract the empty hash
retries=5
for i in $(seq $retries 0); do
    containerLog=$(kubectl logs $podname | tr -d '[:space:]')
    if [ -z "$containerLog" ]; then
        sleep 5 # get at least 5 seconds worth of logs
        containerLog=$(kubectl logs $podname)
        emptyHash=$(echo $containerLog | tr -d '[:space:]')
        echo "Got empty hash: $emptyHash"
        break
    else
        echo "chaosnode container not ready. Retrying $i more times."
        sleep 5
    fi
done
kubectl delete -f manifests/empty-hash-get-job.yaml

# initialize tendermint locally
TMOLD=$TMHOME
export TMHOME=$(pwd)/tmp
tendermint init
export TMHOME=$TMOLD

# update genesis.json
cp tmp/config/genesis.json tmp/config/genesis.bak
jq ".app_hash=\"$emptyHash\"" tmp/config/genesis.bak > tmp/config/genesis.json
rm tmp/config/genesis.bak

# update config.toml
cp tmp/config/config.toml tmp/config/config.bak 
$sed -E \
    -e '/^proxy_app/s|://[^:]*:|://chaosnode-service:|' \
    -e '/^create_empty_blocks_interval/s/[[:digit:]]+/10/' \
    -e '/^create_empty_blocks\b/{
            s/true/false/
            s/(.*)/# \1/
            i # tendermint respects create_empty_blocks *OR* create_empty_blocks_interval
        }' \
    tmp/config/config.bak > tmp/config/config.toml
rm tmp/config/config.bak

# make configmaps for tendermint
kubectl apply -f manifests/tendermint-config-init.yaml
kubectl create configmap tendermint-config-toml --from-file=tmp/config/config.toml
kubectl create configmap tendermint-config-genesis --from-file=tmp/config/genesis.json
kubectl create configmap tendermint-config-priv-validator --from-file=tmp/config/priv_validator.json 

# install tendermint
kubectl apply -f manifests/tendermint-deployment.yaml
kubectl apply -f manifests/tendermint-service.yaml
