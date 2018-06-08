#!/bin/bash
# Configure kops

usage() {
    echo "Usage"
    echo "For dev.cluster.ndau.tech:"
    echo "CLUSTER_NAME=dev SUB_DOMAIN=cluster.ndau.tech REGION=us-east-1 AZ=us-east-1b ./bootstrap-cluster.sh"
}

missing_env_vars=()
if [ -z "$CLUSTER_NAME" ]; then
    missing_env_vars+=('CLUSTER_NAME')
fi

if [ -z "$REGION" ]; then
	missing_env_vars+=('REGION')
fi

if [ -z "$SUB_DOMAIN" ]; then
	missing_env_vars+=('SUB_DOMAIN')
fi

if [ -z "$AZ" ]; then
	missing_env_vars+=('AZ')
fi

if [ ${#missing_env_vars[@]} != 0 ]; then
    echo "Missing the following env vars: $(join ${missing_env_vars[@]})"
    usage
    exit 1
fi

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
export NAME=${CLUSTER_NAME}.${SUB_DOMAIN}
export KOPS_STATE_STORE=s3://$BUCKET

# use kops to create the cluster in the availability zone specified.
kops create cluster --zones $AZ $NAME
kops update cluster $NAME --yes
