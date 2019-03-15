#!/bin/bash

# kill a process and wait for it to really be killed.
kill_decoy() {
  local pid=$1
  local port=$2
  local tag="kill_decoy"
  kill "$pid"
  while kill -0 "$pid"; do
    log "$tag: waiting for decoy on $port to die"
    sleep 1
  done
  log "$tag: done waiting"

  while true; do
    if exec 6<>/dev/tcp/127.0.0.1/"$port"; then
        exec 6>&- # close output
        exec 6<&- # close input
        log "$tag: Port $port still open"
        sleep 1
    else
        exec 6>&- # close output
        exec 6<&- # close input
        break
    fi
  done
  log "$tag: Port $port free."
}
