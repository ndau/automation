#!/bin/bash

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # no color

# errcho prints an error message to stderr.
errcho() {
    >&2 echo -e "$@"
}

# err prints an error message to stderr in red.
err() {
    errcho "${RED}${1}: " "${@:2}" "${NC}"
    exit 1
}

# echo_green prints a message in green
echo_green() {
    errcho "$GREEN" "$@" "$NC"
}

# confirm takes a character as input and "returns" bash's built-in true/false
confirm_timeout=10
confirm() {
    # read with a prompt and 10 second timeout
    read -t $confirm_timeout -r -p "${1} [y/n]} " response
    case "$response" in
        [yY][eE][sS]|[yY])
            true ;;
		"")
			false ;;
        *)
            false ;;
    esac
}

# echos a joins arrays by a ", " delimiter
join() {
    shift; printf "%s" "$1"; shift; printf "%s" "${@/#/, }";
}
