# Configure kops

usage() {
    echo "Usage"
    echo "BUCKET=ndau-my-cluster-state-store ./bootstrap.sh"
}


if [ -z "$BUCKET" ]; then
    echo "Missing bucket name."
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




