
# Multinode test nets

This document contains information regarding the design and operation of the multinode test nets on kubernetes.

## Design

chaos/ndau nodes can be deployed with helm, using the helm charts provided in this repo. For the case of multiple nodes, scripts are used that generate the initial configuration. The actual generation is done by Tendermint, which is accessed via docker. The dockerized version is removes the local dependency for the correct version of Tendermint by using the same thing the testnet will use. The initial configuration is passed to the helm chart of each node, overriding the default values. Once the chaos/ndau node is running, their Tendermint configurations enable communication as validator nodes.

## Installation

The script `gen_node_groups.py` require python 3.x to execute. It sets up a multiple node test net in kubernetes.

The script uses `docker`, `kubectl` and `helm`. kubectl must be configured to authenticate and set to use a cluster of your chosing, as all commands executed by these scripts will go through helm and kubectl. Docker is used to generate configuration files.

The required settings are RELEASE, ELB_SUBDOMAIN, a node number, and a starting port number.

```
RELEASE=test ELB_SUBDOMAIN=api.ndau.tech ./gen_node_groups.py 2 30004
```

The above script installs the # of node groups given by the number arg (in this case 2), `test-0` and `test-1`. By default it uses port `30000` as a base port and increments from there, unless you give it a different port to start with as the 2nd arg. That is, it will use `30000` for test-0's chaos `p2p` port, then `30001` for test-0's chaos `rpc` port, `30002` for test-0's ndau `p2p` port, then `30003` for test-0's ndau `rpc` port. test-1 will get `30004` through `30007` respectively.

The docker image tags are gathered automatically from the commands repo and ECR. You may specify image tags for Noms, Tendermint, chaosnode, ndaunode, or the commands repo. If you specify `COMMANDS_TAG`, then that gets applied to chaosnode, ndaunode, and ndauapi. Give their close relationship, ndauapi always uses ndaunode's tag.

Although they are usually the same, noms and tendermint tags can be specified separately with `NDAU_TM_TAG`, `NDAU_NOMS_TAG`, etc. See `gen_node_groups.py` for a complete list.

## Changing the install

Updating or otherwise altering the installation of the test net can be done easily using the helm charts provided.

The default values for all options are in each chart folder's `values.yaml`. These are applied automatically and overriden with the commandline.

For example, to change an installed image:

```
helm upgrade ganymede ../../../helm/chaosnode \
  --set tendermint.image.tag=abcdef1 \
  --reuse-values \
  --tls
```

* `upgrade` means we intend to change an existing release.
* `ganymede` is the release name.
* `../../../helm/chaosnode` is the location of the helm chart.
* `--set tendermint.image.tag=0.21` override this value in `values.yaml`.
* `--reuse-values` means we will use all the values from the previous release, with the exception of what's specified here with `--set`.
* `--tls` use tls authentication.

For the case of changing the persistent peers addresses, it is only slightly more complicated.

1. The addresses must be base64 encoded.
2. The additional property `updatePeerAddresses` must be set to `true`.
3. Use the `--recreate-pods` option.

So all together that looks like:

```
helm upgrade ganymede ../../../helm/chaosnode \
  --reuse-values \
  --set updatePersistentPeers=true \
  --set persistentPeers=NC40LjQuNDozMDY2Niw0LjQuNC40OjMwNjY3LDQuNC40LjQ6MzA2NjgK \
  --tls
```

Caveat ingeniator: because we use the `--reuse-values` option, you must take care to set this to false, for the very next change. It is recommended that you create another dummy release, immediately after updating the peers, simply to return this value to false.

## Continuous delivery

Once the test nets are in place helm is the easiest way to upgrade a release is to execute the following command after a successful build and push to ecr:

```
helm upgrade ganymede ../../../helm/chaosnode \
  --set chaosnode.image.tag=9.0.0 \
  --reuse-values \
  --recreate-pods \
  --tls
```
