#!/usr/bin/env bash


# Ubuntu doesn't include the unzip utility in its base installation. Move this
# line into the Dockerfile if other installation scripts need it too
apt install unzip -y

# Install the AWS CLI. Instructions originally copied from
# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Set default AWS region
aws configure set region us-west-2
