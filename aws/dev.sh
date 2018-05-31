#!/bin/bash

# Run the parent dev script
../dev.sh


GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # no color

err() {
    echo -e "${RED}$@${NC}"
    exit 1
}

echo_green() {
    echo -e "${GREEN}$@${NC}"
}


# require awscli
if [ -z "$(which aws)" ]; then
    echo_green "Installing awscli"
    brew install awscli
    aws configure
else
    echo "awscli already installed"
fi

# Ensure awscli is configured 
if [ ! -f $HOME/.aws/credentials ]; then
    echo_green "Please configure awscli."
    echo_green "See https://docs.aws.amazon.com/general/latest/gr/managing-aws-access-keys.html to create a key."
    aws configure
else
    echo "awscli already configured"
fi

# test aws
aws iam list-users > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo_red "aws not configured properly or permissions incorrect"
    echo_red "aws response: $(aws iam list-users)"
    exit 1
else
    echo "aws working"
fi

# require kops
if [ -z "$(which kops)" ]; then
    echo_green "Installing kops"
    brew install kops
else
    echo "kops already installed"
fi
