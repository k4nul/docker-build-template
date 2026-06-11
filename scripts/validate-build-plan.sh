#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

. "$SCRIPT_DIR/build-config.sh"

CONFIG_FILE="${CONFIG_FILE:-config/image.env.example}"
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

if [ "$PUSH" != "false" ]; then
  printf '%s\n' "No-push validation requires PUSH=false" >&2
  exit 2
fi

case "$CONTEXT" in
  *://*|git@*) ;;
  *)
    if [ ! -d "$CONTEXT" ]; then
      printf '%s\n' "Build context does not exist: $CONTEXT" >&2
      exit 2
    fi
    ;;
esac

if [ ! -f "$DOCKERFILE" ]; then
  printf '%s\n' "Dockerfile does not exist: $DOCKERFILE" >&2
  exit 2
fi

if [ ! -f .dockerignore ]; then
  printf '%s\n' ".dockerignore is required before validating a public build context" >&2
  exit 2
fi

for required_pattern in \
  ".git" \
  "config/image.env" \
  ".env" \
  ".env.*" \
  "node_modules" \
  "dist" \
  "build"
do
  if ! grep -Fx -- "$required_pattern" .dockerignore >/dev/null; then
    printf '%s\n' ".dockerignore is missing required pattern: $required_pattern" >&2
    exit 2
  fi
done

docker buildx bake --file buildx/docker-bake.hcl --print >/dev/null

printf '%s\n' "No-push build plan validation passed for ${REGISTRY}${IMAGE_NAME}:${IMAGE_TAG}"
