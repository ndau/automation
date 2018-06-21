#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ensure dependencies
$DIR/dev.sh

# get a subdomain if it's not already there
$DIR/subdomain.sh

# bring up a new cluster
$DIR/bootstrap-cluster.sh

# deploy chaosnode to the new cluster
$DIR/up.sh
