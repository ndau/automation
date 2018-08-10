#!/bin/bash
# This script will build a base image for use in circle-ci.

# get the current directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Build this image
docker build -t deploy-utils "$DIR" -f "$DIR/deploy-utils.docker"

# get the version label from the docker image
VERSION=$(docker inspect deploy-utils | jq -jr '.[0].ContainerConfig.Labels["org.opencontainers.image.version"]')

# make a version tag
TAG=578681496768.dkr.ecr.us-east-1.amazonaws.com/deploy-utils:$VERSION

# tag the image we built and push it to ECR
docker tag deploy-utils "$TAG"
docker push "$TAG"
