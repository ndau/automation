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

# Deploying to MainNet

This section will assume an AWS environment as set up using the AWS environment specific install instructions.

## Requirements

### Tools

The following must be present to install nodegroups.
  * `python3` - A script (`gen_node_groups.py`), is used that will create a some configuration and issue commands to install the nodegroup or series of nodegroups.
  * `brew` - Used to install a single nodegroup with configuration options.
  * `kubectl` - Used by brew to communicate with kubernetes.

### Security keys

`1password` contains a document `deploy security`. It is a `tgz` file that contains a directory that is a git repo.

There are two folders in the repo `/helm` and `/kubectl`. They each contain security certificates for communicating with our kubernetes cluster securely. The `/helm/main` directory contains the certificates for our MainNet cluster, and can be copied to your default helm config location with the following commands:

```
cp helm/main/ca.cert.pem $(helm home)/ca.pem
cp helm/main/helm.cert.pem $(helm home)/cert.pem
cp helm/main/helm.key.pem $(helm home)/key.pem
```

The kubectl config is a little more flexible and detailed in `/kubectl/readme.md`, but for simply communicating with MainNet, the following command will copy the relevent config file to `kubectl` config location.

```
cp kubectl/dev.yaml $HOME/.kube/config
```

## Tasks

Once you have those config files in place. You will use the `automation/testnet/gen_node_groups.py` script to install a set of nodegroups.


In the simplest case you can install with the following command.

```
RELEASE=my-mainnet ELB_SUBDOMAIN=api.ndau.tech ./testnet/gen_node_groups.py 5 30000
```

* `ELB_SUBDOMAIN` must match what has already been configured as the subdomain for the traefik load balancer. See `automation/env/aws/readme.md` and `automation/env/aws/traefik.sh` for more information.
* `RELEASE` is a name that will be used internally, as well as the basis for names generated with `gen_node_groups.py` for the `ndauapi`. In this example the ndauapi will be available at the following urls: `my-mainnet-0.api.ndau.tech`, `my-mainnet-1.api.ndau.tech`, `my-mainnet-2.api.ndau.tech`, `my-mainnet-3.api.ndau.tech`, `my-mainnet-4.api.ndau.tech`.
* The argument 5, specifies how many nodegroups to create.
* The argument 30000 is the starting port number. This number is used to sequentially assign ports to Tendermint's P2P and RPC ports for each nodegroup. Note: if you are installing more than one set of nodegroups, care will have to be taken to ensure the allocated ports do not overlap. The acceptible range is a kubernetes' default of `30000`-`32767`.


Under the hood, the script will use the ECR images from the most recent master build of each dependency (`chaosnode`, `ndaunode`, etc.).

For detailed information about each configuration option, please see the comments in `gen_node_groups.py`.

You can now use `kubectl get pods` to see the readiness of the set of nodegroups.

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

#### Chart

This is the basic unit that you work with in Helm. A helm chart, is a template with default values saved in `values.yaml`. They may be overriden at install time.

#### Release

A release is a specific install of a helm chart.

#### Tiller

Helm is a client/server pair of applications. To begin using helm, the tiller must be installed on the cluster with `helm init`. This uses the current `kubectl` context. The tiller is installed just like any other kubernetes application but it has the privileges to install and modify kubernetes resources.

#### Security

For a helm security overview. Look to 1password for `dev-chaos-helm-tiller-certs.zip` which contains documentation on authorization and usage of our dev cluster.

# Resources

Jumping into kubernetes is really confusing and bewildering and can make anyone question their choices in life. Generally you have a program that accepts input and gives useful output, where it gthen you add layers and layers of abstraction until you start questioning what a boolean value "really means". It can be helpful to only think of one layer at a time. And when in doubt, just ask. There are no stupid questions :)

http://kubernetesbyexample.com - in the vein of gobyexample.com another great learning resource.
https://www.katacoda.com/courses/kubernetes - interactive browser-based courses.
https://github.com/Praqma/LearnKubernetes/blob/master/kamran/Kubernetes-kubectl-cheat-sheet.md - Nice cheatsheet for kubectl commands.
https://kubernetes.io/docs/reference/kubectl/cheatsheet - Official cheatsheet.
