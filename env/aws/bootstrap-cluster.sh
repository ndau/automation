#!/bin/bash
# Configure kops

# exit on errors
set -e

# includes
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=../common/dev.sh
source "$DIR"/../common/dev.sh
# shellcheck source=../common/helpers.sh
source "$DIR"/../common/helpers.sh
# shellcheck source=../common/wait_for_cluster.sh
source "$DIR"/../common/wait_for_cluster.sh
me=$(basename "$0")

usage() {
    errcho "Usage"
    errcho "For dev.cluster.ndau.tech:"
    errcho "CLUSTER_NAME=dev CLUSTER_SUBDOMAIN=cluster.ndau.tech REGION=us-east-1 AZ=us-east-1b ./bootstrap-cluster.sh"
}

if [ -f "$HOME"/.ssh/kops-rsa.pub ]; then
	errcho "Please make sure the ssh key you wish to use for kops is located at $HOME/.ssh/kops-rsa.pub"
fi

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
    errcho "$me" "Missing the following env vars: $(join "${missing_env_vars[@]}")"
    usage
    exit 1
fi

export BUCKET=ndau-"$CLUSTER_NAME"-cluster-state-store

# create a bucket
aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION"

# turn on versioning for bucket to rollback
aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration \
    Status=Enabled

# format the name for the cluster
export NAME=${CLUSTER_NAME}.${CLUSTER_SUBDOMAIN}
export KOPS_STATE_STORE=s3://"$BUCKET"

# use kops to create the cluster in the availability zone specified.
kops create cluster \
  --zones "$AZ" \
  --name "$NAME" \
  --ssh-public-key "$HOME"/.ssh/kops-rsa.pub

# update instance group `nodes` with kope-ig-nodes.json
kops get ig nodes --name "$NAME" --state s3://"$BUCKET" -o json > current-nodes.json
kops get ig master-"$AZ" --name "$NAME" --state s3://"$BUCKET" -o json > current-master.json
jq -s '.[0] * .[1]' current-nodes.json ig-nodes-spec.json > merged-nodes.json
jq -s '.[0] * .[1]' current-master.json ig-master-spec.json > merged-master.json
kops replace -f merged-nodes.json --state s3://"$BUCKET"
kops replace -f merged-master.json --state s3://"$BUCKET"

rm current-master.json
rm current-nodes.json

rm merged-nodes.json
rm merged-master.json

# bring up the cluster
kops update cluster --name "$NAME" --yes

# wait for the cluster to become available
wait_for_cluster "$BUCKET"
