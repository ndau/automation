#!/bin/bash

# install dependencies
./dev.sh

# build images
./build.sh

# install in minikube
./up.sh

# get the tendermint pod name
pod_name=$(kubectl get pods --selector=app=tendermint -o json | jq -r ".items[0].metadata.name")

# port forward
kubectl port-forward $pod_name 46657:46657 &

# stream the tendermint log to stdout
kubectl logs $pod_name -f
