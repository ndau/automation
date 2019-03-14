#!/bin/bash

err () {
    # shellcheck disable=SC2154
    >&2 printf '{t:"%s", l:"%s", src:"%s", msg:"%s"}' \
    "$(date +%F_%T)" \
    "err" \
    "$log_src" \
    "$(printf "%s" "$@" | sed 's/"/\\\"/g')"
}
