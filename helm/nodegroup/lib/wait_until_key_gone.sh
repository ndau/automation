#!/bin/bash

# wait for waits until a service is shut down
wait_until_key_gone() {
	local key=$1
	local tag="wait_until_key_gone"
	local tries_left="${TRIES:-30}" # 30 = approx 2 minutes
	local resp="1"
	# keep waiting while the key is not there
	log "$tag: Waiting for $key to be gone"
  until [ "$resp" == "-1" ]; do
	  [[ "$tries_left" -lt "1" ]] && break
	  resp=$(redis_cli GET "$key")
	  sleep 2
	  tries_left=$((tries_left-1))
	  log "$tag: Waiting... $tries_left tries left."
	done
}
