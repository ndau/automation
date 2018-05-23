#!/bin/bash

# This script brings up the chaos node in kubernetes.


#cp $HOME/.tendermint/config/genesis.json $HOME/.tendermint/config/genesis.bak
#empty_hash=$(
#    docker-compose run --rm --no-deps chaosnode --echo-empty-hash |\
#    tr -d '\r'
#)
#jq ".app_hash=\"$empty_hash\"" $HOME/.tendermint/config/genesis.bak > $HOME/.tendermint/config/genesis.json
#rm $HOME/.tendermint/config/genesis.bak

# install chaosnode and noms
kubectl apply -f chaosnode-deployment.yaml
kubectl apply -f chaosnode-service.yaml

# get chaosnode's pod name
retries=5
for i in $(seq $retries 0); do
    podname=$(
        kubectl get pods --selector=app=chaosnode --output=json |\
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

retries=5
for i in $(seq $retries 0); do
    containerLog=$(kubectl logs $podname -c chaosnode-container 2>&1)
    if [ -z "$(grep 'Error' <<< $containerLog)" ]; then
        emptyHash=$( echo $containerLog |\
            grep -o -E 'emptyHash=(.*)' |\
            head -n 1 |\
            sed 's/.*=//'
        )
        echo "Got empty hash: $emptyHash"
        break
    else
        echo "chaosnode container not ready. Retrying $i more times."
        sleep 5
    fi
done

# update genesis.json
cp $HOME/.tendermint/config/genesis.json $HOME/.tendermint/config/genesis.bak
jq ".app_hash=\"$emptyHash\"" $HOME/.tendermint/config/genesis.bak > $HOME/.tendermint/config/genesis.json
rm $HOME/.tendermint/config/genesis.bak

# make configmaps for tendermint
kubectl create configmap tendermint-config-genesis --from-file=$HOME/.tendermint/config/genesis.json
kubectl create configmap tendermint-config-priv-validator --from-file=$HOME/.tendermint/config/priv_validator.json 

# install tendermint
kubectl apply -f tendermint-deployment.yaml
kubectl apply -f tendermint-service.yaml
