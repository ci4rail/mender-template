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

# Install iptables nftables
install_iptables_nftables() {
    # Install iptables and nftables
    sudo apt-get update
    sudo apt-get install -y iptables nftables

    # Switch to nftables
    sudo update-alternatives --set iptables /usr/sbin/iptables-nft
    sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-nft
    sudo update-alternatives --set arptables /usr/sbin/arptables-nft
    sudo update-alternatives --set ebtables /usr/sbin/ebtables-nft
}


# create docker certs to secure docker daemon
create_docker_certs() {
    sudo mkdir -p /etc/docker/certs

    # Function to generate CA certificate and key
    sudo openssl genrsa -aes256 -out /etc/docker/certs/ca-key.pem 4096
    sudo openssl req -new -x509 -days 365 -key /etc/docker/certs/ca-key.pem -sha256 -out /etc/docker/certs/ca.pem
    
    # Function to generate server certificate and key
    sudo openssl genrsa -out /etc/docker/certs/server-key.pem 4096
    sudo openssl req -subj "/CN=$(hostname)" -sha256 -new -key /etc/docker/certs/server-key.pem -out /etc/docker/certs/server.csr
    echo subjectAltName = DNS:$(hostname),IP:127.0.0.1 | sudo tee /etc/docker/certs/extfile.cnf
    sudo openssl x509 -req -days 365 -sha256 -in /etc/docker/certs/server.csr -CA /etc/docker/certs/ca.pem -CAkey /etc/docker/certs/ca-key.pem -CAcreateserial -out /etc/docker/certs/server-cert.pem -extfile /etc/docker/certs/extfile.cnf
    
    # Function to generate client certificate and key
    sudo openssl genrsa -out /etc/docker/certs/key.pem 4096
    sudo openssl req -subj '/CN=client' -new -key /etc/docker/certs/key.pem -out /etc/docker/certs/client.csr
    echo extendedKeyUsage = clientAuth | sudo tee /etc/docker/certs/extfile-client.cnf
    sudo openssl x509 -req -days 365 -sha256 -in /etc/docker/certs/client.csr -CA /etc/docker/certs/ca.pem -CAkey /etc/docker/certs/ca-key.pem -CAcreateserial -out /etc/docker/certs/cert.pem -extfile /etc/docker/certs/extfile-client.cnf
}


# Function to configure Docker daemon to use TLS certificates for secure communication
configure_docker_daemon() {
    sudo bash -c 'cat > /etc/docker/daemon.json <<EOF
{
  "hosts": ["tcp://0.0.0.0:2376", "unix:///var/run/docker.sock"],
  "tls": true,
  "tlsverify": true,
  "tlscacert": "/etc/docker/certs/ca.pem",
  "tlscert": "/etc/docker/certs/server-cert.pem",
  "tlskey": "/etc/docker/certs/server-key.pem"
}
EOF'
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

check_environment_vars() {

    if [ -z "$DEVICE_TYPE" ]; then
        echo "Error: DEVICE_TYPE variable is not set."
        exit 1
    fi

    if [ -z "$TENANT_TOKEN" ]; then
        echo "Error: TENANT_TOKEN variable is not set."
        exit 1
    fi

}

# Function to restart Docker daemon
restart_docker() {
    sudo systemctl daemon-reload
    sudo systemctl restart docker
}

# Function to check if Docker started correctly
check_docker_status() {
    if sudo systemctl is-active --quiet docker; then
        echo "Docker TLS/SSL configuration completed. Docker daemon is now accessible over TCP on port 2376."
    else
        echo "Docker failed to start correctly. Please check Docker logs."
        sudo journalctl -u docker.service
    fi
}

display_client_instructions() {
    echo "To access the Docker daemon with the Docker client, set the following environment variables:"
    echo "export DOCKER_TLS_VERIFY=1"
    echo "export DOCKER_HOST=tcp://$(hostname):2376"
    echo "export DOCKER_CERT_PATH=/etc/docker/certs"
}

# Main script execution
check_environment_vars
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
