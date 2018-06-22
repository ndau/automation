#!/bin/bash
# This script brings up the chaos node in kubernetes.

# stop execution of this script if there's an error
set -e

# preflight checks

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

usage() {
    echo "Usage"
    echo "For [rpc/p2p].cn.ndau.tech and [rpc/p2p].nn.ndau.tech.:"
    echo "CHAOS_ENDPOINT=one.cn.ndau.tech NDAU_ENDPOINT=one.nn.ndau.tech ./up.sh"
}

if [ -z "$CHAOS_ENDPOINT" ]; then
    echo "Missing chaos node endpoint."
    usage
    exit 1
fi

if [ -z "$NDAU_ENDPOINT" ]; then
    echo "Missing ndau node endpoint."
    usage
    exit 1
fi

# Install chaosnode
helm install --name cn-1 $DIR/../../helm/chaosnode \
  --set ingress.enabled=true \
  --set ingress.host=$CHAOS_ENDPOINT

# Install ndaunode
helm install --name nn-1 $DIR/../../helm/ndaunode \
  --set ingress.enabled=true \
  --set ingress.host=$NDAU_ENDPOINT
