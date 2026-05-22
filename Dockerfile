FROM ubuntu:rolling

ARG USERNAME=ubuntu

# Install additional utilities not included in Ubuntu by default
RUN apt update
RUN apt install \
  curl \
  git \
  iptables ipset \
  python3 python3-pip python3-venv \
  sudo \
  unzip \
  vim \
  zsh \
  -y

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Create workspace and config directories and set permissions
RUN mkdir -p /workspaces
RUN chown -R $USERNAME:$USERNAME /workspaces

# Install tools that require root permissions
WORKDIR /tmp
COPY ./install-scripts/root/* ./install-scripts/root/.

WORKDIR /tmp/install-scripts/root
RUN ./aws-cli.sh
RUN ./aws-sam.sh
RUN ./git-delta.sh

# Setup non-root user
USER $USERNAME

ENV SHELL=/bin/zsh
ENV EDITOR=vim
ENV VISUAL=vim

# Install additional tools
WORKDIR /tmp
COPY ./install-scripts/user/* ./install-scripts/user/.

WORKDIR /tmp/install-scripts/user
RUN ./oh-my-zsh.sh
RUN ./nodejs.sh
RUN ./yarn.sh
RUN ./aws-cdk.sh
RUN ./claude.sh

# Copy config files
COPY home /home/$USERNAME

# Copy and set up firewall script
COPY firewall.sh /usr/local/bin/
USER root
RUN echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/firewall.sh" > /etc/sudoers.d/${USERNAME}-firewall
RUN chmod 0440 /etc/sudoers.d/${USERNAME}-firewall
USER $USERNAME

WORKDIR /workspaces

# Start the container and keep it running
ENTRYPOINT ["sleep", "infinity"]
