#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to update the package list
update_package_list() {
    sudo apt-get update
}

# Function to install Docker
install_docker() {
    if command_exists docker; then
        echo "Docker is already installed."
    else
        sudo apt-get install -y docker.io
    fi
}

# Function to install Docker Compose
install_docker_compose() {
    if command_exists docker-compose; then
        echo "Docker Compose is already installed."
    else
        sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi
}

# Function to configure Docker daemon
configure_docker_daemon() {
    cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "hosts": ["tcp://0.0.0.0:2375", "unix:///var/run/docker.sock"]
}
EOF
    sudo systemctl restart docker
    sudo ufw allow 2375/tcp
    sudo ufw enable
}

# Function to display Docker versions
display_docker_versions() {
    echo "Docker version:"
    docker --version
    echo "Docker Compose version:"
    docker-compose --version
}

# Function to install additional tools
install_additional_tools() {
    sudo apt-get install -y jq tree xdelta3
    echo "jq version:"
    jq --version
    echo "tree version:"
    tree --version
    echo "xdelta3 version:"
    xdelta3 --version
}

# Function to install Mender client
install_mender_client() {
    sudo apt-get install --assume-yes \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg-agent \
        software-properties-common

    curl -fsSL https://downloads.mender.io/repos/debian/gpg | sudo tee /etc/apt/trusted.gpg.d/mender.asc
    gpg --show-keys --with-fingerprint /etc/apt/trusted.gpg.d/mender.asc
    sudo sed -i.bak -e "\,https://downloads.mender.io/repos/debian,d" /etc/apt/sources.list

    echo "deb [arch=$(dpkg --print-architecture)] https://downloads.mender.io/repos/debian ubuntu/jammy/stable main" \
     | sudo tee /etc/apt/sources.list.d/mender.list > /dev/null

    sudo apt-get update
    sudo apt-get install mender-client4
}

# Function to set up Mender
setup_mender() {
    if [ -z "$DEVICE_TYPE" ]; then
        echo "Error: DEVICE_TYPE variable is not set."
        exit 1
    fi

    if [ -z "$TENANT_TOKEN" ]; then
        echo "Error: TENANT_TOKEN variable is not set."
        exit 1
    fi

    sudo mender-setup \
        --device-type $DEVICE_TYPE \
        --hosted-mender \
        --tenant-token $TENANT_TOKEN \
        --demo-polling

    sudo systemctl restart mender-updated
}

# Function to install Mender Docker Compose update module
install_mender_docker_compose_update_module() {
    sudo su

    mkdir -p /usr/share/mender/modules/v3
    wget https://raw.githubusercontent.com/mendersoftware/app-update-module/1.0.0/src/app \
        -O /usr/share/mender/modules/v3/app \
        && chmod +x /usr/share/mender/modules/v3/app

    mkdir -p /usr/share/mender/app-modules/v1
    wget https://raw.githubusercontent.com/mendersoftware/app-update-module/1.0.0/src/app-modules/docker-compose \
        -O /usr/share/mender/app-modules/v1/docker-compose \
        && chmod +x /usr/share/mender/app-modules/v1/docker-compose

    wget https://raw.githubusercontent.com/mendersoftware/app-update-module/1.0.0/conf/mender-app.conf \
        -O /etc/mender/mender-app.conf
    wget https://raw.githubusercontent.com/mendersoftware/app-update-module/1.0.0/conf/mender-app-docker-compose.conf \
        -O /etc/mender/mender-app-docker-compose.conf

    systemctl restart mender-client
    echo "Mender update service restarted."
    echo "Mender Docker Compose update module installed successfully."
}

# Main script execution
update_package_list
install_docker
install_docker_compose
configure_docker_daemon
display_docker_versions
install_additional_tools
install_mender_client
setup_mender
install_mender_docker_compose_update_module

echo "Installation complete."
