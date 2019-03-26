#!/bin/bash

# get the current directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

release=$1

if [ -z "$release" ]; then
    >&2 echo "Err: no release specified."
    >&2 echo "Usage: $0 devnet-0"
    exit 1
fi

# easy way to get a pod name
pod_name() {
    local release=$1
    local app=$2
    kubectl get pod -l "release=$release,app=nodegroup-$app" -o=jsonpath='{.items[0].metadata.name}'
}

c_noms=$(pod_name "$release" chaos-noms)
n_noms=$(pod_name "$release" ndau-noms)
n_redis=$(pod_name "$release" ndau-redis)
c_redis=$(pod_name "$release" ndau-redis)
c_tm=$(pod_name "$release" chaos-tendermint)
n_tm=$(pod_name "$release" ndau-tendermint)

kubectl cp "$c_noms:/noms" "$DIR/fetches/$release/c-noms" &
kubectl cp "$n_noms:/noms" "$DIR/fetches/$release/n-noms" &
kubectl cp "$c_redis:/redis" "$DIR/fetches/$release/c-redis" &
kubectl cp "$n_redis:/redis" "$DIR/fetches/$release/n-redis" &
kubectl cp "$c_tm:/tendermint" "$DIR/fetches/$release/c-tm" &
kubectl cp "$n_tm:/tendermint" "$DIR/fetches/$release/n-tm"&

wait

>&2 echo "Done"

