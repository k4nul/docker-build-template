#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

PUSH=false
export PUSH
"$SCRIPT_DIR/validate-build-plan.sh"

PUSH=true
export PUSH
"$SCRIPT_DIR/build-image.sh"
