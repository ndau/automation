#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# for $sed
source $DIR/../common/helpers.sh

# Configure kops
usage() {
    echo "Usage"
    echo "SUB_DOMAIN=cluster.ndau.tech ./subdomain.sh"
}

if [ -z "$SUB_DOMAIN" ]; then
    echo "Missing SUB_DOMAIN."
    usage
    exit 1
fi

# Get the parent domain
export PARENT_DOMAIN=$(sed "s/[^\.]*\.//" <<< "$SUB_DOMAIN")

# get hosted zone for the parent domain
parent_HZ=$(aws route53 list-hosted-zones | jq -r ".HostedZones[] | select(.Name==\"${PARENT_DOMAIN}.\") | .Id")

# check to see if the dns info is already there
record=$(aws route53 list-resource-record-sets --hosted-zone-id $parent_HZ |\
	jq ".ResourceRecordSets[] | select(.Name==\"$SUB_DOMAIN.\")")

# early exit if subdomain already exists
if [ ! -z "$record" ]; then
	echo "Subdomain $SUB_DOMAIN already exists. Will not create."
	exit 0
fi

# make a uuid for a request
ID=$(uuidgen)

# create a new hosted zone and get nameservers
NS=$(aws route53 create-hosted-zone \
        --name "$SUB_DOMAIN" \
        --caller-reference "$ID" |\
    jq .DelegationSet.NameServers)

# sed all the things
cp $DIR/subdomain.template $DIR/subdomain.json
$sed -i "s/DNS_1/$(jq -r '.[0]' <<< "$NS")/g" $DIR/subdomain.json
$sed -i "s/DNS_2/$(jq -r '.[1]' <<< "$NS")/g" $DIR/subdomain.json
$sed -i "s/DNS_3/$(jq -r '.[2]' <<< "$NS")/g" $DIR/subdomain.json
$sed -i "s/DNS_4/$(jq -r '.[3]' <<< "$NS")/g" $DIR/subdomain.json
$sed -i "s/NEW_SUB_DOMAIN/${SUB_DOMAIN}/g" $DIR/subdomain.json

# give a cname to the hosted zone
aws route53 change-resource-record-sets \
    --hosted-zone-id ${parent_HZ} \
    --change-batch file://subdomain.json

# cleanup
rm $DIR/subdomain.json
