# Kubernetes

This repo is for material related to kubernetes deployments.

## Environments

In order to deploy the chaos or ndau nodes, you first need to have a running kubernetes cluster.

* [AWS](./env/aws/readme.md)
* [Local (minikube)](./env/local/readme.md)

## Installation

Once `helm` and `kubectl` are configured, it's really quite easy. (see below for instructions)

```
helm install helm/chaosnode --name my-chaos-node --tls
```

```
helm install helm/ndaunode --name my-ndau-node --tls
```

The output of those commands will provide details about how to connect to those nodes.

### Requirements

#### kubectl

`brew install kubectl`

kubectl is a command line tool that is the main way to interact with k8s. It makes http calls to a k8s cluster. It can be used to `apply` manifest files to a kubernetes cluster, which commands kubernetes to bring up containers and associated resources.

It's a good idea to add kubectl to your aliases. `alias k=kubectl`

##### Configuration

The configuration for kubectl is in located in `~/.kube/config`. The two most important peices of information are the `user` and the `cluster`. A `context` is a combination of a `user` and `cluster`. When minikube is installed it will automatically configure kubectl to connect to it.

The configuration and instructions for any clusters that already exist can be found on 1password.

#### helm

`helm` will allow you to install `charts` instead of kubernetes manifest files. helm is configured to access your kubernetes cluster securely through certificates. The certificates themselves and more information are stored in 1password. `helm` uses some of the configuration of `kubectl` and so that needs to be set up first.

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
