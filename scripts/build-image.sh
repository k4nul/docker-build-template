#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/build-config.sh"

load_image_build_settings
IMAGE_REF=$(image_build_ref)
OUTPUT_FLAG=$(image_build_output_flag)

docker buildx build \
  --platform "$PLATFORMS" \
  --file "$DOCKERFILE" \
  --tag "$IMAGE_REF" \
  --build-arg "OCI_TITLE=$OCI_TITLE" \
  --build-arg "OCI_DESCRIPTION=$OCI_DESCRIPTION" \
  --build-arg "OCI_SOURCE=$OCI_SOURCE" \
  --build-arg "OCI_REVISION=$OCI_REVISION" \
  --build-arg "OCI_LICENSES=$OCI_LICENSES" \
  "$OUTPUT_FLAG" \
  "$CONTEXT"
