#!/bin/bash

# This script removes everything that was insallted in kubernetes.

kubectl delete -f manifests/tendermint-config-init.yaml
kubectl delete configmap tendermint-config-genesis
kubectl delete configmap tendermint-config-priv-validator
kubectl delete configmap tendermint-config-toml
kubectl delete -f manifests/chaosnode-deployment.yaml
kubectl delete -f manifests/chaosnode-service.yaml
kubectl delete -f manifests/tendermint-deployment.yaml
kubectl delete -f manifests/tendermint-service.yaml
kubectl delete -f manifests/noms-deployment.yaml
kubectl delete -f manifests/noms-service.yaml

# This should be gone already, but just incase it isn't.
kubectl delete -f manifests/empty-hash-get-job.yaml 2>/dev/null

# This will delete the volumes, which might not be what you want.
kubectl delete -f manifests/volumes.yaml 2>/dev/null

kubectl delete -f manifests/tendermint-ingress.yaml

exit 0
