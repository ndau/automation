#!/bin/bash

# use sed or gnu sed
sed="sed"
if ! (sed --version > /dev/null 2>&1); then
    if ! (which gsed >/dev/null); then
        (
            >&2 echo "You have a broken version of sed, and gsed is not installed"
            >&2 echo "This is common on OSX. Try `brew install gnu-sed`"
            exit 1
        )
    fi
    sed=gsed
    echo "using $sed as sed"
fi
