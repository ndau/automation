# Installation

For instructions on installing helm securely to your cluster use the following guide [helm-installation.md](./helm-installation.md).

# helm charts

These helm charts are largely similar, but different enough to make it worth while to keep the separate. Updating them is a pain, yes. Usually, I make a change in one and use a diff tool. But installing is complicated enough without having to specify whether it's a chaos node or ndau node, and then giving each chart the ability to know how to do each. Scripts are good for that level of abstraction. Hence the testnet scripts.

## Upgrading tendermint

Since we've had helm charts tendermint has been upgraded exactly once. This is a checklist to make sure that upgrade can go smoothly.

* Regarding `tendermint init`'s generated files, diff the old versions and the new versions. Take note of any new files.
  - previously 0.18.x did not generate node_key.json files. The diff being, this file is critical in 0.24.x.
