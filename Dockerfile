FROM ubuntu:rolling

WORKDIR /tmp

RUN apt update
RUN apt install curl -y

COPY ./install-scripts/* ./install-scripts/.

RUN ./install-scripts/nodejs.sh
RUN ./install-scripts/aws-cli.sh
RUN ./install-scripts/aws-cdk.sh

WORKDIR /root

# Start the container and keep it running
ENTRYPOINT ["tail", "-f", "/dev/null"]
