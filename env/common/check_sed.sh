#!/bin/bash

# use sed or gnu sed
sed="sed"
if ! $sed --version &> /dev/null; then
    if ! which gsed &> /dev/null; then
		>&2 echo "Version of sed not adequate. Try again after: brew install gnu-sed"
		exit 1
    fi
    sed=gsed
fi
