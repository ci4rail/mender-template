# Define variables
ARTIFACT_NAME ?= awesome-mender-artifact
PLATFORM ?= linux/amd64
APPLICATION_NAME ?= awesome-application
ORCHESTRATOR ?= docker-compose
OUTPUT_DIR ?= ./artifacts
SOFTWARE_NAME ?= softwarename
SOFTWARE_VERSION ?= v1.0.1

# List of manifest directories and corresponding images
APP_DIRS_IMAGES = ./app/benthos-http-producer:jeffail/benthos:latest # ./app/go-template:golang:latest ./app/yet-another-app-dir:another-image:latest

# List of device types
DEVICE_TYPES ?= template-device # another-device yet-another-device

# Mender server details
MENDER_SERVER_URL ?= https://hosted.mender.io
MENDER_USERNAME ?= <your-username>
MENDER_PASSWORD ?= <your-password>
MENDER_TENANT_TOKEN ?= <your-tenant-token>

# Default target
all: build-and-upload

# Get the current commit SHA as default version
VERSION ?= $(shell git rev-parse --short HEAD)

# Target to build and upload Mender artifacts for each manifest directory and each device type
build-and-upload: build-artifacts upload-artifacts

# Target to build Mender artifacts for each manifest directory and each device type
build-artifacts:
	@mkdir -p $(OUTPUT_DIR)
	@for dir_image in $(APP_DIRS_IMAGES); do \
		dir=$$(echo $$dir_image | cut -d':' -f1); \
		image=$$(echo $$dir_image | cut -d':' -f2-); \
		for device in $(DEVICE_TYPES); do \
			artifact_name=$(ARTIFACT_NAME)-$$(basename $$dir)-$$device-$(VERSION); \
			output_path=$(OUTPUT_DIR)/$$artifact_name.mender; \
			echo "Building Mender artifact for $$dir and device $$device with commit $(VERSION)..."; \
			app-gen --artifact-name "$$artifact_name" \
			        --device-type "$$device" \
			        --platform "$(PLATFORM)" \
			        --application-name "$(APPLICATION_NAME)" \
			        --image "$$image" \
			        --orchestrator "$(ORCHESTRATOR)" \
			        --manifests-dir "$$dir/manifest" \
			        --output-path "$$output_path" \
			        -- \
			        --software-name="$$(basename $$dir)" \
			        --software-version="$(VERSION)"; \
			echo "Mender artifact built successfully: $$output_path"; \
		done \
	done


# Target to upload Mender artifacts
upload-artifacts:
	@mender-cli login --server $(MENDER_SERVER_URL) --username $(MENDER_USERNAME) --password $(MENDER_PASSWORD) --token-value $(MENDER_TENANT_TOKEN)
	@for artifact in $(OUTPUT_DIR)/*.mender; do \
		echo "Uploading $$artifact to Mender server..."; \
		mender-cli artifacts upload $$artifact --server $(MENDER_SERVER_URL); \
		echo "Uploaded $$artifact successfully"; \
	done


# Clean target to remove all artifact files
clean:
	@echo "Cleaning up..."
	@rm -rf $(OUTPUT_DIR)
	@echo "Clean up completed."

# Phony targets to avoid conflicts with files named 'all' or 'clean'
.PHONY: all build-and-upload build-artifacts upload-artifacts clean
