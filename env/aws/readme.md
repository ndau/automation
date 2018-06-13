# AWS

This document will detail the cloud environments we deploy to as well as the installation of chaos node.

The clusters that are set up this way are accessible through the `*.cluster.ndau.tech`. That is, `kubectl` will point to that address. The chaos node api itself, however, is accessible through *.ndau.tech.

# tldr;

```
# Check local dependencies
./dev.sh

# Set up a subdomain
export SUBDOMAIN=cluster.ndau.tech
./subdomain.sh

# Set up a cluster at dev.cluster.ndau.tech in us-east-1
export CLUSTER_NAME=dev
export REGION=us-east-1
./bootstrap-cluster.sh

# Install app with kubernetes
export ENDPOINT_DOMAIN=dev-chaos.ndau.tech
./up.sh

# cd to your chaostool

./chaos conf https://dev.ndau.tech:80
```

# KOPS

_Kubernetes OPerationS._ Kops is a tool that automates setting up a cluster on AWS.

These permissions need to be given to the user
AmazonEC2FullAccess, AmazonRoute53FullAccess, AmazonS3FullAccess,IAMFullAccess, AmazonVPCFullAccess, autoscalling:*

