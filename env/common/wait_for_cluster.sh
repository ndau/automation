#!/bin/bash

# wait until the cluster is ready
wait_for_cluster() {

	retries=10
	wait_seconds=10
	for i in $(seq $retries 0); do
		if (kops validate cluster --state s3://$1); then
			echo "Cluster is ready."
			break
		else
			echo "Cluster not ready. Retrying $i more times."
			sleep $wait_seconds
		fi
	done

}
