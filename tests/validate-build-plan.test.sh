#!/usr/bin/env sh
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/docker-build-template-tests.XXXXXX")
STUB_DIR="$TEST_ROOT/bin"
VALIDATOR_OUTPUT=
VALIDATOR_STATUS=
TESTS_RUN=0

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT HUP INT TERM

fail() {
  printf 'not ok - %s\n' "$1" >&2
  if [ -n "${VALIDATOR_OUTPUT:-}" ]; then
    printf '%s\n' "validator output:" >&2
    printf '%s\n' "$VALIDATOR_OUTPUT" >&2
  fi
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_status() {
  expected_status=$1
  if [ "$VALIDATOR_STATUS" -ne "$expected_status" ]; then
    fail "expected status $expected_status, got $VALIDATOR_STATUS"
  fi
}

assert_output_contains() {
  expected_output=$1
  case "$VALIDATOR_OUTPUT" in
    *"$expected_output"*) ;;
    *) fail "expected output to contain: $expected_output" ;;
  esac
}

assert_file_contains() {
  file_path=$1
  expected_output=$2
  if ! grep -F -- "$expected_output" "$file_path" >/dev/null; then
    fail "expected $file_path to contain: $expected_output"
  fi
}

assert_no_docker_calls() {
  log_file=$1
  if [ -s "$log_file" ]; then
    fail "expected no docker calls, got: $(cat "$log_file")"
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
  printf 'REGISTRY=%s\n' "${REGISTRY-}"
  printf 'IMAGE_NAME=%s\n' "${IMAGE_NAME-}"
  printf 'IMAGE_TAG=%s\n' "${IMAGE_TAG-}"
  printf 'CONTEXT=%s\n' "${CONTEXT-}"
  printf 'DOCKERFILE=%s\n' "${DOCKERFILE-}"
  printf 'PLATFORMS=%s\n' "${PLATFORMS-}"
  printf 'PUSH=%s\n' "${PUSH-}"
  printf 'SBOM=%s\n' "${SBOM-}"
  printf 'PROVENANCE=%s\n' "${PROVENANCE-}"
  printf 'OCI_TITLE=%s\n' "${OCI_TITLE-}"
} >> "$DOCKER_STUB_LOG"

if [ "$#" -eq 5 ] &&
  [ "$1" = "buildx" ] &&
  [ "$2" = "bake" ] &&
  [ "$3" = "--file" ] &&
  [ "$4" = "buildx/docker-bake.hcl" ] &&
  [ "$5" = "--print" ]; then
  if [ "${IMAGE_NAME-}" = "missing-sbom-app" ]; then
    printf '{\n'
    printf '  "target": {"default": {"attest": []}}\n'
    printf '}\n'
    exit 0
  fi
  if [ "${IMAGE_NAME-}" = "unexpected-provenance-app" ]; then
    printf '{\n'
    printf '  "target": {"default": {"attest": [{"type": "provenance"}]}}\n'
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

run_validator() {
  fixture_dir=$1
  config_file=$2
  output_file="$fixture_dir/validator.out"
  log_file="$fixture_dir/docker.log"
  : > "$log_file"

  set +e
  (
    cd "$fixture_dir"
    PATH="$STUB_DIR:$PATH" \
      DOCKER_STUB_LOG="$log_file" \
      CONFIG_FILE="$config_file" \
      ./scripts/validate-build-plan.sh
  ) > "$output_file" 2>&1
  VALIDATOR_STATUS=$?
  set -e

  VALIDATOR_OUTPUT=$(cat "$output_file")
}

test_success_uses_no_push_bake_plan() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "success"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
# Supported config syntax should be accepted by no-push validation.
export REGISTRY=registry.example.com/team/
IMAGE_NAME='validated-app'
IMAGE_TAG="1.2.3"
CONTEXT=.
DOCKERFILE=docker/Dockerfile
PLATFORMS=linux/amd64,linux/arm64
PUSH=false
OCI_TITLE='Validated App'
OCI_DESCRIPTION="Validated image"
OCI_SOURCE=https://example.com/validated-app
OCI_REVISION=abc123
OCI_LICENSES=MIT
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 0
  assert_output_contains "No-push build plan validation passed for registry.example.com/team/validated-app:1.2.3"
  assert_file_contains "$FIXTURE_DIR/docker.log" "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>"
  assert_file_contains "$FIXTURE_DIR/docker.log" "REGISTRY=registry.example.com/team/"
  assert_file_contains "$FIXTURE_DIR/docker.log" "IMAGE_NAME=validated-app"
  assert_file_contains "$FIXTURE_DIR/docker.log" "IMAGE_TAG=1.2.3"
  assert_file_contains "$FIXTURE_DIR/docker.log" "PLATFORMS=linux/amd64,linux/arm64"
  assert_file_contains "$FIXTURE_DIR/docker.log" "PUSH=false"
  assert_file_contains "$FIXTURE_DIR/docker.log" "SBOM=false"
  assert_file_contains "$FIXTURE_DIR/docker.log" "PROVENANCE=false"
  assert_file_contains "$FIXTURE_DIR/docker.log" "OCI_TITLE=Validated App"
  pass "no-push validation exports settings and prints the bake plan"
}

test_attestation_controls_are_visible_in_no_push_bake_plan() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "attestation-controls"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
SBOM=true
PROVENANCE=mode=min
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 0
  assert_file_contains "$FIXTURE_DIR/docker.log" "SBOM=true"
  assert_file_contains "$FIXTURE_DIR/docker.log" "PROVENANCE=mode=min"
  assert_file_contains "$FIXTURE_DIR/docker.log" "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>"
  pass "attestation controls are exported into the no-push bake plan"
}

test_missing_sbom_attestation_is_rejected() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "missing-sbom-attestation"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
IMAGE_NAME=missing-sbom-app
SBOM=true
PROVENANCE=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Buildx bake plan is missing SBOM attestation while SBOM=true"
  pass "enabled SBOM must appear in the no-push bake plan"
}

test_disabled_provenance_attestation_is_rejected() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "unexpected-provenance-attestation"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
IMAGE_NAME=unexpected-provenance-app
PROVENANCE=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Buildx bake plan enables provenance attestation while PROVENANCE=false"
  pass "disabled provenance must be absent from the no-push bake plan"
}

test_unsupported_attestation_controls_are_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "invalid-attestation-controls"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
SBOM=maybe
PROVENANCE=full
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "SBOM must be true or false"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "unsupported attestation controls are rejected before docker buildx bake"
}

test_multistage_template_satisfies_oci_gate() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "multistage"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
DOCKERFILE=docker/Dockerfile.multistage
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 0
  assert_file_contains "$FIXTURE_DIR/docker.log" "DOCKERFILE=docker/Dockerfile.multistage"
  assert_file_contains "$FIXTURE_DIR/docker.log" "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>"
  pass "multistage template satisfies required OCI label validation"
}

test_push_true_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "push-true"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=true
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "No-push validation requires PUSH=false"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "PUSH=true is rejected before docker buildx bake"
}

test_missing_local_context_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "missing-context"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
CONTEXT=missing-context
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Build context does not exist: missing-context"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "missing local context is rejected before docker buildx bake"
}

test_parent_context_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "parent-context"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
CONTEXT=..
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Build context must stay inside repository: .."
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "parent-directory context is rejected before docker buildx bake"
}

test_dockerfile_outside_repo_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "outside-dockerfile"
  printf '%s\n' "FROM scratch" > "$TEST_ROOT/outside.Dockerfile"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
DOCKERFILE=../outside.Dockerfile
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Dockerfile must stay inside repository: ../outside.Dockerfile"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "Dockerfile outside the repository is rejected before docker buildx bake"
}

test_explicit_missing_config_file_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "missing-config"

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/missing.env"

  assert_status 2
  assert_output_contains "CONFIG_FILE does not exist: $FIXTURE_DIR/config/missing.env"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "explicit missing CONFIG_FILE is rejected before docker buildx bake"
}

test_required_dockerignore_patterns_are_enforced() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "dockerignore"
  grep -Fxv -- "config/image.env" "$FIXTURE_DIR/.dockerignore" > "$FIXTURE_DIR/.dockerignore.tmp"
  mv "$FIXTURE_DIR/.dockerignore.tmp" "$FIXTURE_DIR/.dockerignore"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains ".dockerignore is missing required pattern: config/image.env"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "required .dockerignore patterns are enforced"
}

test_required_oci_label_bindings_are_enforced() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "oci-labels"
  grep -Fv -- 'org.opencontainers.image.source="${OCI_SOURCE}"' "$FIXTURE_DIR/docker/Dockerfile" > "$FIXTURE_DIR/docker/Dockerfile.tmp"
  mv "$FIXTURE_DIR/docker/Dockerfile.tmp" "$FIXTURE_DIR/docker/Dockerfile"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains 'Dockerfile is missing required OCI label binding: org.opencontainers.image.source="${OCI_SOURCE}"'
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "required OCI label bindings are enforced before docker buildx bake"
}

test_build_contract_is_required_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "missing-build-contract"
  rm "$FIXTURE_DIR/docs/build-contract.md"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "docs/build-contract.md is required before validating supply-chain build guidance"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "build contract guidance is required before docker buildx bake"
}

test_build_contract_security_guidance_is_enforced() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "build-contract-guidance"
  grep -Fv -- "BuildKit secret" "$FIXTURE_DIR/docs/build-contract.md" > "$FIXTURE_DIR/docs/build-contract.md.tmp"
  mv "$FIXTURE_DIR/docs/build-contract.md.tmp" "$FIXTURE_DIR/docs/build-contract.md"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "docs/build-contract.md is missing required security guidance: BuildKit secret"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "build contract security guidance is enforced before docker buildx bake"
}

test_remote_context_skips_local_directory_check() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "remote-context"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
CONTEXT=https://github.com/example/app.git
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 0
  assert_output_contains "No-push build plan validation passed for example-app:0.1.0"
  assert_file_contains "$FIXTURE_DIR/docker.log" "CONTEXT=https://github.com/example/app.git"
  assert_file_contains "$FIXTURE_DIR/docker.log" "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>"
  pass "remote contexts skip local directory checks and still print the bake plan"
}

install_docker_stub
test_success_uses_no_push_bake_plan
test_attestation_controls_are_visible_in_no_push_bake_plan
test_missing_sbom_attestation_is_rejected
test_disabled_provenance_attestation_is_rejected
test_unsupported_attestation_controls_are_rejected_before_bake
test_multistage_template_satisfies_oci_gate
test_push_true_is_rejected_before_bake
test_missing_local_context_is_rejected_before_bake
test_parent_context_is_rejected_before_bake
test_dockerfile_outside_repo_is_rejected_before_bake
test_explicit_missing_config_file_is_rejected_before_bake
test_required_dockerignore_patterns_are_enforced
test_required_oci_label_bindings_are_enforced
test_build_contract_is_required_before_bake
test_build_contract_security_guidance_is_enforced
test_remote_context_skips_local_directory_check

printf '1..%s\n' "$TESTS_RUN"
