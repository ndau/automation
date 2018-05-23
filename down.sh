#!/bin/bash

# This script brings up the chaos node in kubernetes.

kubectl delete configmap tendermint-config-genesis
kubectl delete configmap tendermint-config-priv-validator
#kubectl delete configmap tendermint-config-node-key
kubectl delete -f chaosnode-deployment.yaml
kubectl delete -f chaosnode-service.yaml
kubectl delete -f tendermint-deployment.yaml
kubectl delete -f tendermint-service.yaml
