#!/bin/bash

# runs the snapshot script for a service
make_service_snapshot() {
  local tag="make_service_snapshot"
  log "$tag: starting snapshot"
  # shellcheck disable=SC2154
  kill_and_wait "$pid" "$THIS_SERVICE"
  redis_cli SET "snapshot-$THIS_SERVICE-down" "1" EX 120 # flag the service as down
  >&2 timeout -t 60 /bin/bash /root/liveness-decoy.sh "$DECOY_PORT" & # start the decoy
  local decoy_pid=$!
  >&2 /bin/bash /root/make-snapshot.sh # run the services' own snapshot script
  kill_decoy $decoy_pid "$DECOY_PORT" # kill the decoy and free up the port
  startup # start the service back up. down flag is removed here.
}
