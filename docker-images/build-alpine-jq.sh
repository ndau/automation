#!/bin/bash

# builds alpine jq and uploads it

docker build . -f ./alpine-jq.docker -t 578681496768.dkr.ecr.us-east-1.amazonaws.com/alpine-jq:latest
docker push 578681496768.dkr.ecr.us-east-1.amazonaws.com/alpine-jq:latest
