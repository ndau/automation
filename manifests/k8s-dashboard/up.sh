#!/bin/bash

# create a new role for dashboard auth
kubectl apply -f service-account.yaml

# create the dashboard
kubectl apply -f kubernetes-dashboard.yaml

echo "Waiting a few seconds..."
sleep 5

# Get the token for logging in
kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep admin-user | awk '{print $1}')

# Start port forwarding
kubectl proxy