#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

. "$SCRIPT_DIR/build-config.sh"

load_image_build_settings

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

export_image_build_settings
docker buildx bake --file buildx/docker-bake.hcl --print >/dev/null

printf '%s\n' "No-push build plan validation passed for $(image_build_ref)"
