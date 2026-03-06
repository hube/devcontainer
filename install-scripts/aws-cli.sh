#!/usr/bin/env bash

# Install the AWS CLI. Instructions originally copied from
# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Set default AWS region
aws configure set region us-west-2
