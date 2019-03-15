#!/bin/bash
# This will download all the information you need to connect a single node to a network by fetching the necessary config
# and base64 encodes it, making it ready for putting into the existing helm commands.
release=$1

if [ -z "$release" ]; then
	>&2 echo "Usage: ./fetch-config.sh RELEASE_NAME"
	>&2 echo "Example: ./fetch-config.sh devnet-0"
	exit 1
fi

# easy way to get a pod name
pod_name() {
    release=$1
    app=$2
    kubectl get pod -l release="$release",app=nodegroup-"$app" -o=jsonpath='{.items[0].metadata.name}'
}

b64() {
	echo "$1" | base64
}

process_json() {
	b64 "$(echo "$@" | jq "." -c)"
}

c_address="$(kubectl exec "$(pod_name "$release" chaos-tendermint)"  cat /tendermint/config/priv_validator_key.json | jq -r .address )"
n_address="$(kubectl exec "$(pod_name "$release" ndau-tendermint)"  cat /tendermint/config/priv_validator_key.json | jq -r .address )"

c_genesis=$( process_json "$(kubectl exec "$(pod_name "$release" chaos-tendermint)"  cat /tendermint/config/genesis.json)" )
n_genesis=$( process_json "$(kubectl exec "$(pod_name "$release" ndau-tendermint)"  cat /tendermint/config/genesis.json)" )

ip=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="ExternalIP")].address}' | tr " " "\n" | head -n 1 | tr -d "[:space:]")
n_p2p=$(kubectl get service --namespace default -o jsonpath="{.spec.ports[?(@.name==\"p2p\")].nodePort}" "$release"-nodegroup-ndau-tendermint-service)
c_p2p=$(kubectl get service --namespace default -o jsonpath="{.spec.ports[?(@.name==\"p2p\")].nodePort}" "$release"-nodegroup-chaos-tendermint-service)

echo -e "\nchaos"
echo "persistentPeers=\"$(b64 "$(printf "%s@%s:%s" "$c_address" "$ip" "$c_p2p")")\""
echo "genesis=$c_genesis"

echo -e "\nndau"
echo "persistentPeers=\"$(b64 "$(printf "%s@%s:%s" "$n_address" "$ip" "$n_p2p")")\""
echo "genesis=$n_genesis"
