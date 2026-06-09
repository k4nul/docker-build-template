#!/usr/bin/env sh
set -eu

PUSH=true
export PUSH

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/build-image.sh"
