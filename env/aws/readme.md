# AWS

This document will detail the cloud environments we deploy to as well as the installation of chaos and ndau nodes.

The clusters that are set up this way are accessible through the `*.cluster.ndau.tech`. That is, `kubectl` will point to that address. The chaos node api itself, however, is accessible through the ip address of any of the node machines `kubectl get nodes -o wide`. The configured p2p and rpc ports will allow you to connect to either tendermint endpoint.

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
export AZ=us-east-1b
./bootstrap-cluster.sh

# Install a chaosnode
helm install --name chaos-one ../../helm/chaos \
    --set p2pPort=30500 \
    --set rpcPort=30501 \
    --set tendermint.moniker=chaos-one \
    --tls

# Install an ndaunode
helm install --name ndau-one ../../helm/ndau \
    --set p2pPort=30600 \
    --set rpcPort=30601 \
    --set tendermint.moniker=ndau-one \
    --tls

```

## One Password

One password has a command-line tool, `op`, for interacting with the secure things stored in your 1password vaults. It is used in the aws scripts to retrieve AWS credentials from a secure document.

### Install one password

Install and verify `op` from https://support.1password.com/command-line-getting-started/

Get your signin information from your 1password emergency kit and use `op` to sign in.

```
op signin https://oneiro.1password.com your.name@oneiro.io <secret-key>
```

Then you'll be able to sign in with this command

```
eval $(op signin oneiro)
```

## KOPS

_Kubernetes OPerationS._ Kops is a tool that automates setting up a cluster on AWS.

These permissions need to be given to the user currently logged in with `aws-cli`
AmazonEC2FullAccess, AmazonRoute53FullAccess, AmazonS3FullAccess,IAMFullAccess, AmazonVPCFullAccess, autoscalling:*

## Monitoring

Basic cluster monitoring is available through [Prometheus](https://prometheus.io/) and [Grafana](https://grafana.com/).

To install run the following command:

```
./env/aws/monitoring.sh
```

It will also install the [kubernetes app](https://grafana.com/plugins/grafana-kubernetes-app) for grafana with a basic dashboard.

At the end of installation, instructions for connecting and viewing should appear.
