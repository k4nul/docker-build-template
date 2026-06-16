#!/usr/bin/env sh
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/docker-build-template-config-tests.XXXXXX")
TESTS_RUN=0
PROBE_OUTPUT=
PROBE_STATUS=

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT HUP INT TERM

fail() {
  printf 'not ok - %s\n' "$1" >&2
  if [ -n "${PROBE_OUTPUT:-}" ]; then
    printf '%s\n' "probe output:" >&2
    printf '%s\n' "$PROBE_OUTPUT" >&2
  fi
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_status() {
  expected_status=$1
  if [ "$PROBE_STATUS" -ne "$expected_status" ]; then
    fail "expected status $expected_status, got $PROBE_STATUS"
  fi
}

assert_output_contains() {
  expected_output=$1
  case "$PROBE_OUTPUT" in
    *"$expected_output"*) ;;
    *) fail "expected output to contain: $expected_output" ;;
  esac
}

run_config_probe() {
  output_file=$1
  shift

  set +e
  (
    cd "$REPO_ROOT"
    . ./scripts/build-config.sh
    "$@"
  ) > "$output_file" 2>&1
  PROBE_STATUS=$?
  set -e

  PROBE_OUTPUT=$(cat "$output_file")
}

print_loaded_settings() {
  load_image_build_settings
  printf 'REGISTRY=%s\n' "$REGISTRY"
  printf 'IMAGE_NAME=%s\n' "$IMAGE_NAME"
  printf 'IMAGE_TAG=%s\n' "$IMAGE_TAG"
  printf 'CONTEXT=%s\n' "$CONTEXT"
  printf 'DOCKERFILE=%s\n' "$DOCKERFILE"
  printf 'PLATFORMS=%s\n' "$PLATFORMS"
  printf 'PUSH=%s\n' "$PUSH"
  printf 'SBOM=%s\n' "$SBOM"
  printf 'PROVENANCE=%s\n' "$PROVENANCE"
  printf 'OCI_TITLE=%s\n' "$OCI_TITLE"
  printf 'OCI_DESCRIPTION=%s\n' "$OCI_DESCRIPTION"
  printf 'OCI_SOURCE=%s\n' "$OCI_SOURCE"
  printf 'OCI_REVISION=%s\n' "$OCI_REVISION"
  printf 'OCI_LICENSES=%s\n' "$OCI_LICENSES"
  printf 'IMAGE_REF=%s\n' "$(image_build_ref)"
  printf 'OUTPUT_FLAG=%s\n' "$(image_build_output_flag)"
}

print_exported_settings() {
  load_image_build_settings
  export_image_build_settings
  exported_settings_pattern="^(REGISTRY|IMAGE_NAME|IMAGE_TAG|CONTEXT|DOCKERFILE|"
  exported_settings_pattern="${exported_settings_pattern}PLATFORMS|PUSH|SBOM|"
  exported_settings_pattern="${exported_settings_pattern}PROVENANCE|OCI_TITLE|"
  exported_settings_pattern="${exported_settings_pattern}OCI_DESCRIPTION|OCI_SOURCE|"
  exported_settings_pattern="${exported_settings_pattern}OCI_REVISION|OCI_LICENSES)="
  env | grep -E "$exported_settings_pattern" | sort
}

test_defaults_are_applied_when_no_config_file_is_forced() {
  TESTS_RUN=$((TESTS_RUN + 1))
  output_file="$TEST_ROOT/defaults.out"

  run_config_probe "$output_file" print_loaded_settings

  assert_status 0
  assert_output_contains "REGISTRY="
  assert_output_contains "IMAGE_NAME=example-app"
  assert_output_contains "IMAGE_TAG=0.1.0"
  assert_output_contains "CONTEXT=."
  assert_output_contains "DOCKERFILE=docker/Dockerfile"
  assert_output_contains "PLATFORMS=linux/amd64"
  assert_output_contains "PUSH=false"
  assert_output_contains "SBOM=false"
  assert_output_contains "PROVENANCE=false"
  assert_output_contains "OCI_TITLE=Example App"
  assert_output_contains "IMAGE_REF=example-app:0.1.0"
  assert_output_contains "OUTPUT_FLAG=--load"
  pass "default build settings are applied without requiring a local image env file"
}

test_config_file_supports_exports_quotes_and_build_ref() {
  TESTS_RUN=$((TESTS_RUN + 1))
  config_file="$TEST_ROOT/quoted.env"
  output_file="$TEST_ROOT/quoted.out"

  cat > "$config_file" <<'EOF'
# Comments and blank lines should be ignored.

export REGISTRY=registry.example.com/team/
IMAGE_NAME='quoted-app'
IMAGE_TAG="2026.06.15"
CONTEXT=examples/app
DOCKERFILE=docker/Dockerfile.multistage
PLATFORMS=linux/amd64,linux/arm64
PUSH=true
SBOM=true
PROVENANCE=mode=max
OCI_TITLE='Quoted App'
OCI_DESCRIPTION="Quoted image description"
OCI_SOURCE=https://example.com/quoted-app
OCI_REVISION=rev-123
OCI_LICENSES=Apache-2.0
EOF

  CONFIG_FILE="$config_file" run_config_probe "$output_file" print_loaded_settings

  assert_status 0
  assert_output_contains "REGISTRY=registry.example.com/team/"
  assert_output_contains "IMAGE_NAME=quoted-app"
  assert_output_contains "IMAGE_TAG=2026.06.15"
  assert_output_contains "CONTEXT=examples/app"
  assert_output_contains "DOCKERFILE=docker/Dockerfile.multistage"
  assert_output_contains "PLATFORMS=linux/amd64,linux/arm64"
  assert_output_contains "PUSH=true"
  assert_output_contains "SBOM=true"
  assert_output_contains "PROVENANCE=mode=max"
  assert_output_contains "OCI_TITLE=Quoted App"
  assert_output_contains "OCI_DESCRIPTION=Quoted image description"
  assert_output_contains "IMAGE_REF=registry.example.com/team/quoted-app:2026.06.15"
  assert_output_contains "OUTPUT_FLAG=--push"
  pass "config files support export prefixes, quoted values, and image reference output"
}

test_environment_values_override_config_file_values() {
  TESTS_RUN=$((TESTS_RUN + 1))
  config_file="$TEST_ROOT/env-precedence.env"
  output_file="$TEST_ROOT/env-precedence.out"

  cat > "$config_file" <<'EOF'
IMAGE_NAME=config-app
IMAGE_TAG=config-tag
PUSH=false
SBOM=false
PROVENANCE=false
EOF

  CONFIG_FILE="$config_file" \
    IMAGE_NAME=env-app \
    IMAGE_TAG=env-tag \
    PUSH=true \
    SBOM=true \
    PROVENANCE=mode=min \
    run_config_probe "$output_file" print_loaded_settings

  assert_status 0
  assert_output_contains "IMAGE_NAME=env-app"
  assert_output_contains "IMAGE_TAG=env-tag"
  assert_output_contains "PUSH=true"
  assert_output_contains "SBOM=true"
  assert_output_contains "PROVENANCE=mode=min"
  assert_output_contains "IMAGE_REF=env-app:env-tag"
  assert_output_contains "OUTPUT_FLAG=--push"
  pass "environment values take precedence over config file values"
}

test_invalid_config_lines_are_rejected() {
  TESTS_RUN=$((TESTS_RUN + 1))
  config_file="$TEST_ROOT/invalid-line.env"
  output_file="$TEST_ROOT/invalid-line.out"

  cat > "$config_file" <<'EOF'
IMAGE_NAME
EOF

  CONFIG_FILE="$config_file" run_config_probe "$output_file" print_loaded_settings

  assert_status 2
  assert_output_contains "Invalid config line in $config_file: IMAGE_NAME"
  pass "config lines without assignments are rejected"
}

test_unsupported_config_keys_are_rejected() {
  TESTS_RUN=$((TESTS_RUN + 1))
  config_file="$TEST_ROOT/unsupported-key.env"
  output_file="$TEST_ROOT/unsupported-key.out"

  cat > "$config_file" <<'EOF'
IMAGE_NAME=example-app
REGISTRY_USER=not-supported
EOF

  CONFIG_FILE="$config_file" run_config_probe "$output_file" print_loaded_settings

  assert_status 2
  assert_output_contains "Unsupported config key in $config_file: REGISTRY_USER"
  pass "unsupported config keys are rejected"
}

test_invalid_boolean_and_provenance_values_are_rejected() {
  TESTS_RUN=$((TESTS_RUN + 1))
  config_file="$TEST_ROOT/invalid-controls.env"
  output_file="$TEST_ROOT/invalid-controls.out"

  cat > "$config_file" <<'EOF'
PUSH=maybe
SBOM=enabled
PROVENANCE=full
EOF

  CONFIG_FILE="$config_file" run_config_probe "$output_file" print_loaded_settings

  assert_status 2
  assert_output_contains "PUSH must be true or false"
  pass "invalid boolean and provenance controls are rejected during validation"
}

test_empty_config_values_fall_back_to_defaults() {
  TESTS_RUN=$((TESTS_RUN + 1))
  config_file="$TEST_ROOT/empty-values.env"
  output_file="$TEST_ROOT/empty-values.out"

  cat > "$config_file" <<'EOF'
IMAGE_NAME=
IMAGE_TAG=
OCI_TITLE=
EOF

  CONFIG_FILE="$config_file" run_config_probe "$output_file" print_loaded_settings

  assert_status 0
  assert_output_contains "IMAGE_NAME=example-app"
  assert_output_contains "IMAGE_TAG=0.1.0"
  assert_output_contains "OCI_TITLE=Example App"
  assert_output_contains "IMAGE_REF=example-app:0.1.0"
  pass "empty config values fall back to defaults"
}

test_missing_explicit_config_file_is_rejected() {
  TESTS_RUN=$((TESTS_RUN + 1))
  output_file="$TEST_ROOT/missing-config.out"
  missing_config="$TEST_ROOT/missing.env"

  CONFIG_FILE="$missing_config" run_config_probe "$output_file" print_loaded_settings

  assert_status 2
  assert_output_contains "CONFIG_FILE does not exist: $missing_config"
  pass "explicit missing config files are rejected"
}

test_defaults_remain_valid_when_exported_for_buildx() {
  TESTS_RUN=$((TESTS_RUN + 1))
  output_file="$TEST_ROOT/exported.out"

  run_config_probe "$output_file" print_exported_settings

  assert_status 0
  assert_output_contains "IMAGE_NAME=example-app"
  assert_output_contains "IMAGE_TAG=0.1.0"
  assert_output_contains "PUSH=false"
  assert_output_contains "SBOM=false"
  assert_output_contains "PROVENANCE=false"
  assert_output_contains "OCI_REVISION=unknown"
  pass "loaded settings are exported for buildx bake consumers"
}

test_defaults_are_applied_when_no_config_file_is_forced
test_config_file_supports_exports_quotes_and_build_ref
test_environment_values_override_config_file_values
test_invalid_config_lines_are_rejected
test_unsupported_config_keys_are_rejected
test_invalid_boolean_and_provenance_values_are_rejected
test_empty_config_values_fall_back_to_defaults
test_missing_explicit_config_file_is_rejected
test_defaults_remain_valid_when_exported_for_buildx

printf '1..%s\n' "$TESTS_RUN"
