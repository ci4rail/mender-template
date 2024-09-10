FROM ubuntu:22.04

# Default values for UID, GID, and DID
ENV UID=1000
ENV GID=1000
ENV DID=999

# Create the docker group with DID
RUN groupadd -g ${DID} docker

# Install necessary packages
RUN apt-get update && apt-get install --assume-yes \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg-agent \
    software-properties-common \
    make \
    wget \
    docker.io

# Install app-gen
COPY hack/app-gen /usr/local/bin/app-gen

# Install mender-cli
RUN wget https://downloads.mender.io/mender-cli/1.12.0/linux/mender-cli \
    -O /usr/local/bin/mender-cli && chmod +x /usr/local/bin/mender-cli

# Install mender-artifact
RUN wget https://downloads.mender.io/mender-artifact/3.11.2/linux/mender-artifact \
    -O /usr/local/bin/mender-artifact && chmod +x /usr/local/bin/mender-artifact

# Install libssl
RUN wget http://nz2.archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb && dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb

# Install yq
RUN wget https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64 -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# Create user to enable ssh from nonroot user in docker container
RUN groupadd -g ${GID} user && useradd -m -u ${UID} -g ${GID} user && usermod -aG docker user

# Switch to the new user
USER user

# Set the working directory
WORKDIR /app
