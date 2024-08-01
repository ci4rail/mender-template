# Define variables
ARTIFACT_NAME ?= awesome-mender-artifact
APPLICATION_NAME ?= awesome-application
ORCHESTRATOR ?= docker-compose
OUTPUT_DIR ?= ./artifacts
SOFTWARE_NAME ?= softwarename
SOFTWARE_VERSION ?= v1.3.0

# List of platforms and architectures
PLATFORMS ?= linux/arm64 # linux/amd64

# List of manifest directories and corresponding images
APP_DIRS_IMAGES = ./app/benthos-http-producer:jeffail/benthos:latest ./app/go-template:ghcr.io/ci4rail/go-template:latest

# List of device types
DEVICE_TYPES ?= mender01

# Mender server details
MENDER_SERVER_URL ?= https://hosted.mender.io
MENDER_USERNAME ?= $(error MENDER_USERNAME is not set)
MENDER_PASSWORD ?= $(error MENDER_PASSWORD is not set)
MENDER_TENANT_TOKEN ?= $(error MENDER_TENANT_TOKEN is not set)

# Default target
all: build-and-upload

# Get the current commit SHA as default version
VERSION ?= $(shell git rev-parse --short HEAD)

# Target to build and upload Mender artifacts for each manifest directory, platform, and device type
build-and-upload: build-artifacts upload-artifacts

# Target to build Mender artifacts for each manifest directory, platform, and device type
build-artifacts:
	@mkdir -p $(OUTPUT_DIR)
	@for platform in $(PLATFORMS); do \
		formatted_platform=$$(echo $$platform | tr '/' '_'); \
		for dir_image in $(APP_DIRS_IMAGES); do \
			dir=$$(echo $$dir_image | cut -d':' -f1); \
			image=$$(echo $$dir_image | cut -d':' -f2-); \
			for device in $(DEVICE_TYPES); do \
	     		artifact_name=$(ARTIFACT_NAME)-$(APPLICATION_NAME)-$$(basename $$dir)-$$device-$$formatted_platform-$(VERSION); \
				echo "Artifact name: $$artifact_name"; \
				output_path=$(OUTPUT_DIR)/$$artifact_name.mender; \
				echo "Building Mender artifact for $$dir, device $$device, platform $$platform with commit $(VERSION)..."; \
				app-gen --artifact-name "$$artifact_name" \
				        --device-type "$$device" \
				        --platform "$$platform" \
				        --application-name "$(APPLICATION_NAME)-$$(basename $$dir)" \
				        --image "$$image" \
				        --orchestrator "$(ORCHESTRATOR)" \
				        --manifests-dir "$$dir/manifest" \
				        --output-path "$$output_path" \
				        -- \
				        --software-name="$$(basename $$dir)" \
				        --software-version="$(VERSION)"; \
				echo "Mender artifact built successfully: $$output_path"; \
			done \
		done \
	done

# Target to upload Mender artifacts
upload-artifacts:
	@mender-cli login --server $(MENDER_SERVER_URL) --username $(MENDER_USERNAME) --password $(MENDER_PASSWORD) --token-value $(MENDER_TENANT_TOKEN)
	@for artifact in $(OUTPUT_DIR)/*.mender; do \
		echo "Uploading $$artifact to Mender server..."; \
		mender-cli artifacts upload $$artifact --server $(MENDER_SERVER_URL); \
		# rm -f $$artifact; \
		echo "Uploaded $$artifact successfully"; \
	done

# Clean target to remove all artifact files
clean:
	@echo "Cleaning up..."
	@rm -rf $(OUTPUT_DIR)
	@echo "Clean up completed."

# Phony targets to avoid conflicts with files named 'all' or 'clean'
.PHONY: all build-and-upload build-artifacts upload-artifacts clean
