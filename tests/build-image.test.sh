#!/usr/bin/env sh
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/docker-build-template-build-tests.XXXXXX")
STUB_DIR="$TEST_ROOT/bin"
TESTS_RUN=0
BUILD_OUTPUT=
BUILD_STATUS=

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT HUP INT TERM

fail() {
  printf 'not ok - %s\n' "$1" >&2
  if [ -f "${DOCKER_STUB_LOG:-}" ]; then
    printf '%s\n' "docker calls:" >&2
    cat "$DOCKER_STUB_LOG" >&2
  fi
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_log_contains() {
  expected_output=$1
  if ! grep -F -- "$expected_output" "$DOCKER_STUB_LOG" >/dev/null; then
    fail "expected docker log to contain: $expected_output"
  fi
}

assert_log_not_contains() {
  unexpected_output=$1
  if grep -F -- "$unexpected_output" "$DOCKER_STUB_LOG" >/dev/null; then
    fail "expected docker log not to contain: $unexpected_output"
  fi
}

assert_log_empty() {
  if [ -s "$DOCKER_STUB_LOG" ]; then
    fail "expected no docker calls"
  fi
}

assert_log_order() {
  first_output=$1
  second_output=$2

  first_line=$(grep -n -F -- "$first_output" "$DOCKER_STUB_LOG" | head -n 1 | cut -d: -f1 || true)
  second_line=$(grep -n -F -- "$second_output" "$DOCKER_STUB_LOG" | head -n 1 | cut -d: -f1 || true)

  if [ -z "$first_line" ]; then
    fail "expected docker log to contain first ordered entry: $first_output"
  fi

  if [ -z "$second_line" ]; then
    fail "expected docker log to contain second ordered entry: $second_output"
  fi

  if [ "$first_line" -ge "$second_line" ]; then
    fail "expected '$first_output' to appear before '$second_output'"
  fi
}

assert_build_status() {
  expected_status=$1
  if [ "$BUILD_STATUS" -ne "$expected_status" ]; then
    fail "expected build status $expected_status, got $BUILD_STATUS"
  fi
}

assert_build_output_contains() {
  expected_output=$1
  case "$BUILD_OUTPUT" in
    *"$expected_output"*) ;;
    *) fail "expected build output to contain: $expected_output" ;;
  esac
}

install_docker_stub() {
  mkdir -p "$STUB_DIR"
  cat > "$STUB_DIR/docker" <<'SH'
#!/usr/bin/env sh
set -eu

: "${DOCKER_STUB_LOG:?}"

{
  printf 'args:'
  for arg do
    printf ' <%s>' "$arg"
  done
  printf '\n'
  printf 'pwd: <%s>\n' "$(pwd)"
  printf 'PUSH: <%s>\n' "${PUSH-}"
} >> "$DOCKER_STUB_LOG"

if [ "$#" -ge 3 ] &&
  [ "$1" = "buildx" ] &&
  [ "$2" = "build" ]; then
  exit 0
fi

if [ "$#" -eq 5 ] &&
  [ "$1" = "buildx" ] &&
  [ "$2" = "bake" ] &&
  [ "$3" = "--file" ] &&
  [ "$4" = "buildx/docker-bake.hcl" ] &&
  [ "$5" = "--print" ]; then
  if [ "${IMAGE_NAME-}" = "push-missing-sbom-app" ]; then
    printf '{\n'
    printf '  "target": {"default": {"attest": []}}\n'
    printf '}\n'
    exit 0
  fi
  printf '{\n'
  printf '  "target": {\n'
  printf '    "default": {\n'
  if [ "${SBOM-}" = "true" ] || [ "${PROVENANCE-}" != "false" ]; then
    printf '      "attest": [\n'
    if [ "${SBOM-}" = "true" ]; then
      printf '        {"type": "sbom"}'
      if [ "${PROVENANCE-}" != "false" ]; then
        printf ',\n'
      else
        printf '\n'
      fi
    fi
    if [ "${PROVENANCE-}" = "mode=min" ]; then
      printf '        {"type": "provenance", "mode": "min"}\n'
    elif [ "${PROVENANCE-}" = "mode=max" ]; then
      printf '        {"type": "provenance", "mode": "max"}\n'
    elif [ "${PROVENANCE-}" = "true" ]; then
      printf '        {"type": "provenance"}\n'
    fi
    printf '      ]\n'
  else
    printf '      "attest": []\n'
  fi
  printf '    }\n'
  printf '  }\n'
  printf '}\n'
  exit 0
fi

printf 'unexpected docker command:' >&2
for arg do
  printf ' <%s>' "$arg" >&2
done
printf '\n' >&2
exit 99
SH
  chmod +x "$STUB_DIR/docker"
}

make_fixture() {
  fixture_name=$1
  FIXTURE_DIR="$TEST_ROOT/$fixture_name"
  mkdir -p "$FIXTURE_DIR"
  cp -R "$REPO_ROOT/buildx" "$FIXTURE_DIR/"
  cp -R "$REPO_ROOT/config" "$FIXTURE_DIR/"
  cp -R "$REPO_ROOT/docker" "$FIXTURE_DIR/"
  cp -R "$REPO_ROOT/scripts" "$FIXTURE_DIR/"
  mkdir -p "$FIXTURE_DIR/docs"
  cp "$REPO_ROOT/docs/build-contract.md" "$FIXTURE_DIR/docs/build-contract.md"
  cp "$REPO_ROOT/.dockerignore" "$FIXTURE_DIR/.dockerignore"
}

run_build_script() {
  fixture_dir=$1
  script_path=$2
  config_file=$3
  DOCKER_STUB_LOG="$fixture_dir/docker.log"
  export DOCKER_STUB_LOG
  : > "$DOCKER_STUB_LOG"

  (
    cd "$fixture_dir"
    PATH="$STUB_DIR:$PATH" CONFIG_FILE="$config_file" "$script_path"
  )
}

run_build_script_probe() {
  fixture_dir=$1
  script_path=$2
  config_file=$3
  output_file="$fixture_dir/build.out"
  DOCKER_STUB_LOG="$fixture_dir/docker.log"
  export DOCKER_STUB_LOG
  : > "$DOCKER_STUB_LOG"

  set +e
  (
    cd "$fixture_dir"
    PATH="$STUB_DIR:$PATH" CONFIG_FILE="$config_file" "$script_path"
  ) > "$output_file" 2>&1
  BUILD_STATUS=$?
  set -e

  BUILD_OUTPUT=$(cat "$output_file")
}

run_build_script_from_dir() {
  fixture_dir=$1
  script_path=$2
  config_file=$3
  run_dir=$4
  DOCKER_STUB_LOG="$fixture_dir/docker.log"
  export DOCKER_STUB_LOG
  : > "$DOCKER_STUB_LOG"

  (
    cd "$run_dir"
    PATH="$STUB_DIR:$PATH" CONFIG_FILE="$config_file" "$script_path"
  )
}

run_push_script_with_push_override() {
  fixture_dir=$1
  script_path=$2
  config_file=$3
  DOCKER_STUB_LOG="$fixture_dir/docker.log"
  export DOCKER_STUB_LOG
  : > "$DOCKER_STUB_LOG"

  (
    cd "$fixture_dir"
    PATH="$STUB_DIR:$PATH" CONFIG_FILE="$config_file" PUSH=true "$script_path"
  )
}

test_default_build_loads_without_attestations() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "default-build"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
REGISTRY=
IMAGE_NAME=example-app
IMAGE_TAG=0.1.0
PUSH=false
EOF

  run_build_script "$FIXTURE_DIR" ./scripts/build-image.sh "$FIXTURE_DIR/config/test.env"

  assert_log_contains "args: <buildx> <build>"
  assert_log_contains "<--tag> <example-app:0.1.0>"
  assert_log_contains "<--load> <.>"
  assert_log_not_contains "<--push>"
  assert_log_not_contains "<--sbom>"
  assert_log_not_contains "<--provenance>"
  pass "default build uses local load without attestation flags"
}

test_attestation_controls_are_forwarded_to_buildx() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "attestation-build"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
REGISTRY=registry.example.com/team/
IMAGE_NAME=attested-app
IMAGE_TAG=2.0.0
PUSH=false
SBOM=true
PROVENANCE=mode=min
EOF

  run_build_script "$FIXTURE_DIR" ./scripts/build-image.sh "$FIXTURE_DIR/config/test.env"

  assert_log_contains "<--tag> <registry.example.com/team/attested-app:2.0.0>"
  assert_log_contains "<--sbom> <true>"
  assert_log_contains "<--provenance> <mode=min>"
  assert_log_contains "<--load> <.>"
  assert_log_not_contains "<--push>"
  pass "attestation controls are forwarded to docker buildx build"
}

test_push_script_forces_registry_output() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "push-build"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
REGISTRY=registry.example.com/team/
IMAGE_NAME=push-app
IMAGE_TAG=3.0.0
PUSH=false
PROVENANCE=mode=max
EOF

  run_build_script "$FIXTURE_DIR" ./scripts/push-image.sh "$FIXTURE_DIR/config/test.env"

  assert_log_contains "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>"
  assert_log_contains "args: <buildx> <build>"
  assert_log_order \
    "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>" \
    "args: <buildx> <build>"
  assert_log_order "PUSH: <false>" "PUSH: <true>"
  assert_log_contains "<--tag> <registry.example.com/team/push-app:3.0.0>"
  assert_log_contains "<--provenance> <mode=max>"
  assert_log_contains "<--push> <.>"
  assert_log_not_contains "<--load>"
  pass "push wrapper forces registry output while preserving configured attestations"
}

test_push_script_builds_from_repo_root_when_called_elsewhere() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "push-outside-cwd"
  run_dir="$TEST_ROOT/outside-cwd"
  mkdir -p "$run_dir"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
REGISTRY=registry.example.com/team/
IMAGE_NAME=outside-cwd-app
IMAGE_TAG=3.1.0
PUSH=false
EOF

  run_build_script_from_dir \
    "$FIXTURE_DIR" \
    "$FIXTURE_DIR/scripts/push-image.sh" \
    "$FIXTURE_DIR/config/test.env" \
    "$run_dir"

  assert_log_contains "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>"
  assert_log_contains "args: <buildx> <build>"
  assert_log_contains "pwd: <$FIXTURE_DIR>"
  assert_log_contains "<--tag> <registry.example.com/team/outside-cwd-app:3.1.0>"
  assert_log_contains "<--push> <.>"
  pass "push wrapper validates and builds from the repository root when called elsewhere"
}

test_push_script_forces_no_push_validation_with_push_environment() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "push-env-override"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
REGISTRY=registry.example.com/team/
IMAGE_NAME=env-push-app
IMAGE_TAG=3.2.0
PUSH=false
EOF

  run_push_script_with_push_override \
    "$FIXTURE_DIR" \
    ./scripts/push-image.sh \
    "$FIXTURE_DIR/config/test.env"

  assert_log_order \
    "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>" \
    "args: <buildx> <build>"
  assert_log_order "PUSH: <false>" "PUSH: <true>"
  assert_log_contains "<--tag> <registry.example.com/team/env-push-app:3.2.0>"
  assert_log_contains "<--push> <.>"
  assert_log_not_contains "<--load>"
  pass "push wrapper validates in no-push mode even when the environment starts with PUSH=true"
}

test_push_script_forces_no_push_validation_with_push_config() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "push-config-override"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
REGISTRY=registry.example.com/team/
IMAGE_NAME=config-push-app
IMAGE_TAG=3.2.1
PLATFORMS=linux/amd64,linux/arm64
PUSH=true
EOF

  run_build_script "$FIXTURE_DIR" ./scripts/push-image.sh "$FIXTURE_DIR/config/test.env"

  assert_log_order \
    "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>" \
    "args: <buildx> <build>"
  assert_log_order "PUSH: <false>" "PUSH: <true>"
  assert_log_contains "<--platform> <linux/amd64,linux/arm64>"
  assert_log_contains "<--tag> <registry.example.com/team/config-push-app:3.2.1>"
  assert_log_contains "<--push> <.>"
  assert_log_not_contains "<--load>"
  pass "push wrapper validates in no-push mode even when config requests a multi-platform push"
}

test_push_script_stops_before_push_when_validation_fails() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "push-validation-failure"
  rm "$FIXTURE_DIR/docs/build-contract.md"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
REGISTRY=registry.example.com/team/
IMAGE_NAME=blocked-push-app
IMAGE_TAG=3.3.0
PUSH=false
EOF

  run_build_script_probe "$FIXTURE_DIR" ./scripts/push-image.sh "$FIXTURE_DIR/config/test.env"

  assert_build_status 2
  assert_build_output_contains \
    "docs/build-contract.md is required before validating supply-chain build guidance"
  assert_log_empty
  pass "push wrapper stops before docker calls when no-push validation fails"
}

test_push_script_stops_after_bake_plan_validation_fails() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "push-bake-validation-failure"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
REGISTRY=registry.example.com/team/
IMAGE_NAME=push-missing-sbom-app
IMAGE_TAG=3.4.0
PUSH=false
SBOM=true
PROVENANCE=false
EOF

  run_build_script_probe "$FIXTURE_DIR" ./scripts/push-image.sh "$FIXTURE_DIR/config/test.env"

  assert_build_status 2
  assert_build_output_contains "Buildx bake plan is missing SBOM attestation while SBOM=true"
  assert_log_contains "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>"
  assert_log_contains "PUSH: <false>"
  assert_log_not_contains "args: <buildx> <build>"
  assert_log_not_contains "PUSH: <true>"
  pass "push wrapper stops before registry build when bake-plan validation fails"
}

test_direct_push_requires_validated_wrapper() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "direct-push"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
REGISTRY=registry.example.com/team/
IMAGE_NAME=direct-push-app
IMAGE_TAG=4.0.0
PUSH=true
EOF

  run_build_script_probe "$FIXTURE_DIR" ./scripts/build-image.sh "$FIXTURE_DIR/config/test.env"

  assert_build_status 2
  assert_build_output_contains \
    "PUSH=true builds must run through scripts/push-image.sh after no-push validation"
  assert_log_empty
  pass "direct PUSH=true builds are rejected before docker buildx build"
}

test_multi_platform_local_load_is_rejected() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "multi-platform-load"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
IMAGE_NAME=multi-platform-load-app
PLATFORMS=linux/amd64,linux/arm64
PUSH=false
EOF

  run_build_script_probe "$FIXTURE_DIR" ./scripts/build-image.sh "$FIXTURE_DIR/config/test.env"

  assert_build_status 2
  assert_build_output_contains \
    "PUSH=false local loads require a single platform; use scripts/push-image.sh for multi-platform registry output"
  assert_log_empty
  pass "direct local loads reject multi-platform output before docker buildx build"
}

install_docker_stub
test_default_build_loads_without_attestations
test_attestation_controls_are_forwarded_to_buildx
test_push_script_forces_registry_output
test_push_script_builds_from_repo_root_when_called_elsewhere
test_push_script_forces_no_push_validation_with_push_environment
test_push_script_forces_no_push_validation_with_push_config
test_push_script_stops_before_push_when_validation_fails
test_push_script_stops_after_bake_plan_validation_fails
test_direct_push_requires_validated_wrapper
test_multi_platform_local_load_is_rejected

printf '1..%s\n' "$TESTS_RUN"
