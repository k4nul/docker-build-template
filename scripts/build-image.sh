#!/usr/bin/env sh
set -eu

CONFIG_FILE="${CONFIG_FILE:-config/image.env.example}"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/build-config.sh"

if [ -f "$CONFIG_FILE" ]; then
  load_image_config "$CONFIG_FILE"
fi

REGISTRY="${REGISTRY:-}"
IMAGE_NAME="${IMAGE_NAME:-example-app}"
IMAGE_TAG="${IMAGE_TAG:-0.1.0}"
CONTEXT="${CONTEXT:-.}"
DOCKERFILE="${DOCKERFILE:-docker/Dockerfile}"
PLATFORMS="${PLATFORMS:-linux/amd64}"
PUSH="${PUSH:-false}"

validate_image_build_settings

IMAGE_REF="${REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}"

if [ "$PUSH" = "true" ]; then
  OUTPUT_FLAG="--push"
else
  OUTPUT_FLAG="--load"
fi

docker buildx build \
  --platform "$PLATFORMS" \
  --file "$DOCKERFILE" \
  --tag "$IMAGE_REF" \
  "$OUTPUT_FLAG" \
  "$CONTEXT"
