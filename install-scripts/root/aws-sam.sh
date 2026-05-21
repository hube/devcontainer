#!/usr/bin/env bash

# Install the AWS SAM CLI. Instructions originally copied from
# https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html

curl -L "https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-arm64.zip" -o "aws-sam-cli-linux-arm64.zip"
curl -L "https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-arm64.zip.sha256" -o "aws-sam-cli-linux-arm64.zip.sha256"
sha256sum -c aws-sam-cli-linux-arm64.zip.sha256

unzip aws-sam-cli-linux-arm64.zip -d sam-installation
./sam-installation/install

# Verify the SAM CLI version:
sam --version
