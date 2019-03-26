# Local (minikube) testing and debugging

This guide will help you install minikube on your mac.

## What is minikube?

minikube lets you run a kubernetes cluster on your machine as a single master node. It does so by creating a new linux virtual machine in which it installs and runs `docker` and `kubernetes`. It will also configure `kubectl` to connect to your "minikube cluster". For more info, see https://github.com/kubernetes/minikube.

## Why use minikube?

To shorten dev cycles. The automated deployment process can take time and perform steps that may be irrelevant to your task. minikube is a good environment to test on without having to involve CI or an external kubernetes cluster.

## How do I install it?

First you'll need homebrew for the `brew` command. [Get it here](https://brew.sh/).

Then you'll need `docker` and `minikube`.

```
brew install docker
```

```
brew cask install minikube
```

In order for minikube to spin up a new virtual machine, it needs a hypervisor. [Many are supported](https://github.com/kubernetes/minikube). Assuming you've installed docker for mac and want to use Docker's hypervisor `hyperkit`, you need to install a driver from the minikube repository as per the [instructions here](https://github.com/kubernetes/minikube/blob/master/docs/drivers.md#hyperkit-driver).

The following command `curl`s and executable from google and installs it to `/usr/local/bin`.

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

Other start options exist, and typically you may use something like the following.

```
minikube start \
  --vm-driver=hyperkit \
  --cpus=3 \
  --disk-size=20g \
  --memory=8192 \
  --kubernetes-version v1.10.11
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

You may need to wait a minute for the hello-minikube service to start accepting connections.

The minikube cluster runs its own docker daemon. You can configure your docker client to connect to minikube with `eval $(minikube docker-env)` and build images available to minikube's docker.

If you're interested, you can ssh into the machine and inspect it further with `minikube ssh`.

There is a web ui for a kubernetes cluster that great for seeing things at a glance, but isn't generally good for making changes to your cluster. To run it and connect: `minikube dashboard`.

## Install helm

`helm` is used for templating kubernetes manifests. `gen_node_groups.py` creates helm commands that you can run to install node groups.

`brew install kubernetes-helm`

Helm works by having an application installed on your kubernetes cluster (the helm tiller) that is capible of installing other software. To initialize the tiller on minikube, use the following command.

```
helm init
```

## ECR configuration

Minikube, in it's default configuration will not be able to pull images from ECR. In order to authenticate with ECR, you must configure and enable a minikube addon. The enable step below will be required about as often as the `docker login` command is required.

The configure command bellow will require:

  * AWS credentials (secret key and secret access key).
  * A region. `us-east-1` will do.
  * Our 12 digit aws account id.

```
minikube addons configure registry-creds
minikube addons enable registry-creds
```

Once this is done, the `gen_node_groups.py` script will automatically detect the minikube environment and add the minikube specific setting, which enables `imagePullSecret`s in the helm charts. You should then be able to install like normal with the following command.

```
RELEASE=test ELB_SUBDOMAIN=test ./testnet/gen_node_groups.py 1 30100
```

Please be sure to check that your current `kubectl` context is set to `minikube` by typing: `kubectl config current-context`. If it is not, this will set it, `kubectl config use-context minikube`


# How to...

## port forward

```shell
kubectl get pods # find the pod name you're looking for
kubectl port-forward POD_NAME 46657:46657
```

Use `ctrl+c` to stop port forwarding.

## get logs

To see the logs of one pod

```shell
kubectl get pods # find the pod name you're looking for
kubectl logs POD_NAME -f # -f for follow
```

or you can use kubetail to see both with different colors

```shell
brew tap johanhaleby/kubetail && brew install kubetail
t_pod=$(kubectl get pods --selector=app=tendermint -o json | jq -r ".items[0].metadata.name")
c_pod=$(kubectl get pods --selector=app=ndaunode -o json | jq -r ".items[0].metadata.name")
kubetail $c_pod,$t_pod
```

## Troubleshooting

Sometimes the best thing to do is to blow away minikube and try again. `minikube delete`.

### Debugging our applications

Sometimes it's useful to run a special version of our software that contains, for example, more debugging output. If you simply wish to build docker images from your local commands repo, you can run `./build-docker-images.sh`, which will build docker images for each of the components of our application using our minikube's docker daemon. That means that those images, built with the supplied common image tag, will be accessible to your minikube's kubernetes node without needing to download images from external sources.

This also has the side effect of cache busting the docker images. For example, using the tag `latest` repeatedly across nodegroup installs will now work. Why? Because kubernetes' normal behavior is to fetch images only when they don't already exist in its local docker repo. Consequently, it will never download `latest` from ECR again after the first time, and they will never be overwritten with newer versions of images tagged `latest`. When we build images using minikube's docker, we directly overwrite that `latest` image. So don't worry about bumping your versions to see fresh code changes. Simply rerun `./build-docker-images.sh`.

