#!/bin/bash

err () {
    >&2 printf '{t:"%s", l:"%s", src:"%s", msg:"%s"}' \
    $(date +%F_%T) \
    "err" \
    "$log_src" \
    "$(printf "$@" | sed 's/"/\\\"/g')"
}
