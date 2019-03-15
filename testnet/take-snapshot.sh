#!/bin/bash

# get release name from arguemnts
release=$1

if [ -z "$release" ]; then
	>&2 echo "Usage: ./take-snapshot.sh RELEASE_NAME"
	>&2 echo "Example: ./take-snapshot.sh devnet-0"
	exit 1
fi

# get snapshot pod name from release
snapshot_pod=$(kubectl get pod -l "release=$release,app=nodegroup-snapshot-redis" -o=jsonpath='{.items[0].metadata.name}')

# execute snapshot script on snapshot pod
kubectl exec "$snapshot_pod" -- /bin/bash /root/start.sh
