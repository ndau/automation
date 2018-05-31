#!/bin/bash

# This script brings up the chaos node in kubernetes.

# preflight

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

usage() {
    echo "Usage"
    echo "For dude.ndau.tech:"
    echo "CLUSTER_NAME=dude PD=ndau.tech ./up.sh"
}

if [ -z "$PD" ]; then
    echo "Missing parent domain name."
    usage
    exit 1
fi

if [ -z "$CLUSTER_DOMAIN" ]; then
    echo "Missing cluster domain name."
    usage
    exit 1
fi


# functions

# gets the empty hash job's pod name
get_empty_hash_pod_name() {
    retries=5
    for i in $(seq $retries 0); do
        podname=$(
            kubectl get pods --selector=job-name=empty-hash-get-job --output=json |\
            jq -r ".items[0].metadata.name"
        )
        if [ "$podname" != "null" ]; then
            echo "Got empty has job podname: $podname"
            break
        else
            echo "empty has job pod not available. Retrying $i more times."
            sleep 5
        fi
    done
}

# gets the empty hash
get_empty_hash(){
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
            echo "empty hash container not ready. Retrying $i more times."
            sleep 5
        fi
    done
}

# try to get the elb address for tendermint
get_elb_address() {
    retries=5
    for i in $(seq $retries 0); do
        elb=$(kubectl get ingress --selector=app=tendermint -o json | jq -r ".items[0].status.loadBalancer.ingress[0].hostname")
        if [ -z "$elb" ]; then
            echo "Got tendermint ELB address: $elb"
            break
        else
            echo "tendermint elb address not ready. Retrying $i more times."
            sleep 5
        fi
    done

}

initialize_tendermint_config() {

    # get $emptyHash from chaosnode
    get_empty_hash_pod_name
    get_empty_hash

    # initialize tendermint locally
    TMOLD=$TMHOME
    export TMHOME=$(pwd)/tmp
    tendermint init
    export TMHOME=$TMOLD # cleanup

    # update genesis.json with chaosnode's empty hash
    cp tmp/config/genesis.json tmp/config/genesis.bak
    jq ".app_hash=\"$emptyHash\"" tmp/config/genesis.bak > tmp/config/genesis.json
    rm tmp/config/genesis.bak # cleanup

    # point tendermint's config to chaosnode-service
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
    rm tmp/config/config.bak # cleanup

}

# main

# volumes
kubectl apply -f ../manifests/volumes.yaml

# nginx ingress
kubectl apply -f ../manifests/nginx-ingress/mandatory.yaml
kubectl apply -f ../manifests/nginx-ingress/service-l4.yaml
kubectl apply -f ../manifests/nginx-ingress/patch-configmap-l4.yaml

# install noms
kubectl apply -f ../manifests/noms-deployment.yaml
kubectl apply -f ../manifests/noms-service.yaml

# install chaosnode
kubectl apply -f ../manifests/chaosnode-deployment.yaml
kubectl apply -f ../manifests/chaosnode-service.yaml

# get empty-hash
kubectl apply -f ../manifests/empty-hash-get-job.yaml

# initialize tendermint config
initialize_tendermint_config

# make configmaps for tendermint
kubectl apply -f ../manifests/tendermint-config-init.yaml
kubectl create configmap tendermint-config-toml --from-file=../tmp/config/config.toml
kubectl create configmap tendermint-config-genesis --from-file=../tmp/config/genesis.json
kubectl create configmap tendermint-config-priv-validator --from-file=../tmp/config/priv_validator.json 

# install tendermint
kubectl apply -f ../manifests/tendermint-deployment.yaml
kubectl apply -f ../manifests/tendermint-service.yaml

# customize ingress template to make accessible through internet
cp ../manifests/tendermint-ingress.template ../manifests/tendermint-ingress.yaml
sed -i "s/API_DOMAIN/${CLUSTER_NAME}.${PD}/" tendermint-ingress.yaml
kubectl apply -f ../manifests/tendermint-ingress.yaml
rm ../manifests/tendermint-ingress.yaml

# get the address for the elb
get_elb_address

cp cname-update.template cname-update.json
sed -i "s/PARENT_CLUSTER/$PD/" cname-update.json
sed -i "s/ELB_ADDRESS/$elb/" cname-update.json

# get hosted zone for the parent domain
parent_HZ=$(aws route53 list-hosted-zones | jq -r ".HostedZones[] | select(.Name==\"${PD}.\") | .Id")

# give a cname to the hosted zone
aws route53 change-resource-record-sets \
    --hosted-zone-id ${parent_HZ} \
    --change-batch file://cname-update.json

rm cname-update.json # cleanup

