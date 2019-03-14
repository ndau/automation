#!/bin/bash

# wait for waits until a service is shut down
wait_until_down() {
	service=$1
	log "waiting for $service to shut down"
	wait_until_key_gone "snapshot-$service-down" 30
}
