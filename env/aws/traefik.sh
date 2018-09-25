#!/bin/bash
# This script installs traefik and connects the established ELB to a subdomain.

usage() {
	errcho "Usage"
	errcho "  Environment variables"
	errcho "    EMAIL          Valid email address used for SSL registration."
	errcho "    RELEASE_NAME   Traefik's name, used for installing with helm."
	errcho "    ELB_DOMIAN     Subdomain to add for Traefik's ELB. Endpoints will exist as subdomains of"
	errcho "                   the subdomain you provide here. This script will prefix the CNAME with \"*.\""
	errcho "Usage: EMAIL=email@example.com RELEASE_NAME=ndau-traefik ./traefik.sh"
}

# Config
CHART=stable/traefik

# get this script's path
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shellcheck source=../common/helpers.sh
source "$DIR"/../common/helpers.sh

# shellcheck source=../common/check_sed.sh
source "$DIR"/../common/check_sed.sh
me=$(basename "$0")

missing_env_vars=()

required_vars=( "EMAIL" "RELEASE_NAME" "ELB_DOMAIN" )

for ev in "${required_vars[@]}"; do
	if [ -z "${!ev}" ]; then
    	missing_env_vars+=("$ev")
	fi
done

if [ ${#missing_env_vars[@]} != 0 ]; then
	str=${missing_env_vars[*]}
    errcho "$me" "Missing the following env vars: ${str// /, }"
    usage
    exit 1
fi

if [ ! -f "$DIR"/traefik-keys.sh ]; then
	err "$me" "Please copy traefik-keys.sample.sh to traefik-keys.sh and change the values to match your authorized user."
fi
# Gets AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
# shellcheck source=./traefik-keys.sample.sh
source "$DIR"/traefik-keys.sh

# get parent domain from the ELB_DOMAIN
PARENT_DOMAIN=$($sed "s/[^\\.]*\\.//" <<< "$ELB_DOMAIN")
if ! hzs=$(aws route53 list-hosted-zones); then
	errcho "$hzs"
	err "$me" "Could not get hosted zones from AWS."
fi

parent_HZ=$(echo "$hzs" | jq -r ".HostedZones[] | select(.Name==\"${PARENT_DOMAIN}.\") | .Id")
if [ -z "$parent_HZ" ]; then
  err "$me" "No hosted zone found for parent domain: $PARENT_DOMAIN"
fi

# check to see if the CNAME for this elb is already there
record=$(aws route53 list-resource-record-sets --hosted-zone-id "$parent_HZ" |\
	jq ".ResourceRecordSets[] | select(.Name==\"\\\\052.${ELB_DOMAIN}.\")")

if [ ! -z "$record" ]; then
	echo "Subdomain $ELB_DOMAIN already exists. Will not create."
fi

OPTS=""

# Use this image with alpine for shelling into container for debugging
# OPTS+="--set imageTag=1.7-alpine "
# Sets log level to debug and turns on profiler
# OPTS+="--set debug.enabled=false "
# More logs for debugging
# OPTS+="--set acme.logging=true "

# Use https.
OPTS+="--set ssl.enabled=true "

# Try to get SSL certs using let's encrypt.
OPTS+="--set acme.enabled=true "

# What kind of ownership challenge to use. dns-01 is the most secure.
OPTS+="--set acme.challengeType=dns-01 "

# Just wait a little while
OPTS+="--set acme.delayBeforeCheck=60 "

# This needs to be here for SSL cert registration. You will recieve notifications.
OPTS+="--set acme.email=$EMAIL "

# Staging=true will get fake certificates. Use it for testing. False is the real deal.
OPTS+="--set acme.staging=true "

# For k8s 1.5+
OPTS+="--set rbac.enabled=true "

# Tell it we're on AWS
OPTS+="--set acme.dnsProvider.name=route53 "

# AWS specific authorization and config
OPTS+="--set acme.dnsProvider.route53.AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID "
OPTS+="--set acme.dnsProvider.route53.AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY_ID "
OPTS+="--set acme.dnsProvider.route53.AWS_REGION=us-east-1 "

# "Upstall"
if helm ls --tls | grep "$RELEASE_NAME"; then
	echo_green "$me" "Upgrading $RELEASE_NAME"
	# shellcheck disable=2086
	helm upgrade "$RELEASE_NAME" "$CHART" --recreate-pods --tls $OPTS
else
	# shellcheck disable=2086
	helm install "$CHART" --name "$RELEASE_NAME" --tls $OPTS
fi

# wait for elb assignment
(
	retries=10
	wait_seconds=10
	for i in $(seq $retries 0); do
		if kubectl get svc "$RELEASE_NAME" | grep "<pending>"; then
			errcho "ELB address not available. Waiting ${wait_seconds} and retrying $i more times."
			sleep $wait_seconds
		else
			errcho "ELB address assigned is available."
			break
		fi
	done
)

# get ELB address
ELB_ADDRESS=$(kubectl describe svc "$RELEASE_NAME" --namespace default | grep Ingress | awk '{print $3}' | tr -d '[:space:]')

# copy template
cp traefik.json.template traefik.json

# replace variables
$sed -i "s/ELB_DOMAIN/\\\\\\\\052.${ELB_DOMAIN}./g" "$DIR"/traefik.json
$sed -i "s/ELB_ADDRESS/$ELB_ADDRESS/g" "$DIR"/traefik.json

# give a cname to the hosted zone
aws route53 change-resource-record-sets \
    --hosted-zone-id "$parent_HZ" \
    --change-batch file://traefik.json

# clean up
rm "$DIR"/traefik.json
