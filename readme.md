# k-os

## Chaos node on Kubernetes

This repo is for all things related to getting a Chaos node up and running.

## tldr;

1. Copy `gomu` to this project's root.
2. Pick your target environment by setting an environment variable.

```shell
k8s_target=aws
# or
k8s_target=local
```

If you're going with `aws`, please also set the following environment variables to something like the following:

_For more info, see [AWS specific readme](./env/aws/readme.md)._

```
# This will set up a subdomain at cluster.ndau.tech
# and a k8s cluster at dev-chaos.cluster.ndau.tech
# with tendermint accessible from dev-chaos.ndau.tech
# in region us-east-1, availability zone us-east-1b
export SUBDOMAIN=cluster.ndau.tech
export CLUSTER_NAME=dev-chaos
export ENDPOINT_DOMAIN=dev-chaos.ndau.tech
export REGION=us-east-1
export AZ=us-east-1b
```

And then

```shell
./env/$k8s_target/quickstart.sh
```

## Minikube port forwarding

```shell
pod_name=$(kubectl get pods --selector=app=tendermint -o json | jq -r ".items[0].metadata.name")
kubectl port-forward $pod_name 46657:46657
```

Use `ctrl+c` to stop port forwarding.

## Logs

To see the logs of one pod

```shell
pod_name=$(kubectl get pods --selector=app=tendermint -o json | jq -r ".items[0].metadata.name")
kubectl logs $pod_name -f # -f for follow
```

or you can use kubetail to see both with different colors

```shell
brew tap johanhaleby/kubetail && brew install kubetail
t_pod=$(kubectl get pods --selector=app=tendermint -o json | jq -r ".items[0].metadata.name")
c_pod=$(kubectl get pods --selector=app=chaosnode -o json | jq -r ".items[0].metadata.name")
kubetail $c_pod,$t_pod
```

## Machine requirements

You can follow the steps bellow or run `./dev.sh` to check for and/or install dependencies.

### kubectl

`brew install kubectl`

kubectl is a commandline tool that is the main way to interact with k8s. It makes http calls to a k8s cluster. It can be used to `apply` manifest files to a kubernetes cluster, which commands kubernetes to bring up containers and associated resources.

It's a good idea to add kubectl to your aliases. `alias k=kubectl`

#### Configuration

The configuration for kubectl is in located in `~/.kube/config`. The two most important peices of information are the `user` and the `cluster`. A `context` is a combination of a `user` and `cluster`. When minikube is installed it will automatically configure kubectl to connect to it.


### minikube (for local testing)

`brew install minikube`

minikube lets you run a kubernetes cluster on your machine as a single master node. It does so by running a kubernetes server in a linux VM and automatically configuring kubectl to connect to it. For more info, see https://github.com/kubernetes/minikube.

In order for minikube to spin up a new VM, it needs a hypervisor, [many are supported](https://github.com/kubernetes/minikube). Assuming you've installed docker for mac and want to use Docker's hypervisor `hyperkit`, you need to install a driver from the minikube repository as per the [instructions here](https://github.com/kubernetes/minikube/blob/master/docs/drivers.md#hyperkit-driver).

```
curl -LO https://storage.googleapis.com/minikube/releases/latest/docker-machine-driver-hyperkit \
&& chmod +x docker-machine-driver-hyperkit \
&& sudo mv docker-machine-driver-hyperkit /usr/local/bin/ \
&& sudo chown root:wheel /usr/local/bin/docker-machine-driver-hyperkit \
&& sudo chmod u+s /usr/local/bin/docker-machine-driver-hyperkit
```

Once minikube and hyperkit are installed, you can start your local cluster with the following command

```
minikube start --vm-driver=hyperkit
```

If that all worked, you'll have a single node cluster running on your machine. You can test it with a simple echo service.

```
# download an image from google and run it as a deployment
kubectl run hello-minikube --image=k8s.gcr.io/echoserver:1.4 --port=8080

# create a service for that deployment
kubectl expose deployment hello-minikube --type=NodePort

# curl the address minikube gives you for that service
curl $(minikube service hello-minikube --url)
```

The minikube cluster runs its own docker server. You can configure your docker client to connect to minikube with `eval $(minikube docker-env)` and build images available to the docker, which we'll be doing later.

If you're interested, you can ssh into the machine and inspect it further with `minikube ssh`.

There is a web ui for a kubernetes cluster that great for seeing things at a glance, but isn't generally good for making changes to your cluster. To run it and connect: `minikube dashboard`.

# Philosophy

This set of scripts tries to follow a 12 factor approach as much as possible for a set of scripts.

# Glossary

This section is provided as a way to have a common grasp on terms and technologies we use.

## Kubernetes

Kubernetes is a container orchestration platform. Kubernetes means _helmsman_ in ancient Greek, hence the helm logo. It allows you to specify how containers and resources should be managed.

### Node

A node is a computer or VM that is running an installation of Kubernetes. It can be a master node or it can be a slave node.

### Cluster

A bunch of nodes.

### Pod
A pod is an abstraction of a container or group of containers. Docker containers are whales. A pod can be understood as a stateless program that will handle a request on some specified port. A pod may consist of multiple containers, each listening on different ports.

### Deployment

A deployment is a way of specifying the desired state of a `pod` and `replica set`, which typically means you specify a `pod` spec and how many replicas should run.

### Service

A `service` specifies which ports to make available from each `pod`.

### Volume

Volumes connect pods to storage. They get mounted within the container's file system. They are destroyed when the `pod` is destroyed.

### PersistentVolume

`PersistentVolumes` have lifecycles that are independent from a `pod`'s lifecycle.

### PersistentVolumeClaim

A request for storage from a `PersistentVolume`.

### Namespace

All `kubectl` commands run within a `namespace`. The default `namespace` is configured in `~/.kube/config`.

### Labels

Everything in kubernetes has a set of key-value pairs called `labels`. They're how a `service` knows which `pod` to select, for example.

### `kubectl`

`kubectl` (pronounced "cube control" or "cube cuttle") is the primary way of interacting with kubernetes.

## Docker

Docker is a set of tools that make it easier to use containers or cgroups. On non-linux machines docker uses a virtual machine to take advantage of cgroups. The docker commandline tool sends commands to the virtual machine, which means the docker commandline tool can be configured to connect to docker daemons running on another machine, such as minikube.

### Dockerfile

Dockerfiles are used to create docker images. They provide a starting point (e.g. alpine, scratch, ubuntu) and save the state of the machine after commands are run.

### Image

An image is the state of a machine that is created using Dockerfiles. When an image is running it is called a container.

### Container

A sandboxed environment that runs an image, usually a lightweight process that accepts http requests. A container is created when an image is run (e.g. `docker run postgres`). Container memory and storage are destroyed when the container is stopped. External non-volatile storage may be added with `volumes`.

### Helm

Helm is a kubernetes templateing engine that assists with deployment. YAML files for Kubernetes manifests are great, but if you need to share values or provide configuration, a set of static YAML files can be difficult to work with. Helm packages kubernetes manifests into a single tarball that can be applied to a cluster while overriding default values as necessary.

# Resources

Jumping into kubernetes is really confusing and bewildering and can make anyone question their choices in life. Generally you have a program that accepts input and gives useful output, where it gthen you add layers and layers of abstraction until you start questioning what a boolean value "really means". It can be helpful to only think of one layer at a time. And when in doubt, just ask. There are no stupid questions :)

http://kubernetesbyexample.com - in the vein of gobyexample.com another great learning resource.
https://www.katacoda.com/courses/kubernetes - interactive browser-based courses.
https://github.com/Praqma/LearnKubernetes/blob/master/kamran/Kubernetes-kubectl-cheat-sheet.md - Nice cheatsheet for kubectl commands.
https://kubernetes.io/docs/reference/kubectl/cheatsheet - Official cheatsheet.
