#!/bin/bash

# kill a process and wait for it to really be killed.
kill_and_wait() {
  local pid=$1
  local name=$2
  kill "$pid"
  while kill -0 "$pid"; do
    log "waiting for $name process to die"
    sleep 1
  done
  log "done waiting"
}
