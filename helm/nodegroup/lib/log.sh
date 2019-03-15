#!/bin/bash

log () {
    # shellcheck disable=SC2154
    >&2 printf '{t:"%s", l:"%s", src:"%s", msg:"%s"}\n' \
    "$(date +%F_%T)" \
    "info" \
    "$log_src" \
    "$(printf "%s" "$@" | sed 's/"/\\\"/g')"
}
