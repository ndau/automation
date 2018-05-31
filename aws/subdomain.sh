#!/bin/bash

# Configure kops
usage() {
    echo "Usage"
    echo "SD=cluster.ndau.tech ./subdomain.sh"
}

if [ -z "$SD" ]; then
    echo "Missing SD (subdomain)."
    usage
    exit 1
fi

# Get the parent domain
PD=$(sed "s/[^\.]*\.//" <<< $SD)

# make a uuid for a request
ID=$(uuidgen)

# create a new hosted zone and get nameservers
NS=$(aws route53 create-hosted-zone \
        --name $SD \
        --caller-reference $ID |\
    jq .DelegationSet.NameServers)

# get hosted zone for the parent domain
parent_HZ=$(aws route53 list-hosted-zones | jq -r ".HostedZones[] | select(.Name==\"${PD}.\") | .Id")

# sed all the things
cp subdomain.template subdomain.json
sed -i "s/DNS_1/$(jq -r '.[0]' <<< $NS)/g" subdomain.json
sed -i "s/DNS_2/$(jq -r '.[1]' <<< $NS)/g" subdomain.json
sed -i "s/DNS_3/$(jq -r '.[2]' <<< $NS)/g" subdomain.json
sed -i "s/DNS_4/$(jq -r '.[3]' <<< $NS)/g" subdomain.json
sed -i "s/PARENT_DOMAIN/${PARENT_DOMAIN}/g" subdomain.json

# give a cname to the hosted zone
aws route53 change-resource-record-sets \
    --hosted-zone-id ${parent_HZ} \
    --change-batch file://subdomain.json


