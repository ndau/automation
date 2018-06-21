#!/bin/bash
# This script brings up the chaos node in kubernetes.

# stop execution of this script if there's an error
set -e

# preflight checks

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/../common/wait_for_cluster.sh

usage() {
    echo "Usage"
    echo "For dude.ndau.tech:"
    echo "ENDPOINT_DOMAIN=dude.ndau.tech BUCKET=ndau-dude-cluster-state-store ./up.sh"
}

if [ -z "$ENDPOINT_DOMAIN" ]; then
    echo "Missing endpoint domain."
    usage
    exit 1
fi

if [ -z "$BUCKET" ]; then
    echo "Missing bucket name."
    usage
    exit 1
fi

# make sure the cluster is ready
wait_for_cluster $BUCKET

# Install chaosnode
helm install --name cn-1 $DIR/../../helm/chaosnode \
  --set ingress.enabled=true \
  --set ingress.host=$ENDPOINT_DOMAIN
