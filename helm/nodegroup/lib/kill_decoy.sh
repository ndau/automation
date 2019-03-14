#!/bin/bash

# kill a process and wait for it to really be killed.
kill_decoy() {
  local pid=$1
  local port=$2
  kill "$pid"
  while kill -0 "$pid"; do
    log "waiting for decoy on $port to die"
    sleep 1
  done
  log "done waiting"

  while true; do
    if exec 6<>/dev/tcp/127.0.0.1/"$port"; then
        exec 6>&- # close output
        exec 6<&- # close input
        log "Port $port still open"
        sleep 1
    else
        exec 6>&- # close output
        exec 6<&- # close input
        break
    fi
  done
  log "Port $port free."
}
