#!/bin/bash
# This script will build the app for multiple environments.
# https://golang.org/doc/install/source#environment
targets=("linux/amd64" "darwin/amd64" "windows/amd64")
for target in "${targets[@]}"
do
	printf >&2 "Building %s..." "$target"
    IFS="/" read -r GOOS GOARCH <<< "$target"
    file="addy-${GOOS}-${GOARCH}"

    if [ "$GOOS" = "windows" ]; then
        file+=".exe"
    fi

    if ! env GOOS="$GOOS" GOARCH="$GOARCH" go build -o dist/$file; then
        echo >&2 "Error building."
        exit 1
    else
		echo >&2 "done"
	fi
done
