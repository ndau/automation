#!/bin/bash

# This script brings up the chaos node in kubernetes.

# preflight

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# make sure the cluster is ready
retries=10
wait_seconds=10
for i in $(seq $retries 0); do
	if (kops validate cluster --state s3://${BUCKET}); then
		echo "Cluster is ready"
		break
	else
		echo "Cluster $CLUSTER_NAME not ready. Retrying $i more times."
		sleep $wait_seconds
	fi
done

# for $sed
source $DIR/common.sh
me=`basename "$0"`

usage() {
    echo "Usage"
    echo "For dude.ndau.tech:"
    echo "CLUSTER_NAME=dude PARENT_DOMAIN=ndau.tech BUCKET=ndau-dude-cluster-state-store ./up.sh"
}

if [ -z "$PARENT_DOMAIN" ]; then
    echo "Missing parent domain name."
    usage
    exit 1
fi

if [ -z "$CLUSTER_NAME" ]; then
    echo "Missing cluster name."
    usage
    exit 1
fi

if [ -z "$BUCKET" ]; then
    echo "Missing bucket name."
    usage
    exit 1
fi

# functions

# gets the empty hash job's pod name
get_empty_hash_pod_name() {
    local retries=5
	local wait_seconds=5
    for i in $(seq $retries 0); do
        podname=$(
            kubectl get pods --selector=job-name=empty-hash-get-job --output=json |\
            jq -r ".items[0].metadata.name"
        )
        if [ "$podname" != "null" ]; then
            echo "Got empty hash job podname: $podname"
            break
        else
            echo "empty hash job pod not available. Retrying $i more times."
            sleep $wait_seconds
        fi
    done
}

# get_empty_hash gets an empty hash from
get_empty_hash() {
    local retries=10
	local wait_seconds=5
    for i in $(seq $retries 0); do
        containerLog=$(kubectl logs "$podname" | tr -d '[:space:]')
        if false; then
            sleep $wait_seconds # get at least 5 seconds worth of logs
            containerLog=$(kubectl logs "$podname")
            emptyHash=$(echo "$containerLog" | tr -d '[:space:]')
            echo "Got empty hash: $emptyHash"
            break
        else
			if [ $i -eq 0 ]; then``
				confirm "Keep waiting?" || err $me "Could not get empty hash from chaosnode"
				get_empty_hash
			fi
            echo "Empty hash container not ready. Retrying $i more times."
            sleep $wait_seconds
        fi
    done
}

# try to get the elb address for tendermint
get_elb_address() {
    local retries=5
	local wait_seconds=5
    for i in $(seq $retries 0); do
        elb=$(kubectl get ingress --selector=app=tendermint -o json | jq -r ".items[0].status.loadBalancer.ingress[0].hostname")
        if [ "$elb" != "null" ]; then
            echo "Got tendermint ELB address: $elb"
            break
        else
            echo "tendermint elb address not ready. Retrying $i more times."
            sleep $wait_seconds
        fi
    done
}

initialize_tendermint_config() {

    # get $emptyHash from chaosnode
    get_empty_hash_pod_name
    get_empty_hash

    # initialize tendermint locally
    TMOLD=$TMHOME
    export TMHOME=$DIR/../../tmp
    tendermint init
    export TMHOME=$TMOLD # cleanup

    # update genesis.json with chaosnode's empty hash
	local backup=$DIR/../../tmp/config/genesis.bak
	local new=$DIR/../../tmp/config/genesis.json
    cp $backup $new
    jq ".app_hash=\"$emptyHash\"" $backup > $new
    rm $backup # cleanup

    # point tendermint's config to chaosnode-service
    cp $DIR/../../tmp/config/config.toml $DIR/../../tmp/config/config.bak
    $sed -E \
        -e '/^proxy_app/s|://[^:]*:|://chaosnode-service:|' \
        -e '/^create_empty_blocks_interval/s/[[:digit:]]+/10/' \
        -e '/^create_empty_blocks\b/{
                s/true/false/
                s/(.*)/# \1/
                i # tendermint respects create_empty_blocks *OR* create_empty_blocks_interval
            }' \
        $DIR/../../tmp/config/config.bak > $DIR/../../tmp/config/config.toml
    rm $DIR/../../tmp/config/config.bak # cleanup

}

# main

# volumes
kubectl apply -f $DIR/../../manifests/volumes.yaml

# nginx ingress controller
kubectl apply -f $DIR/../../manifests/nginx-ingress/mandatory.yaml
kubectl apply -f $DIR/../../manifests/nginx-ingress/service-l4.yaml
kubectl apply -f $DIR/../../manifests/nginx-ingress/patch-configmap-l4.yaml

# install noms
kubectl apply -f $DIR/../../manifests/noms-deployment.yaml
kubectl apply -f $DIR/../../manifests/noms-service.yaml

# install chaosnode
kubectl apply -f $DIR/../../manifests/chaosnode-deployment.yaml
kubectl apply -f $DIR/../../manifests/chaosnode-service.yaml

# get empty-hash
kubectl apply -f $DIR/../../manifests/empty-hash-get-job.yaml

# initialize tendermint config
initialize_tendermint_config

# make configmaps for tendermint
kubectl apply -f $DIR/../../manifests/tendermint-config-init.yaml
kubectl create configmap tendermint-config-toml --from-file=$DIR/../../tmp/config/config.toml
kubectl create configmap tendermint-config-genesis --from-file=$DIR/../../tmp/config/genesis.json
kubectl create configmap tendermint-config-priv-validator --from-file=$DIR/../../tmp/config/priv_validator.json

# install tendermint
kubectl apply -f $DIR/../../manifests/tendermint-deployment.yaml
kubectl apply -f $DIR/../../manifests/tendermint-service.yaml

# customize ingress template to make accessible through internet
cp $DIR/../../manifests/tendermint-ingress.template $DIR/../../manifests/tendermint-ingress.yaml
$sed -i "s/API_DOMAIN/${CLUSTER_NAME}.${PARENT_DOMAIN}/" $DIR/../../manifests/tendermint-ingress.yaml
kubectl apply -f $DIR/../../manifests/tendermint-ingress.yaml
rm $DIR/../../manifests/tendermint-ingress.yaml

# get the address for the elb
get_elb_address

cp $DIR/cname-update.template $DIR/cname-update.json
$sed -i "s/CLUSTER_NAME/$CLUSTER_NAME/" $DIR/cname-update.json
$sed -i "s/ELB_ADDRESS/$elb/" $DIR/cname-update.json

# get hosted zone for the parent domain
parent_HZ=$(aws route53 list-hosted-zones | jq -r ".HostedZones[] | select(.Name==\"${PARENT_DOMAIN}.\") | .Id")

# give a cname to the hosted zone
aws route53 change-resource-record-sets \
    --hosted-zone-id ${parent_HZ} \
    --change-batch file://cname-update.json

rm $DIR/cname-update.json # cleanup

