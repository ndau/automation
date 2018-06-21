# AWS

This document will detail the cloud environments we deploy to as well as the installation of chaos node.

The clusters that are set up this way are accessible through the `*.cluster.ndau.tech`. That is, `kubectl` will point to that address. The chaos node api itself, however, is accessible through *.ndau.tech.

# tldr;

```
# Check local dependencies
./dev.sh

# Set up a subdomain for clusters, for kubectl access
export CLUSTER_SUBDOMAIN=cluster.ndau.tech
./subdomain.sh

# Set up a cluster at dev-chaos.cluster.ndau.tech in us-east-1
export CLUSTER_NAME=dev-chaos
export REGION=us-east-1
./bootstrap-cluster.sh

# Install app with kubernetes, accessible at rpc.dev-chaos.ndau.tech and p2p.dev-chaos.ndau.tech
export ENDPOINT_SUBDOMAIN=dev-chaos.ndau.tech
./up.sh

# cd to your chaostool
./chaos conf http://rpc.dev-chaos.ndau.tech:80
```

## One Password

install the `op` commandline tool from https://support.1password.com/command-line-getting-started/

Get your signin information from your 1password emergency kit and use `op` to sign in.

```
op signin https://oneiro.1password.com your.name@oneiro.io <secret-key>
```

Then you'll be able to sign in with this command

```
eval $(op signin oneiro)
```

# KOPS

_Kubernetes OPerationS._ Kops is a tool that automates setting up a cluster on AWS.

These permissions need to be given to the user
AmazonEC2FullAccess, AmazonRoute53FullAccess, AmazonS3FullAccess,IAMFullAccess, AmazonVPCFullAccess, autoscalling:*

