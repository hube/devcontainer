FROM ubuntu:rolling

WORKDIR /tmp

# Install additional utilities not included in Ubuntu by default
RUN apt update
RUN apt install curl git unzip -y

COPY ./install-scripts/* ./install-scripts/.

RUN ./install-scripts/nodejs.sh
RUN ./install-scripts/aws-cli.sh
RUN ./install-scripts/aws-cdk.sh
RUN ./install-scripts/aws-sam.sh
RUN ./install-scripts/claude.sh

# Update PATH for all shells
ENV PATH="/root/.local/bin:$PATH"

WORKDIR /root

# Start the container and keep it running
ENTRYPOINT ["tail", "-f", "/dev/null"]
