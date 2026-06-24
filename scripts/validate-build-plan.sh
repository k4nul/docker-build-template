#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)
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

resolve_existing_dir() {
  dir_path=$1

  CDPATH= cd -- "$dir_path" && pwd -P
}

resolve_existing_file() {
  file_path=$1

  if command -v realpath >/dev/null 2>&1; then
    realpath "$file_path"
    return
  fi

  if readlink -f "$file_path" >/dev/null 2>&1; then
    readlink -f "$file_path"
    return
  fi

  if [ -L "$file_path" ]; then
    printf '%s\n' \
      "Cannot resolve Dockerfile symlink without realpath or readlink -f: $file_path" >&2
    exit 2
  fi

  file_dir=${file_path%/*}
  file_name=${file_path##*/}

  if [ "$file_dir" = "$file_path" ]; then
    file_dir=.
  fi

  resolved_dir=$(CDPATH= cd -- "$file_dir" && pwd -P)
  printf '%s/%s\n' "$resolved_dir" "$file_name"
}

require_repo_bound_path() {
  path_label=$1
  original_path=$2
  resolved_path=$3

  case "$resolved_path" in
    "$REPO_ROOT"|"$REPO_ROOT"/*) ;;
    *)
      printf '%s\n' "$path_label must stay inside repository: $original_path" >&2
      exit 2
      ;;
  esac
}

require_no_push_validation_mode() {
  if [ "$PUSH" != "false" ]; then
    printf '%s\n' "No-push validation requires PUSH=false" >&2
    exit 2
  fi
}

require_build_paths() {
  RESOLVED_LOCAL_CONTEXT=

  if ! is_remote_context "$CONTEXT"; then
    if [ ! -d "$CONTEXT" ]; then
      printf '%s\n' "Build context does not exist: $CONTEXT" >&2
      exit 2
    fi

    resolved_context=$(resolve_existing_dir "$CONTEXT")
    require_repo_bound_path "Build context" "$CONTEXT" "$resolved_context"
    RESOLVED_LOCAL_CONTEXT=$resolved_context
  fi

  if [ ! -f "$DOCKERFILE" ]; then
    printf '%s\n' "Dockerfile does not exist: $DOCKERFILE" >&2
    exit 2
  fi

  resolved_dockerfile=$(resolve_existing_file "$DOCKERFILE")
  require_repo_bound_path "Dockerfile" "$DOCKERFILE" "$resolved_dockerfile"
}

require_dockerfile_base_image_defaults() {
  dockerfile_to_check=$1
  base_image_defaults=$(grep -E '^ARG[[:space:]]+[A-Za-z0-9_]*IMAGE=' "$dockerfile_to_check" || true)

  if [ -z "$base_image_defaults" ]; then
    printf '%s\n' "Dockerfile must declare tagged base image ARG defaults ending in _IMAGE" >&2
    exit 2
  fi

  old_ifs=$IFS
  IFS='
'
  for base_image_line in $base_image_defaults; do
    IFS=$old_ifs
    set -- $base_image_line
    base_image_assignment=$2
    base_image_name=${base_image_assignment%%=*}
    base_image_value=${base_image_assignment#*=}

    if [ -z "$base_image_value" ]; then
      printf '%s\n' "Dockerfile base image default must not be empty: $base_image_name" >&2
      exit 2
    fi

    case "$base_image_value" in
      *:latest|*:latest@*)
        printf '%s%s=%s\n' \
          "Dockerfile must not use latest for base image default: " \
          "$base_image_name" "$base_image_value" >&2
        exit 2
        ;;
    esac

    case "$base_image_value" in
      *@sha256:*|*:*) ;;
      *)
        printf '%s%s=%s\n' \
          "Dockerfile base image default must include an explicit tag or digest: " \
          "$base_image_name" "$base_image_value" >&2
        exit 2
        ;;
    esac

    IFS='
'
  done
  IFS=$old_ifs
}

require_repository_template_paths() {
  for template_dockerfile in docker/Dockerfile docker/Dockerfile.*; do
    if [ ! -f "$template_dockerfile" ]; then
      continue
    fi

    resolved_template_dockerfile=$(resolve_existing_file "$template_dockerfile")
    require_repo_bound_path "Dockerfile" "$template_dockerfile" "$resolved_template_dockerfile"
  done
}

require_repository_template_base_image_defaults() {
  for template_dockerfile in docker/Dockerfile docker/Dockerfile.*; do
    if [ ! -f "$template_dockerfile" ]; then
      continue
    fi

    require_dockerfile_base_image_defaults "$template_dockerfile"
  done
}

require_dockerfile_oci_metadata() {
  dockerfile_to_check=$1

  for required_arg in \
    OCI_TITLE \
    OCI_DESCRIPTION \
    OCI_SOURCE \
    OCI_REVISION \
    OCI_LICENSES
  do
    if ! grep -Eq "^ARG[[:space:]]+$required_arg(=|$)" "$dockerfile_to_check"; then
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
    if ! grep -F -- "$required_label" "$dockerfile_to_check" >/dev/null; then
      printf '%s\n' "Dockerfile is missing required OCI label binding: $required_label" >&2
      exit 2
    fi
  done
}

require_repository_template_oci_metadata() {
  for template_dockerfile in docker/Dockerfile docker/Dockerfile.*; do
    if [ ! -f "$template_dockerfile" ]; then
      continue
    fi

    require_dockerfile_oci_metadata "$template_dockerfile"
  done
}

require_context_hygiene_contract() {
  dockerignore_path=.dockerignore
  dockerignore_label=.dockerignore

  if [ -n "${RESOLVED_LOCAL_CONTEXT:-}" ]; then
    dockerignore_path="$RESOLVED_LOCAL_CONTEXT/.dockerignore"
    if [ "$RESOLVED_LOCAL_CONTEXT" != "$REPO_ROOT" ]; then
      dockerignore_label="${CONTEXT%/}/.dockerignore"
    fi
  fi

  if [ ! -f "$dockerignore_path" ]; then
    printf '%s\n' ".dockerignore is required before validating a public build context" >&2
    printf '%s\n' "Missing build-context ignore file: $dockerignore_label" >&2
    exit 2
  fi

  for required_pattern in \
    ".git" \
    "config/*.env" \
    "config/image.env" \
    ".env" \
    ".env.*" \
    ".codex" \
    "AGENTS.md" \
    "docs/management" \
    "out" \
    "node_modules" \
    "dist" \
    "build" \
    "coverage" \
    ".cache" \
    ".npm" \
    "*.log" \
    "*.tar" \
    "*.tar.gz" \
    "*.oci" \
    "*.pem" \
    "*.key" \
    "id_rsa" \
    "id_ed25519"
  do
    if ! grep -Fx -- "$required_pattern" "$dockerignore_path" >/dev/null; then
      printf '%s\n' ".dockerignore is missing required pattern: $required_pattern" >&2
      printf '%s\n' "Checked build-context ignore file: $dockerignore_label" >&2
      exit 2
    fi
  done
}

require_build_contract_guidance() {
  if [ ! -f docs/build-contract.md ]; then
    printf '%s\n' \
      "docs/build-contract.md is required before validating supply-chain build guidance" >&2
    exit 2
  fi

  for required_guidance in \
    "Build context hygiene:" \
    "local configs, dotenv files, credentials" \
    'through `.dockerignore`' \
    "context and Dockerfile paths stay inside the repository" \
    "Build path safety:" \
    "Remote context values" \
    "must not contain URL userinfo or token-like material" \
    "Base image dependencies:" \
    "Dockerfile \`*_IMAGE\` argument defaults" \
    "Use explicit tags or digests" \
    "do not use" \
    "\`latest\`" \
    "Secret handling:" \
    "do not pass registry credentials, package tokens, or private" \
    "BuildKit secret" \
    "build path settings" \
    "build arguments, labels, or copied files" \
    "SBOM and provenance:" \
    "SBOM=false" \
    "PROVENANCE=false" \
    "PROVENANCE=mode=min" \
    "PROVENANCE=mode=max" \
    "attestation publishing" \
    "private image names" \
    "CI publish examples:" \
    "checked \`BAKE_PLAN_OUTPUT\`" \
    "hardcoded registry credentials" \
    "Direct \`scripts/build-image.sh\` calls with \`PUSH=true\` are rejected"
  do
    require_file_contains docs/build-contract.md "$required_guidance"
  done
}

write_bake_plan() {
  bake_plan_output=$(mktemp)
  export_image_build_settings

  if ! docker buildx bake --file buildx/docker-bake.hcl --print > "$bake_plan_output"; then
    rm -f "$bake_plan_output"
    return 1
  fi

  printf '%s\n' "$bake_plan_output"
}

require_bake_plan_contains() {
  bake_plan_output=$1
  required_text=$2
  failure_message=$3

  if ! grep -F "$required_text" "$bake_plan_output" >/dev/null; then
    printf '%s\n' "$failure_message" >&2
    return 1
  fi
}

require_bake_plan_omits() {
  bake_plan_output=$1
  forbidden_text=$2
  failure_message=$3

  if grep -F "$forbidden_text" "$bake_plan_output" >/dev/null; then
    printf '%s\n' "$failure_message" >&2
    return 1
  fi
}

exit_bake_plan_check_failed() {
  bake_plan_output=$1

  rm -f "$bake_plan_output"
  exit 2
}

require_bake_plan_check() {
  bake_plan_output=$1
  check_function=$2
  required_text=$3
  failure_message=$4

  "$check_function" "$bake_plan_output" "$required_text" "$failure_message" || {
    exit_bake_plan_check_failed "$bake_plan_output"
  }
}

persist_bake_plan_review_output() {
  bake_plan_output=$1

  if [ -z "${BAKE_PLAN_OUTPUT:-}" ]; then
    return 0
  fi

  case "$BAKE_PLAN_OUTPUT" in
    -)
      cat "$bake_plan_output"
      return 0
      ;;
  esac

  bake_plan_output_dir=${BAKE_PLAN_OUTPUT%/*}
  if [ "$bake_plan_output_dir" != "$BAKE_PLAN_OUTPUT" ] &&
    [ -n "$bake_plan_output_dir" ]; then
    mkdir -p "$bake_plan_output_dir"
  fi

  cp "$bake_plan_output" "$BAKE_PLAN_OUTPUT"
  printf '%s\n' "Wrote config-aware Buildx bake plan to $BAKE_PLAN_OUTPUT"
}

require_bake_plan_attestation_controls() {
  if ! bake_plan_output=$(write_bake_plan); then
    return 1
  fi

  require_bake_plan_check "$bake_plan_output" require_bake_plan_contains \
    '"output": [' \
    "Buildx bake plan is missing explicit no-push output"

  require_bake_plan_check "$bake_plan_output" require_bake_plan_contains \
    '"type": "cacheonly"' \
    "Buildx bake plan must use cache-only output while PUSH=false"

  require_bake_plan_check "$bake_plan_output" require_bake_plan_omits \
    '"type": "registry"' \
    "Buildx bake plan enables registry output while PUSH=false"

  if [ "$SBOM" = "false" ]; then
    require_bake_plan_check "$bake_plan_output" require_bake_plan_omits \
      '"type": "sbom"' \
      "Buildx bake plan enables SBOM attestation while SBOM=false"
  else
    require_bake_plan_check "$bake_plan_output" require_bake_plan_contains \
      '"type": "sbom"' \
      "Buildx bake plan is missing SBOM attestation while SBOM=$SBOM"
  fi

  if [ "$PROVENANCE" = "false" ]; then
    require_bake_plan_check "$bake_plan_output" require_bake_plan_omits \
      '"type": "provenance"' \
      "Buildx bake plan enables provenance attestation while PROVENANCE=false"
  else
    require_bake_plan_check "$bake_plan_output" require_bake_plan_contains \
      '"type": "provenance"' \
      "Buildx bake plan is missing provenance attestation while PROVENANCE=$PROVENANCE"
  fi

  case "$PROVENANCE" in
    mode=min)
      require_bake_plan_check "$bake_plan_output" require_bake_plan_contains \
        '"mode": "min"' \
        "Buildx bake plan is missing minimum provenance mode"
      ;;
    mode=max)
      require_bake_plan_check "$bake_plan_output" require_bake_plan_contains \
        '"mode": "max"' \
        "Buildx bake plan is missing maximum provenance mode"
      ;;
  esac

  if ! persist_bake_plan_review_output "$bake_plan_output"; then
    exit_bake_plan_check_failed "$bake_plan_output"
  fi

  rm -f "$bake_plan_output"
}

load_image_build_settings
require_no_push_validation_mode
require_build_paths
require_dockerfile_base_image_defaults "$DOCKERFILE"
require_repository_template_paths
require_repository_template_base_image_defaults
require_dockerfile_oci_metadata "$DOCKERFILE"
require_repository_template_oci_metadata
require_context_hygiene_contract
require_build_contract_guidance
require_bake_plan_attestation_controls

printf '%s\n' "No-push build plan validation passed for $(image_build_ref)"
