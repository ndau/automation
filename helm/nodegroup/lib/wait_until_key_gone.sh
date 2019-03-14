#!/bin/bash

# wait for waits until a service is shut down
wait_until_key_gone() {
	key=$1
	tries_left="${TRIES:-30}" # 30 = approx 2 minutes
	resp="1"
	# keep waiting while the key is not there
  until [ "$resp" == "-1" ]; do
	  [[ "$tries_left" -lt "1" ]] && break
	  resp=$(redis_cli GET "$key")
	  sleep 2
	  tries_left=$((tries_left-1))
	  log "Waiting... $tries_left tries left."
	done
}
