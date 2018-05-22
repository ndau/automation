#!/bin/bash

# This script brings up the chaos node in kubernetes.

kubectl delete -f deployment.yaml
kubectl delete -f service.yaml
kubectl delete -f noms-deployment.yaml
kubectl delete -f noms-service.yaml
