# Local (minikube) testing

This guide will help you install minikube on your local machine.

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

The minikube cluster runs its own docker server. You can configure your docker client to connect to minikube with `eval $(minikube docker-env)` and build images available to minikube's docker.

If you're interested, you can ssh into the machine and inspect it further with `minikube ssh`.

There is a web ui for a kubernetes cluster that great for seeing things at a glance, but isn't generally good for making changes to your cluster. To run it and connect: `minikube dashboard`.

## Minikube port forwarding

```shell
kubectl get pods # find the pod name you're looking for
kubectl port-forward POD_NAME 46657:46657
```

Use `ctrl+c` to stop port forwarding.

## Logs

To see the logs of one pod

```shell
kubectl get pods # find the pod name you're looking for
kubectl logs POD_NAME -f # -f for follow
```

or you can use kubetail to see both with different colors

```shell
brew tap johanhaleby/kubetail && brew install kubetail
t_pod=$(kubectl get pods --selector=app=tendermint -o json | jq -r ".items[0].metadata.name")
c_pod=$(kubectl get pods --selector=app=chaosnode -o json | jq -r ".items[0].metadata.name")
kubetail $c_pod,$t_pod
```

## Troubleshooting

Sometimes the best thing to do is to blow away minikube and try again. `minikube delete`.

## Integration testing

To bring up a test net locally with minikube for integration testing.  

*The following steps will not check out any new code. This will build whatever version you currently have in `$GOPATH/src/github.com/oneiro-ndev/chaos`.*

### Requirements
You can run `env/local/dev.sh` or you can install the following manually. *Note: `dev.sh` will not upgrade for you.*

```
brew cask install minikube
brew install kubectl
brew install kubernetes-helm
# The following will install minikube's docker hypervisor
curl -LO https://storage.googleapis.com/minikube/releases/latest/docker-machine-driver-hyperkit \
&& chmod +x docker-machine-driver-hyperkit \
&& sudo mv docker-machine-driver-hyperkit /usr/local/bin/ \
&& sudo chown root:wheel /usr/local/bin/docker-machine-driver-hyperkit \
&& sudo chmod u+s /usr/local/bin/docker-machine-driver-hyperkit
```

1. Start minikube
```
minikube start --vm-driver=hyperkit --disk-size=10g
```
2. Connect docker-cli to minikube
```
eval $(minikube docker-env)
```
3. Build the images to be tested
```
chaos_dir=$GOPATH/src/github.com/oneiro-ndev/chaos
git_sha=$(cd $chaos_dir; git rev-parse --short HEAD)
# build chaosnode
docker build -f "${chaos_dir}/Dockerfile" "$chaos_dir" -t chaos:${git_sha}
# build tendermint
docker build -f "${chaos_dir}/tm-docker/Dockerfile" "$chaos_dir/tm-docker" -t tendermint:latest
# build noms
docker build -f "${chaos_dir}/noms-docker/Dockerfile" "$chaos_dir/noms-docker" -t noms:latest
# build helper image
docker build -f "./docker-images/deploy-utils.docker" "./docker-images" -t deploy-utils:latest
```
4. Install the helm tiller
```
helm init
```
5. install the testnet
```
VERSION_TAG=${git_sha} ./testnet/chaos.js 30000 castor pollux
```

At this point you'll have to wait a little while until everything is running. You can type `kubectl get pods` to see if everything has a `RUNNING` status.

Since we used a script to install the nodes, we didn't see the output from the helm charts. You can still view them however and get a few little helpful commands by running the comand `helm status pollux` or `helm status castor`.