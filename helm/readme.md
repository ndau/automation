# Installation

For instructions on installing helm securely to your cluster use the following guide [helm-installation.md](./helm-installation.md).

# helm charts

These helm charts are largely similar, but different enough to make it worth while to keep the separate. Updating them is a pain, yes. Usually, I make a change in one and use a diff tool. But installing is complicated enough without having to specify whether it's a chaos node or ndau node, and then giving each chart the ability to know how to do each. Scripts are good for that level of abstraction. Hence the testnet scripts.

## Upgrading tendermint

Since we've had helm charts tendermint has been upgraded exactly once. This is a checklist to make sure that upgrade can go smoothly.

* Regarding `tendermint init`'s generated files, diff the old versions and the new versions. Take note of any new files.
  - previously 0.18.x did not generate node_key.json files. The diff being, this file is critical in 0.24.x.

# Snapshot creation

There are three values in values.yaml that are required for creating snapshots. They are `snapshotOnShutdown`, `awsKeyID` and `awsSecretAccessKey`.

Redis is used to coordinate snapshot creation between pods. It is a simple state machine with several flags for each process involved, (chaos/ndau, noms/tendermint).

The initial state is indicated by the `...-snapping` key set to 0. This means that it is ready to create a snapshot and is not currently creating a snapshot. Each service has it's own loop to check whether its specific key is calling for a snapshot to be created (`...-ndau-tm`, `...-chaos-noms`, etc). If any service is called to snapshot (either by SIGTERM or by detecting a `1` for its snapshot key), AND `...-snapping` is set to 0, it will set `...-snapping` to `1` and all the others to `1`, triggering a snapshot for all other services. If `...-snapping` is set to `1` already, it will simply set its own flag to `0` when it's done. If all flags are set to `0` and `...-snapping` is set to `1`, then `...-snapping` gets set to `0`. Put another way, when snapping is true services just complete their job. If snapshotting when snapping is false, then turn on jobs for other services.

Race conditions are prevented by `...-snapping` being set with the NX argument, which is redis for `set-if-unset`.
