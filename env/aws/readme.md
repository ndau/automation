# AWS

This document will detail the cloud environments we deploy to as well as the installation of chaos node.

The clusters that are set up this way are accessible through the `*.cluster.ndau.tech`. That is, `kubectl` will point to that address. The chaos node api itself, however, is accessible through *.ndau.tech. 

# tldr;

```
./dev.sh

export SD=cluster.ndau.tech
./subdomain.sh

export CLUSTER_NAME=dev
export REGION=us-east-1
./bootstrap-cluster.sh

./up.sh

# cd to your chaostool

./chaos conf http://dev.ndau.tech:80
```

# KOPS

_Kubernetes OPerationS._ Kops is a tool that automates setting up a cluster on AWS.

These permissions need to be given to the user 
AmazonEC2FullAccess, AmazonRoute53FullAccess, AmazonS3FullAccess,IAMFullAccess, AmazonVPCFullAccess, autoscalling:*

