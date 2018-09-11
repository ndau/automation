[![js-standard-style](https://cdn.rawgit.com/standard/standard/master/badge.svg)](http://standardjs.com)

# Multinode test nets

This document contains information regarding the design and operation of the multinode test nets on kubernetes.

## Design

chaos/ndau nodes can be deployed with helm, using the helm charts provided in this repo. For the case of multiple nodes, scripts are used that generate the initial configuration. The actual generation is done by Tendermint, which is accessed via docker. The dockerized version is removes the local dependency for the correct version of Tendermint by using the same thing the testnet will use. The initial configuration is passed to the helm chart of each node, overriding the default values. Once the chaos/ndau node is running, their Tendermint configurations enable communication as validator nodes.

## Installation

The two scripts `ndau.js` and `chaos.js` require node to execute. They both set up a multiple node test net in kubernetes

Both scripts use kubectl and helm. kubectl must be configured to authenticate and set to use a cluster of your chosing, as all commands executed by these scripts will go through helm and kubectl.

Once that's taken care of, the default settings will adequatly set up a new test net.

```
VERSION_TAG=fedcba0 ./chaos.js 30000 castor pollux
./ndau.js 31000 ren stimpy
```

The first line installs chaos nodes named castor and pollux. It uses port `30000` as a base port and increments from there. That is, it will use `30000` for castor's `p2p` port, then `30001` for castor's `rpc` port. Pollux will get `30002` and `30003` respectively.

The same process is true for the ndau node. It simply starts at `31000` and calls them ren and stimpy.

You may optionally specify container versions for Noms and Tendermint. The ndau and chaos nodes require a `VERSION_TAG` variable to be set.

```
NOMS_VERSION=fedcba0
TM_VERSION=fedcba0
CHAOS_LINK=http://127.0.0.0:26657
VERSION_TAG=fedcba0
```

In order to link the ndau nodes to a chaos node, you must supply the `CHAOS_LINK` variable with the url where the chaos node will be available (e.g. `http://127.0.0.0:26657`).

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
