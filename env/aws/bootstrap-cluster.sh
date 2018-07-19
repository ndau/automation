#!/bin/bash
# Configure kops

# exit on errors
set -e

# includes
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/../common/wait_for_cluster.sh
source $DIR/../common/helpers.sh
me=`basename "$0"`

usage() {
    errcho "Usage"
    errcho "For dev.cluster.ndau.tech:"
    errcho "CLUSTER_NAME=dev CLUSTER_SUBDOMAIN=cluster.ndau.tech REGION=us-east-1 AZ=us-east-1b ./bootstrap-cluster.sh"
}

missing_env_vars=()
if [ -z "$CLUSTER_NAME" ]; then
    missing_env_vars+=('CLUSTER_NAME')
fi

if [ -z "$REGION" ]; then
	missing_env_vars+=('REGION')
fi

if [ -z "$CLUSTER_SUBDOMAIN" ]; then
	missing_env_vars+=('CLUSTER_SUBDOMAIN')
fi

if [ -z "$AZ" ]; then
	missing_env_vars+=('AZ')
fi

if [ ${#missing_env_vars[@]} != 0 ]; then
    echo "Missing the following env vars: $(join ${missing_env_vars[@]})"
    usage
    exit 1
fi

export BUCKET=ndau-${CLUSTER_NAME}-cluster-state-store

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
export NAME=${CLUSTER_NAME}.${CLUSTER_SUBDOMAIN}
export KOPS_STATE_STORE=s3://$BUCKET

# use kops to create the cluster in the availability zone specified.
kops create cluster \
  -f ./kops-conf.yaml \
  --zones $AZ \
   $NAME

# update instance group `nodes` with kope-ig-nodes.json
kops get ig nodes --state s3://$BUCKET -o json > kops-current.json
jq -s '.[0] * .[1]' current.json kops-ig-nodes.json > kops-merged.json
kops replace -f kops-merged.json --state s3://$BUCKET
rm kops-merged.json kops-current.json

# bring up the cluster
kops update cluster $NAME --yes

# wait for the cluster to become available
wait_for_cluster $BUCKET

# See if 1password is set up, try to sign in
if (! op list vaults); then
	errcho "Not signed in to 1passsword. Please sign in."
	op_result=$(op sign oneiro)
	if [ -z "$(echo "$op_result" | grep -i OP_SESSION)"]; then
		err $me "You have no signed in to oneiro using op before. Please run `op signin --help`."
	else
		if (! op list vaults); then
		    err $me "Could not sign in to 1password."
		fi
	fi
 fi

