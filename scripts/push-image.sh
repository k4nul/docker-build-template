#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
cd "$REPO_ROOT"

PUSH=false
export PUSH
"$SCRIPT_DIR/validate-build-plan.sh"

PUSH=true
export PUSH

. "$SCRIPT_DIR/build-config.sh"
load_image_build_settings
run_image_build
