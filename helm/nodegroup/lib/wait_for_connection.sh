#!/bin/bash

wait_for_connection() {
  service=$1
  pod=$2
  port=$3
  tag="wait_for_connection"

  log "$tag: starting $service wait loop"
  until nc -z -w 1 "$pod" "$port"; do
    log "$tag: waiting for $pod on $port to accept a connection"
    sleep 2
  done
}
