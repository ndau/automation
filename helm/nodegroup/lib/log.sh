#!/bin/bash

log () {
    >&2 printf '{t:"%s", l:"%s", src:"%s", msg:"%s"}\n' \
    $(date +%F_%T) \
    "info" \
    "$log_src" \
    "$(printf "$@" | sed 's/"/\\\"/g')"
}
