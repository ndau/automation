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
