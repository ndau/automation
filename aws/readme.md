# AWS

This document will detail the cloud environments we deploy to as well as the installation of chaosnode.

# tldr;

```
export SD=cluster.ndau.tech
export PD=ndau.tech
./subdomain.sh

export CLUSTER_NAME=dev.cluster.ndau.tech
export BUCKET=ndau-dev-cluster-state-store
./bootstrap.sh

./build.sh

./up.sh
```

# KOPS

_Kubernetes OPerationS._ Kops is a tool that automates setting up a cluster on AWS.

These permissions need to be given to the user 
AmazonEC2FullAccess, AmazonRoute53FullAccess, AmazonS3FullAccess,IAMFullAccess, AmazonVPCFullAccess, autoscalling:*

