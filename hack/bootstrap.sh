#!/bin/bash

# Farben und Formatierungen definieren
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Funktion zum Ausgeben von Meldungen
function print_info {
  echo -e "${BLUE}${BOLD}INFO:${NC} $1"
}

function print_success {
  echo -e "${GREEN}${BOLD}SUCCESS:${NC} $1"
}

function print_warning {
  echo -e "${YELLOW}${BOLD}WARNING:${NC} $1"
}

function print_error {
  echo -e "${RED}${BOLD}ERROR:${NC} $1"
}



# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to update the package list
update_package_list() {
    sudo apt-get update
}

# Function to install Docker
install_docker_and_compose() {
    print_info "Installing Docker and Docker compose..."

    # check if "docker compose" is called "docker-compose" or "docker compose"
    if command_exists docker-compose; then
        print_success "Docker compose is already installed."
    else
        for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
        # Add Docker's official GPG key:
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository to Apt sources:
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update

        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo ln -s /usr/bin/docker /usr/bin/docker-compose

        sudo systemctl restart mender-updated
        print_success "Docker and Docker compose installed successfully."
    fi
    
}

# Install iptables nftables
install_iptables_nftables() {
   
    # Install iptables and nftables
    print_info "Installing iptables and nftables..."
    sudo apt-get update
    sudo apt-get install -y iptables nftables
    print_success "iptables and nftables installed successfully."
  
    # Switch to nftables
    print_info "Switching to nftables..."
    sudo update-alternatives --set iptables /usr/sbin/iptables-nft
    sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-nft
    sudo update-alternatives --set arptables /usr/sbin/arptables-nft
    sudo update-alternatives --set ebtables /usr/sbin/ebtables-nft
    print_success "Switched to nftables successfully."
}



# create docker certs to secure docker daemon
create_docker_certs() {
    print_info "Creating Docker certificates..."
    # Create directory for Docker certificates
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
    print_success "Docker certificates created successfully."
}


# Function to configure Docker daemon to use TLS certificates for secure communication
configure_docker_daemon() {
    print_info "Configuring Docker daemon to use TLS certificates..."
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
    print_success "Docker daemon configured to use TLS certificates."
}

# Function to display Docker versions
display_docker_versions() {
    print_info "Docker version:"
    docker version
    print_info "Docker Compose version:"
    docker compose version
}

# Function to install additional tools
install_additional_tools() {
    print_info "Installing additional tools..."
    sudo apt-get install -y jq tree xdelta3
    echo "jq version:"
    jq --version
    echo "tree version:"
    tree --version
    echo "xdelta3 version:"
    xdelta3 --version
    print_success "Additional tools installed successfully."
}

# Function to install Mender client
install_mender_client() {
    print_info "Installing Mender client..."
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg-agent \
        software-properties-common

    sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 24072B80A1B29B00

    curl -fsSL https://downloads.mender.io/repos/debian/gpg | sudo tee /etc/apt/trusted.gpg.d/mender.asc
    gpg --show-keys --with-fingerprint /etc/apt/trusted.gpg.d/mender.asc
    sudo sed -i.bak -e "\,https://downloads.mender.io/repos/debian,d" /etc/apt/sources.list

    echo "deb [arch=$(dpkg --print-architecture)] https://downloads.mender.io/repos/debian ubuntu/jammy/stable main" \
     | sudo tee /etc/apt/sources.list.d/mender.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y mender-client4
    print_success "Mender client installed successfully."
}

# Function to set up Mender
setup_mender() {
    print_info "Setting up Mender..."

    check_environment_vars

    sudo mender-setup \
        --device-type $MENDER_DEVICE_TYPE \
        --hosted-mender \
        --tenant-token $MENDER_TENANT_TOKEN \
        --demo-polling

    sudo systemctl restart mender-updated
    print_success "Mender setup completed successfully."
}

# Function to install Mender Docker Compose update module
install_mender_docker_compose_update_module() {
    
    print_info "Installing Mender Docker Compose update module..."

    sudo mkdir -p /usr/share/mender/modules/v3
    sudo wget https://raw.githubusercontent.com/mendersoftware/app-update-module/1.0.0/src/app \
        -O /usr/share/mender/modules/v3/app \
        && sudo chmod +x /usr/share/mender/modules/v3/app

    sudo mkdir -p /usr/share/mender/app-modules/v1
    sudo wget https://raw.githubusercontent.com/mendersoftware/app-update-module/1.0.0/src/app-modules/docker-compose \
        -O /usr/share/mender/app-modules/v1/docker-compose \
        && sudo chmod +x /usr/share/mender/app-modules/v1/docker-compose

    sudo wget https://raw.githubusercontent.com/mendersoftware/app-update-module/1.0.0/conf/mender-app.conf \
        -O /etc/mender/mender-app.conf
    sudo wget https://raw.githubusercontent.com/mendersoftware/app-update-module/1.0.0/conf/mender-app-docker-compose.conf \
        -O /etc/mender/mender-app-docker-compose.conf

    sudo systemctl restart mender-updated
    print_success "Mender Docker Compose update module installed successfully."
}

check_environment_vars() {
    if [ -z "$MENDER_DEVICE_TYPE" ]; then
        print_error "MENDER_DEVICE_TYPE variable is not set."
        exit 1
    fi

    if [ -z "$MENDER_TENANT_TOKEN" ]; then
        print_error "MENDER_TENANT_TOKEN variable is not set."
        exit 1
    fi
}

# Function to restart Docker daemon
restart_docker() {

    print_info "Restarting Docker daemon..."
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    print_success "Docker daemon restarted successfully."
}

# Function to check if Docker started correctly
check_docker_status() {
    if sudo systemctl is-active --quiet docker; then
        print_success "Docker TLS/SSL configuration completed. Docker daemon is now accessible over TCP on port 2376."
    else
        print_error "Docker failed to start correctly. Please check Docker logs."
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
install_docker_and_compose
# configure_docker_daemon
display_docker_versions
install_additional_tools
install_mender_client
setup_mender
install_mender_docker_compose_update_module

echo "Installation complete."
