#!/bin/bash
# This creates a subdomain with Route53 and points it to traefik's ELB.
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $DIR/../common/check_sed.sh
source $DIR/../common/helpers.sh
me=$0

# usage displays help
usage() {
    errcho "Usage"
    errcho "ENDPOINT_SUBDOMAIN=dev-chaos.ndau.tech ./endpoint-subdomain.sh"
}

if [ -z "$ENDPOINT_SUBDOMAIN" ]; then
    errcho "Missing ENDPOINT_SUBDOMAIN."
    usage
    exit 1
fi

# get_elb_address tries to get the elb address for traefik
get_elb_address() {
    local retries=5
	local wait_seconds=5
    for i in $(seq $retries 0); do
        local pending_test=$(kubectl get svc tic-traefik | grep -i pending)
        if [ -z "$pending_test" ]; then
			elb=$(kubectl describe svc tic-traefik | grep Ingress | awk '{print $3}')
            errcho "Got traefik ELB address: $elb"
            break
        else
            errcho "traefik elb address not ready. Retrying $i more times."
            sleep $wait_seconds
        fi
    done
}

# get the address for the elb
get_elb_address

# Don't set up the subdomain if it's already pointing at this specific elb
# will not overwrite any previous cname info,
if [ -z "$(dig +short *.$ENDPOINT_SUBDOMAIN | grep $elb)" ]; then

	# Get the subdomain
	endpoint_subdomain=$($sed 's/^[^ ]* \|\..*//' <<< "$ENDPOINT_SUBDOMAIN")

	# get the parent domain
	endpoint_parent_domain=$($sed 's/[^\.]*\.//' <<< "$ENDPOINT_SUBDOMAIN")

	# get hosted zone for the parent domain
	parent_HZ=$(aws route53 list-hosted-zones | jq -r ".HostedZones[] | select(.Name==\"${endpoint_parent_domain}.\") | .Id")
	errcho "Parent's hosted zone is: ${parent_HZ}"

	if [ -z "$parent_HZ" ]; then
    	err $me "No hosted zone for parent domain: ${endpoint_parent_domain}"
	fi

	# copy config template and update it to give a cname to the hosted zone
	cp $DIR/cname-update.template $DIR/cname-update.json
	$sed -i "s/ENDPOINT_SUBDOMAIN/*.${ENDPOINT_SUBDOMAIN}/" $DIR/cname-update.json
	$sed -i "s/ELB_ADDRESS/$elb/"                           $DIR/cname-update.json

	errcho "Sending changes to Route 53"
	aws route53 change-resource-record-sets \
		--hosted-zone-id ${parent_HZ} \
		--change-batch file://cname-update.json >&2

else
  errcho "Nothing updated. DNS ${ENDPOINT_DOMAIN} already points to ${elb}."
fi

rm $DIR/cname-update.json # cleanup
