#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
cd "$REPO_ROOT"

. "$SCRIPT_DIR/build-config.sh"

load_image_build_settings

if [ "$PUSH" = "true" ]; then
  printf '%s\n' \
    "PUSH=true builds must run through scripts/push-image.sh after no-push validation" >&2
  exit 2
fi

require_single_platform_load
run_image_build
