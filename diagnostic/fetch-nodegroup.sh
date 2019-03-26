#!/bin/bash

release=$1

if [ -z "$release" ]; then
    echo "no release"
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

kubectl cp "$c_noms:/noms" "./$release/c-noms"
kubectl cp "$n_noms:/noms" "./$release/n-noms"
kubectl cp "$c_redis:/redis" "./$release/c-redis"
kubectl cp "$n_redis:/redis" "./$release/n-redis"
kubectl cp "$c_tm:/tendermint" "./$release/c-tm"
kubectl cp "$n_tm:/tendermint" "./$release/n-tm"

