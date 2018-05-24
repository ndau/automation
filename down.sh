#!/bin/bash

# This script removes everything that was insallted in kubernetes.

kubectl delete -f tendermint-config-init.yaml
kubectl delete configmap tendermint-config-genesis
kubectl delete configmap tendermint-config-priv-validator
kubectl delete configmap tendermint-config-toml
kubectl delete -f chaosnode-deployment.yaml
kubectl delete -f chaosnode-service.yaml
kubectl delete -f tendermint-deployment.yaml
kubectl delete -f tendermint-service.yaml
kubectl delete -f noms-deployment.yaml
kubectl delete -f noms-service.yaml

# This should be gone already, but just incase it isn't.
kubectl delete -f empty-hash-get-job.yaml

exit 0
