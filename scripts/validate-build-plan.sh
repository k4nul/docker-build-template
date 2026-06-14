#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

. "$SCRIPT_DIR/build-config.sh"

require_file_contains() {
  file_path=$1
  required_text=$2

  if ! grep -F -- "$required_text" "$file_path" >/dev/null; then
    printf '%s\n' "$file_path is missing required security guidance: $required_text" >&2
    exit 2
  fi
}

is_remote_context() {
  case "$1" in
    *://*|git@*) return 0 ;;
    *) return 1 ;;
  esac
}

require_no_push_validation_mode() {
  if [ "$PUSH" != "false" ]; then
    printf '%s\n' "No-push validation requires PUSH=false" >&2
    exit 2
  fi
}

require_build_paths() {
  if ! is_remote_context "$CONTEXT"; then
    if [ ! -d "$CONTEXT" ]; then
      printf '%s\n' "Build context does not exist: $CONTEXT" >&2
      exit 2
    fi
  fi

  if [ ! -f "$DOCKERFILE" ]; then
    printf '%s\n' "Dockerfile does not exist: $DOCKERFILE" >&2
    exit 2
  fi
}

require_dockerfile_oci_metadata() {
  for required_arg in \
    OCI_TITLE \
    OCI_DESCRIPTION \
    OCI_SOURCE \
    OCI_REVISION \
    OCI_LICENSES
  do
    if ! grep -Eq "^ARG[[:space:]]+$required_arg(=|$)" "$DOCKERFILE"; then
      printf '%s\n' "Dockerfile is missing required OCI metadata argument: $required_arg" >&2
      exit 2
    fi
  done

  for required_label in \
    'org.opencontainers.image.title="${OCI_TITLE}"' \
    'org.opencontainers.image.description="${OCI_DESCRIPTION}"' \
    'org.opencontainers.image.source="${OCI_SOURCE}"' \
    'org.opencontainers.image.revision="${OCI_REVISION}"' \
    'org.opencontainers.image.licenses="${OCI_LICENSES}"'
  do
    if ! grep -F -- "$required_label" "$DOCKERFILE" >/dev/null; then
      printf '%s\n' "Dockerfile is missing required OCI label binding: $required_label" >&2
      exit 2
    fi
  done
}

require_context_hygiene_contract() {
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
}

require_build_contract_guidance() {
  if [ ! -f docs/build-contract.md ]; then
    printf '%s\n' "docs/build-contract.md is required before validating supply-chain build guidance" >&2
    exit 2
  fi

  for required_guidance in \
    "Build context hygiene:" \
    "local configs, dotenv files, credentials" \
    'through `.dockerignore`' \
    "Secret handling:" \
    "do not pass registry credentials, package tokens, or private" \
    "BuildKit secret" \
    "build arguments, labels, or copied files" \
    "SBOM and provenance:" \
    "SBOM=false" \
    "PROVENANCE=false" \
    "PROVENANCE=mode=min" \
    "PROVENANCE=mode=max" \
    "attestation publishing" \
    "private image names"
  do
    require_file_contains docs/build-contract.md "$required_guidance"
  done
}

validate_bake_plan() {
  export_image_build_settings
  docker buildx bake --file buildx/docker-bake.hcl --print >/dev/null
}

require_bake_plan_attestation_controls() {
  bake_plan_output=$(mktemp)
  export_image_build_settings

  if ! docker buildx bake --file buildx/docker-bake.hcl --print > "$bake_plan_output"; then
    rm -f "$bake_plan_output"
    return 1
  fi

  if [ "$SBOM" = "false" ] && grep -F '"type": "sbom"' "$bake_plan_output" >/dev/null; then
    rm -f "$bake_plan_output"
    printf '%s\n' "Buildx bake plan enables SBOM attestation while SBOM=false" >&2
    exit 2
  fi

  if [ "$PROVENANCE" = "false" ] && grep -F '"type": "provenance"' "$bake_plan_output" >/dev/null; then
    rm -f "$bake_plan_output"
    printf '%s\n' "Buildx bake plan enables provenance attestation while PROVENANCE=false" >&2
    exit 2
  fi

  if [ "$SBOM" != "false" ] && ! grep -F '"type": "sbom"' "$bake_plan_output" >/dev/null; then
    rm -f "$bake_plan_output"
    printf '%s\n' "Buildx bake plan is missing SBOM attestation while SBOM=$SBOM" >&2
    exit 2
  fi

  if [ "$PROVENANCE" != "false" ] && ! grep -F '"type": "provenance"' "$bake_plan_output" >/dev/null; then
    rm -f "$bake_plan_output"
    printf '%s\n' "Buildx bake plan is missing provenance attestation while PROVENANCE=$PROVENANCE" >&2
    exit 2
  fi

  if [ "$PROVENANCE" = "mode=min" ] && ! grep -F '"mode": "min"' "$bake_plan_output" >/dev/null; then
    rm -f "$bake_plan_output"
    printf '%s\n' "Buildx bake plan is missing minimum provenance mode" >&2
    exit 2
  fi

  if [ "$PROVENANCE" = "mode=max" ] && ! grep -F '"mode": "max"' "$bake_plan_output" >/dev/null; then
    rm -f "$bake_plan_output"
    printf '%s\n' "Buildx bake plan is missing maximum provenance mode" >&2
    exit 2
  fi

  rm -f "$bake_plan_output"
}

load_image_build_settings
require_no_push_validation_mode
require_build_paths
require_dockerfile_oci_metadata
require_context_hygiene_contract
require_build_contract_guidance
validate_bake_plan
require_bake_plan_attestation_controls

printf '%s\n' "No-push build plan validation passed for $(image_build_ref)"
