#!/bin/bash

# Configure kops
usage() {
    echo "Usage"
    echo "SD=dev.cluster.ndau.tech ./subdomain.sh"
}

if [ -z "$SD" ]; then
    echo "Missing SD (subdomain)."
    usage
    exit 1
fi


# make a uuid for a request
ID=$(uuidgen)

# create a new hosted zone and get nameservers
NS=$(aws route53 create-hosted-zone \
        --name cluster.ndau.tech \
        --caller-reference $ID |\
    jq .DelegationSet.NameServers)

# get hosted zone for the parent domain
parent_HZ=$(aws route53 list-hosted-zones |\
    jq -r '.HostedZones[] | select(.Name=="ndau.tech.") | .Id')

# sed all the things
cp subdomain.template subdomain.json
sed -i "s/DNS_1/$(jq -r '.[0]' <<< $NS)/g" subdomain.json
sed -i "s/DNS_2/$(jq -r '.[1]' <<< $NS)/g" subdomain.json
sed -i "s/DNS_3/$(jq -r '.[2]' <<< $NS)/g" subdomain.json
sed -i "s/DNS_4/$(jq -r '.[3]' <<< $NS)/g" subdomain.json
sed -i "s/PARENT_DOMAIN/${PARENT_DOMAIN}/g" subdomain.json

aws route53 change-resource-record-sets \
    --hosted-zone-id $parent_HZ \
    --change-batch file://subdomain.json


aws s3api create-bucket \
    --bucket ${BUCKET} \
    --region us-east-1
aws s3api put-bucket-versioning --bucket ${BUCKET} --versioning-configuration Status=Enabled

export NAME=dev.cluster.ndau.tech
export KOPS_STATE_STORE=s3://${BUCKET}

AZ=us-east-1a

kops create cluster --zones ${AZ} ${NAME}




