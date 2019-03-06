# Installation

For instructions on installing helm securely to your cluster use the following guide [helm-installation.md](./helm-installation.md).

# helm charts

These helm charts are largely similar, but different enough to make it worth while to keep the separate. Updating them is a pain, yes. Usually, I make a change in one and use a diff tool. But installing is complicated enough without having to specify whether it's a chaos node or ndau node, and then giving each chart the ability to know how to do each. Scripts are good for that level of abstraction. Hence the testnet scripts.

## Upgrading tendermint

Since we've had helm charts tendermint has been upgraded exactly once. This is a checklist to make sure that upgrade can go smoothly.

* Regarding `tendermint init`'s generated files, diff the old versions and the new versions. Take note of any new files.
  - previously 0.18.x did not generate node_key.json files. The diff being, this file is critical in 0.24.x.

# Snapshot creation

Snapshots are tar archives of databases. The files that comprise the databases for tendermint, redis and nomsdb are all tarballed and sent to the `ndau-snapshots` bucket on S3. This can be done manually or as a part of a cron job in kubernetes. Saving snapshots in this way allows a newly installed node to not start from scratch.

## How does it work?

Scripts that run inside the pods are used to trigger a backup sequence that is coordinated using redis. The keys concerned are

* `snapshot-snapping` - Set to "1" when a snapshot should be underway. Set at the beginning of the snapshot process and deleted at the end. Prevents starting twice.
* `snapshot-{node}-{app}` - Set to "1" to start an individual application's snapshot procedure.
* `snapshot-{node}-height` - Indicates the current height of the blockchain. Is set when tendermint shuts down. All other snapshot processes will wait until this value is available.
* `snapshot-temp-token` - This is set when the snapshot process begins. It is used to coordinate the uploads of each individual snapshot to a temporary directory on s3. When each individual database's snapshot is verified, the file is moved to the correct directory.

In sequence, the `snapshot-snapping` key is set to `1` and each of the application keys is set to `1`. The tendermint pod immediately shuts down tendermint and gets the current height. The tendermints then wait until noms is done, and then upload their snapshots. When each noms, redis, tendermint for chaosnode and ndaunode complete and verified, they are moved into a directory that allows them to be indexed by height (e.g. `ndau-42`).

The keys are all set with the `NX 120` option, meaning that if they fail or take longer than 2 minutes to snapshot, then those keys get cleaned up and the process may begin again. If an application does not finish backing up, it will not be verified in the final step and not be indexed by height.

## Databases

Very breifly, the noms database contains the current state of the blockchain; the tendermint database contains the blockchain transactions; redis (aside from coordinating snapshots) contains indexes for quicker lookup times.

## Automatic snapshots

When executing `gen_node_groups.py`, the `SNAPSHOTS_ENABLED=true` setting will give the first nodegroup the setting `--set snapshots.enabled=true`, and keep all the rest of them `false`. This will activate all of the necessary resources for creating snapshots in the first nodegroup. The optional variable `SNAPSHOT_SCHEDULE` will also be passed and should contain a valid crontab-style schedule.

## Manual snapshots

Snapshots can be triggered in one of two ways. Either by shelling in and executing the `/root/start.sh` script manually on the `snapshot-redis` pod, or via a network call to the `snapshot-redis` service at the configured listener port. `echo "snap" | nc {{ template "nodegroup.fullname" . }}-snapshot-redis {{ .Values.snapshot.cron.listener.port }}`

## Troubleshooting

### genesis.json

This file needs to be immutable once the block chain is running, ie. once blocks are being generated.

The tricky part of genesis.json is the `app_hash`. The `app_hash` value in genesis.json must match the generated app hash from either chaosnode or ndaunode at block 0. If at block 0, the hash does not say the exact same thing tendermint will panic and exit with an error.

The `chain_id` is also important because it is included in tendermint block headers.

The initial set of validator nodes, with their public keys, are also listed in genesis.json.

### Monitoring the snapshot process

Logs that display the activities of pods undergoing snapshots are be available from their own respective pods. There are no sidecar pods that need to be monitored for those individual processes. The entire snapshot job can be monitored at a high level from the logs of the snapshot-redis pod. To get the pod's logs, execute `kubectl logs $(kubectl get pod -l release=YOUR_RELEASE-0,app=nodegroup-snapshot-redis | tail -n 1 | awk '{print $1}') -f` keeping in mind to change `YOUR_RELEASE-0` to the release you are interested in (e.g. `devnet-1`).
