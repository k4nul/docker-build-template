#!/usr/bin/env sh
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/docker-build-template-build-tests.XXXXXX")
STUB_DIR="$TEST_ROOT/bin"
TESTS_RUN=0

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
} >> "$DOCKER_STUB_LOG"

if [ "$#" -ge 3 ] &&
  [ "$1" = "buildx" ] &&
  [ "$2" = "build" ]; then
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
  cp -R "$REPO_ROOT/config" "$FIXTURE_DIR/"
  cp -R "$REPO_ROOT/scripts" "$FIXTURE_DIR/"
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

  assert_log_contains "<--tag> <registry.example.com/team/push-app:3.0.0>"
  assert_log_contains "<--provenance> <mode=max>"
  assert_log_contains "<--push> <.>"
  assert_log_not_contains "<--load>"
  pass "push wrapper forces registry output while preserving configured attestations"
}

install_docker_stub
test_default_build_loads_without_attestations
test_attestation_controls_are_forwarded_to_buildx
test_push_script_forces_registry_output

printf '1..%s\n' "$TESTS_RUN"
