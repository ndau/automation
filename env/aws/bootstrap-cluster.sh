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
    echo "Usage"
    echo "For dev.cluster.ndau.tech:"
    echo "CLUSTER_NAME=dev SUBDOMAIN=cluster.ndau.tech REGION=us-east-1 AZ=us-east-1b ./bootstrap-cluster.sh"
}

missing_env_vars=()
if [ -z "$CLUSTER_NAME" ]; then
    missing_env_vars+=('CLUSTER_NAME')
fi

if [ -z "$REGION" ]; then
	missing_env_vars+=('REGION')
fi

if [ -z "$SUBDOMAIN" ]; then
	missing_env_vars+=('SUBDOMAIN')
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
export NAME=${CLUSTER_NAME}.${SUBDOMAIN}
export KOPS_STATE_STORE=s3://$BUCKET

# use kops to create the cluster in the availability zone specified.
kops create cluster --zones $AZ $NAME
kops update cluster $NAME --yes

# wait for the cluster to become available
wait_for_cluster $BUCKET

# Set up subdomain and ingress controller

if (! op list vaults); then
	err $me "Please sign in to 1password using op. Remember to set the session environment variable."
fi

# install traefik ingress controller
# get the keys for the kubernetes-lets-encrypt user from 1password
eval "$(op get document du6igtjmjncu5ba6taut76dite)"
helm install stable/traefik --name tic --values $DIR/traefik-values.yaml --tls \
	--set acme.dnsProvider.route53.AWS_ACCESS_KEY_ID=$KLE_KEY \
	--set acme.dnsProvider.route53.AWS_SECRET_ACCESS_KEY=$KLE_SECRET
KLE_KEY=
KLE_SECRET=

# try to get the elb address for tendermint
get_elb_address() {
    local retries=5
	local wait_seconds=5
    for i in $(seq $retries 0); do
        local pending_test=$(kubectl get svc tic-traefik --namespace default | grep -i pending)
        if [ -z "$pending_test" ]; then
			elb=$(kubectl describe svc tic-traefik --namespace default | grep Ingress | awk '{print $3}')
            echo "Got tendermint ELB address: $elb"
            break
        else
            echo "tendermint elb address not ready. Retrying $i more times."
            sleep $wait_seconds
        fi
    done
}

# get the address for the elb
get_elb_address

# Don't set up the subdomain if it's already pointing at the elb
if [ -z "$(dig +short $ENDPOINT_DOMAIN | grep $elb)" ];

	# Get the subdomain
	endpoint_subdomain=$($sed 's/^[^ ]* \|\..*//' <<< "$ENDPOINT_DOMAIN")

	# get the parent domain
	endpoint_parent_domain=$($sed 's/[^\.]*\.//' <<< "$ENDPOINT_DOMAIN")

	# get hosted zone for the parent domain
	parent_HZ=$(aws route53 list-hosted-zones | jq -r ".HostedZones[] | select(.Name==\"${endpoint_parent_domain}.\") | .Id")

	cp $DIR/cname-update.template $DIR/cname-update.json
	$sed -i "s/ENDPOINT_SUBDOMAIN/$ENDPOINT_DOMAIN/" $DIR/cname-update.json
	$sed -i "s/ELB_ADDRESS/$elb/"                    $DIR/cname-update.json

	# get hosted zone for the parent domain
	parent_HZ=$(aws route53 list-hosted-zones | jq -r ".HostedZones[] | select(.Name==\"${endpoint_parent_domain}.\") | .Id")

	if [ -z "$parent_HZ" ]; then
    	err $me "No hosted zone for parent domain: ${endpoint_parent_domain}"
	fi

	# give a cname to the hosted zone
	aws route53 change-resource-record-sets \
		--hosted-zone-id ${parent_HZ} \
		--change-batch file://cname-update.json

fi

rm $DIR/cname-update.json # cleanup
