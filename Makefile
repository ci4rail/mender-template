include .env
include .secret

# Define variables, defaulting to environment variables if set
ARTIFACT_NAME ?= $(or ${ARTIFACT_NAME},app)
ORCHESTRATOR ?= $(or ${ORCHESTRATOR},docker-compose)
OUTPUT_DIR ?= $(or ${OUTPUT_DIR},./artifacts)

# List of platforms and architectures
PLATFORMS ?= $(or ${PLATFORMS},linux/amd64) # linux/arm64

# List of app directories
APP_DIRS ?= $(or ${APP_DIRS},./app/app-dir)

# List of device types
DEVICE_TYPES ?= $(or ${DEVICE_TYPES},device-type-a)

# Mender server details
MENDER_SERVER_URL ?= https://hosted.mender.io
MENDER_USERNAME ?= $(error MENDER_USERNAME is not set)
MENDER_PASSWORD ?= $(error MENDER_PASSWORD is not set)
MENDER_TENANT_TOKEN ?= $(error MENDER_TENANT_TOKEN is not set)

# Docker image to use for building artifacts
DOCKER_IMAGE ?= mender-build-and-upload

# Default target
all: build-and-upload

# Target to build the Docker image
docker-build:
	@echo "Building Docker image $(DOCKER_IMAGE)..."
	@docker build -t $(DOCKER_IMAGE) . || { echo "Docker build failed"; exit 1; }

# Get the current commit SHA as default version
VERSION ?= $(shell git rev-parse --short HEAD)

# Target to build and upload Mender artifacts for each manifest directory, platform, and device type
build-and-upload: docker-build build-artifacts upload-artifacts

# Target to build Mender artifacts for each manifest directory, platform, and device type
build-artifacts:
	@mkdir -p $(OUTPUT_DIR)
	@for platform in $(PLATFORMS); do \
		formatted_platform=$$(echo $$platform | tr '/' '_'); \
		for dir in $(APP_DIRS); do \
			images=$$(docker run --rm -v ${PWD}:/workdir -e UID=$(shell id -u) -e GID=$(shell id -g) -e DID=$(shell getent group docker | cut -d: -f3) $(DOCKER_IMAGE) /bin/bash /workdir/hack/gen-image-names.sh /workdir/$$dir/manifest/docker-compose.yaml); \
			if [ $$? -ne 0 ]; then echo "Failed to generate image names for $$dir"; exit 1; fi; \
			echo "Using Images: $$images"; \
			for device in $(DEVICE_TYPES); do \
				artifact_name=$(ARTIFACT_NAME)-$$(basename $$dir)-$$device-$$formatted_platform-$(VERSION); \
				echo "Artifact name: $$artifact_name"; \
				output_path=$(OUTPUT_DIR)/$$artifact_name.mender; \
				echo "Building Mender artifact for $$dir, device $$device, platform $$platform with commit $(VERSION)..."; \
				docker run --rm \
					-v ${PWD}:/workdir \
					-v /var/run/docker.sock:/var/run/docker.sock \
					-e UID=$(id -u) \
					-e GID=$(id -g) \
					-e DID=$(getent group docker | cut -d: -f3) \
					$(DOCKER_IMAGE) \
					app-gen --artifact-name "$$artifact_name" \
							--device-type "$$device" \
							--platform "$$platform" \
							--application-name "$$(basename $$dir)" \
							$$images \
							--orchestrator "$(ORCHESTRATOR)" \
							--manifests-dir "/workdir/$$dir/manifest" \
							--output-path "/workdir/$$output_path" \
							-- \
							--software-name="$$(basename $$dir)" \
							--software-version="$(VERSION)"; \
				if [ $$? -ne 0 ]; then echo "Failed to build Mender artifact for $$dir"; exit 1; fi; \
				echo "Mender artifact built successfully: $$output_path"; \
			done \
		done \
	done

# Target to upload Mender artifacts
upload-artifacts:
	@docker run --rm -v ${PWD}:/workdir -e UID=$(shell id -u) -e GID=$(shell id -g) -e DID=$(shell getent group docker | cut -d: -f3) $(DOCKER_IMAGE) \
		mender-cli login --server $(MENDER_SERVER_URL) --username $(MENDER_USERNAME) --password $(MENDER_PASSWORD) --token-value $(MENDER_TENANT_TOKEN) || { echo "Mender CLI login failed"; exit 1; }
	@for artifact in $(OUTPUT_DIR)/*.mender; do \
		echo "Uploading $$artifact to Mender server..."; \
		docker run --rm -v ${PWD}:/workdir -e UID=$(shell id -u) -e GID=$(shell id -g) -e DID=$(shell getent group docker | cut -d: -f3) $(DOCKER_IMAGE) \
			mender-cli artifacts upload $$artifact --server $(MENDER_SERVER_URL); \
		if [ $$? -ne 0 ]; then echo "Failed to upload $$artifact"; exit 1; fi; \
		# rm -f $$artifact; \
		echo "Uploaded $$artifact successfully"; \
	done

# Clean target to remove all artifact files
clean:
	@echo "Cleaning up..."
	@rm -rf $(OUTPUT_DIR)
	@echo "Clean up completed."

# Phony targets to avoid conflicts with files named 'all' or 'clean'
.PHONY: all build-and-upload build-artifacts upload-artifacts clean docker-build
