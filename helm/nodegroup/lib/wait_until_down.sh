#!/bin/bash

# wait for waits until a service is shut down
wait_until_down() {
	local service=$1
	local tag="wait_until_down"
	log "$tag: waiting for $service to shut down"
	wait_until_key_exists "snapshot-$service-down" 30
}
