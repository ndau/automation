#!/bin/bash

# kill a process and wait for it to really be killed.
kill_and_wait() {
  local pid=$1
  local name=$2
  local tag="kill_and_wait"
  log "$tag: killing $name"
  kill "$pid"
  while kill -0 "$pid"; do
    log "$tag: waiting for $name process to die"
    sleep 1
  done
  log "$tag: done waiting"
}
