#!/bin/bash

# gets a value from redis
redis_cli() {
  local seconds=${TIMEOUT:-2}
  timeout -t "$seconds" /bin/bash /root/redis-cli.sh -h "$R_HOST" "$@"
  return
}
