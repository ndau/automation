#!/bin/bash
# Configure kops

usage() {
    echo "Usage"
    echo "For dev.cluster.ndau.tech:"
    echo "CLUSTER_NAME=dev SD=cluster.ndau.tech ./bootstrap.sh"
}

if [ -z "$CLUSTER_NAME" ]; then
    echo "Missing cluster name."
    usage
    exit 1
fi

AZ=us-east-1a
BUCKET=ndau-${CLUSTER_NAME}-cluster-state-store

# create a bucket
aws s3api create-bucket \
    --bucket $BUCKET \
    --region $REGION

# turn on versioning for bucket to rollback
aws s3api put-bucket-versioning \
    --bucket $BUCKET \
    --versioning-configuration \
    Status=Enabled

# format the name for the cluster
export NAME=${CLUSTER_NAME}.${SD}
export KOPS_STATE_STORE=s3://$BUCKET

# use kops to create the cluster in the availability zone specified.
kops create cluster --zones $AZ $NAME
