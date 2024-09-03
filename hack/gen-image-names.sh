#/bin/bash
# usage: ./gen-image-names.sh <path-to-docker-compose-yaml>

# Read the docker-compose.yml file
compose_file=$1

# Extract image names using yq (a lightweight and portable command-line YAML processor)
image_names=$(yq '.services[].image' "$compose_file")

# Iterate over each image name
for image in $image_names; do
  # Prepend --image to each image name and print it
  echo "--image $image"
done