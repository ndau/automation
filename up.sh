#!/bin/bash

# This script brings up the chaos node in kubernetes.

kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f noms-deployment.yaml
kubectl apply -f noms-service.yaml
