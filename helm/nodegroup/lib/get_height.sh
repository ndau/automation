#!/bin/bash

# wait for height value
get_height() {
  local height="-1"
  local tag="get_height"
 	local tries_left="${TRIES:-30}" # 30 = approx 1 minutes
  while [ "$height" == "-1" ]; do
    if [[ "$tries_left" -lt "1" ]]; then
      log "Could not get $CHAIN height."
      return 1
    fi
    log "$tag: Waiting for $CHAIN height... $tries_left tries left."
    sleep 1
    height=$(redis_cli GET "snapshot-$CHAIN-height")
    tries_left=$((tries_left-1))
  done
  log "$tag: $CHAIN height: $height"
  echo -n "$height" # output the height
}
