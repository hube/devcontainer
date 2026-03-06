#!/usr/bin/env bash

# Install the AWS CLI. Instructions originally copied from
# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscli-exe-linux-aarch64.zip"
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip.sha256" -o "awscli-exe-linux-aarch64.zip.sha256"
sha256sum -c awscli-exe-linux-aarch64.zip.sha256

unzip awscli-exe-linux-aarch64.zip
./aws/install

# Set default AWS region
aws configure set region us-west-2
