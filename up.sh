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
kubectl apply -f noms-deployment.yaml
kubectl apply -f noms-service.yaml

# install chaosnode
kubectl apply -f chaosnode-deployment.yaml
kubectl apply -f chaosnode-service.yaml

# get empty-hash
kubectl apply -f empty-hash-get-job.yaml

# get chaosnode's pod name
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

# get the chaosnode's log and extract the empty hash
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
kubectl delete -f empty-hash-get-job.yaml

# update genesis.json
cp $HOME/.tendermint/config/genesis.json $HOME/.tendermint/config/genesis.bak
jq ".app_hash=\"$emptyHash\"" $HOME/.tendermint/config/genesis.bak > $HOME/.tendermint/config/genesis.json
rm $HOME/.tendermint/config/genesis.bak

# update config.toml
cp $HOME/.tendermint/config/config.toml $HOME/.tendermint/config/config.bak 
$sed -E \
    -e '/^proxy_app/s|://[^:]*:|://chaosnode-service:|' \
    -e '/^create_empty_blocks_interval/s/[[:digit:]]+/10/' \
    -e '/^create_empty_blocks\b/{
            s/true/false/
            s/(.*)/# \1/
            i # tendermint respects create_empty_blocks *OR* create_empty_blocks_interval
        }' \
    $HOME/.tendermint/config/config.bak > $HOME/.tendermint/config/config.toml
rm $HOME/.tendermint/config/config.bak

# make configmaps for tendermint
kubectl create configmap tendermint-config-toml --from-file=$HOME/.tendermint/config/config.toml
kubectl create configmap tendermint-config-genesis --from-file=$HOME/.tendermint/config/genesis.json
kubectl create configmap tendermint-config-priv-validator --from-file=$HOME/.tendermint/config/priv_validator.json 

# install tendermint
kubectl apply -f tendermint-deployment.yaml
kubectl apply -f tendermint-service.yaml
