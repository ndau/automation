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
```

This will create a new set of files in `~/.kube/config` which will contain certificates allowing you to connect to your cluster.

## KOPS

_Kubernetes OPerationS._ Kops is a tool that automates setting up a cluster on AWS.

These permissions need to be given to the user currently logged in with `aws-cli`
AmazonEC2FullAccess, AmazonRoute53FullAccess, AmazonS3FullAccess,IAMFullAccess, AmazonVPCFullAccess, autoscalling:*

# Cluster's instance group settings

There are two scipts that are run on each EC2 machine in the cluster when it starts. They are located in [./cluster-spec.json](./cluster-spec.json) and run automatically when the machine boots.

## inodes

Noms uses many files. It's best to have a large number of inodes available so noms doesn't run out. In order to do this, we change the default formatting settings in `/etc/mke2fs.conf`.


## Transparent Huge Pages (THP)

THP is a memory optimization that can cause poor or leaky performance in Redis and applications that have sparse disk access patterns.

It runs the following commands to disable THP for all containers running on the node.

```
sudo sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
sudo sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'
```

# Troubleshooting KOPS

For some reason when upgrading there can be a tendency for KOPS to forget which image to use for a given node's operating system.

## Traefik

For any services that use ingresses, Traefik is used as a load balancer/gateway.

`./traefik.sh` is used to install Traefik to the currently selected cluster.

The following command will install traefik, provision an ELB and register a CNAME under `*.api.ndau.tech`. This gives Traefik the ability to route traffic from any sub subdomain and path that might be specified later on (e.g. node-1.api.ndau.tech, nodes.api.ndau.tech/mario/status, etc.).

The command also provides an email address which is used for registering with Let's Encrypt. The `RELEASE_NAME` is a requirement for the installation using helm.

```
EMAIL=person@place.com RELEASE_NAME=ndau-traefik ELB_DOMAIN=api.ndau.tech ./traefik.sh
```

## Monitoring

Basic cluster monitoring is available through [Prometheus](https://prometheus.io/) and [Grafana](https://grafana.com/).

To install run the following command:

```
./env/aws/monitoring.sh
```

It will also install the [kubernetes app](https://grafana.com/plugins/grafana-kubernetes-app) for grafana with a basic dashboard.

At the end of installation, instructions for connecting and viewing should appear.
