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
    printf '  "target": {"default": {"attest": [], "output": [{"type": "cacheonly"}]}}\n'
    printf '}\n'
    exit 0
  fi
  if [ "${IMAGE_NAME-}" = "unexpected-provenance-app" ]; then
    printf '{\n'
    printf '  "target": {"default": {"attest": [{"type": "provenance"}], "output": [{"type": "cacheonly"}]}}\n'
    printf '}\n'
    exit 0
  fi
  if [ "${IMAGE_NAME-}" = "missing-output-app" ]; then
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
  printf '      ,"output": [{"type": "cacheonly"}]\n'
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
  assert_output_contains \
    "No-push build plan validation passed for registry.example.com/team/validated-app:1.2.3"
  assert_file_contains "$FIXTURE_DIR/docker.log" \
    "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>"
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

test_no_push_bake_plan_requires_cache_only_output() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "missing-output"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
IMAGE_NAME=missing-output-app
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Buildx bake plan is missing explicit no-push output"
  pass "no-push validation requires an explicit cache-only bake output"
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
  assert_file_contains "$FIXTURE_DIR/docker.log" \
    "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>"
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

test_secret_like_metadata_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "secret-like-metadata"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
OCI_SOURCE=https://user:token@example.com/private/repository
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "OCI_SOURCE must not include URL userinfo or credentials"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "secret-like metadata is rejected before docker buildx bake"
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
  assert_file_contains "$FIXTURE_DIR/docker.log" \
    "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>"
  pass "multistage template satisfies required OCI label validation"
}

test_latest_base_image_default_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "latest-base-image"
  sed 's/alpine:3.20/alpine:latest/' "$FIXTURE_DIR/docker/Dockerfile" \
    > "$FIXTURE_DIR/docker/Dockerfile.tmp"
  mv "$FIXTURE_DIR/docker/Dockerfile.tmp" "$FIXTURE_DIR/docker/Dockerfile"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains \
    "Dockerfile must not use latest for base image default: RUNTIME_IMAGE=alpine:latest"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "latest base image defaults are rejected before docker buildx bake"
}

test_untagged_base_image_default_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "untagged-base-image"
  sed 's/alpine:3.20/alpine/' "$FIXTURE_DIR/docker/Dockerfile" \
    > "$FIXTURE_DIR/docker/Dockerfile.tmp"
  mv "$FIXTURE_DIR/docker/Dockerfile.tmp" "$FIXTURE_DIR/docker/Dockerfile"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains \
    "Dockerfile base image default must include an explicit tag or digest: RUNTIME_IMAGE=alpine"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "untagged base image defaults are rejected before docker buildx bake"
}

test_alternate_template_latest_base_image_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "alternate-template-latest-base-image"
  sed 's/node:22-alpine/node:latest/' "$FIXTURE_DIR/docker/Dockerfile.multistage" \
    > "$FIXTURE_DIR/docker/Dockerfile.multistage.tmp"
  mv "$FIXTURE_DIR/docker/Dockerfile.multistage.tmp" \
    "$FIXTURE_DIR/docker/Dockerfile.multistage"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains \
    "Dockerfile must not use latest for base image default: BUILDER_IMAGE=node:latest"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "alternate template base image defaults are rejected before docker buildx bake"
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

test_absolute_in_repo_context_and_dockerfile_are_allowed() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "absolute-in-repo-paths"
  mkdir -p "$FIXTURE_DIR/app-context"
  cp "$FIXTURE_DIR/.dockerignore" "$FIXTURE_DIR/app-context/.dockerignore"

  cat > "$FIXTURE_DIR/config/test.env" <<EOF
CONTEXT=$FIXTURE_DIR/app-context
DOCKERFILE=$FIXTURE_DIR/docker/Dockerfile
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 0
  assert_output_contains "No-push build plan validation passed for example-app:0.1.0"
  assert_file_contains "$FIXTURE_DIR/docker.log" "CONTEXT=$FIXTURE_DIR/app-context"
  assert_file_contains "$FIXTURE_DIR/docker.log" "DOCKERFILE=$FIXTURE_DIR/docker/Dockerfile"
  assert_file_contains "$FIXTURE_DIR/docker.log" \
    "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>"
  pass "absolute context and Dockerfile paths are allowed when they stay inside the repository"
}

test_absolute_context_outside_repo_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "absolute-outside-context"
  outside_context="$TEST_ROOT/outside-context"
  mkdir -p "$outside_context"

  cat > "$FIXTURE_DIR/config/test.env" <<EOF
CONTEXT=$outside_context
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Build context must stay inside repository: $outside_context"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "absolute context paths outside the repository are rejected before docker buildx bake"
}

test_context_symlink_outside_repo_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "outside-context-symlink"
  outside_context="$TEST_ROOT/outside-context-symlink-target"
  mkdir -p "$outside_context"
  ln -s "$outside_context" "$FIXTURE_DIR/context-link"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
CONTEXT=context-link
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Build context must stay inside repository: context-link"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "context symlinks resolving outside the repository are rejected before docker buildx bake"
}

test_context_symlink_inside_repo_is_allowed() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "inside-context-symlink"
  mkdir -p "$FIXTURE_DIR/app-context"
  cp "$FIXTURE_DIR/.dockerignore" "$FIXTURE_DIR/app-context/.dockerignore"
  ln -s "$FIXTURE_DIR/app-context" "$FIXTURE_DIR/context-link"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
CONTEXT=context-link
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 0
  assert_output_contains "No-push build plan validation passed for example-app:0.1.0"
  assert_file_contains "$FIXTURE_DIR/docker.log" "CONTEXT=context-link"
  assert_file_contains "$FIXTURE_DIR/docker.log" \
    "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>"
  pass "context symlinks resolving inside the repository are allowed"
}

test_absolute_dockerfile_outside_repo_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "absolute-outside-dockerfile"
  outside_dockerfile="$TEST_ROOT/outside.Dockerfile"
  printf '%s\n' "FROM scratch" > "$outside_dockerfile"

  cat > "$FIXTURE_DIR/config/test.env" <<EOF
DOCKERFILE=$outside_dockerfile
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Dockerfile must stay inside repository: $outside_dockerfile"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "absolute Dockerfile paths outside the repository are rejected before docker buildx bake"
}

test_dockerfile_symlinked_directory_outside_repo_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "outside-dockerfile-directory-symlink"
  outside_docker_dir="$TEST_ROOT/outside-docker-dir"
  mkdir -p "$outside_docker_dir"
  printf '%s\n' "FROM scratch" > "$outside_docker_dir/Dockerfile"
  ln -s "$outside_docker_dir" "$FIXTURE_DIR/docker-link"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
DOCKERFILE=docker-link/Dockerfile
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Dockerfile must stay inside repository: docker-link/Dockerfile"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "Dockerfile paths through directory symlinks outside the repository are rejected before docker buildx bake"
}

test_dockerfile_final_symlink_outside_repo_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "outside-dockerfile-final-symlink"
  outside_dockerfile="$TEST_ROOT/outside-final-symlink.Dockerfile"
  cp "$FIXTURE_DIR/docker/Dockerfile" "$outside_dockerfile"
  ln -s "$outside_dockerfile" "$FIXTURE_DIR/docker/Dockerfile.link"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
DOCKERFILE=docker/Dockerfile.link
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Dockerfile must stay inside repository: docker/Dockerfile.link"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "final Dockerfile symlinks resolving outside the repository are rejected before docker buildx bake"
}

test_repository_template_symlink_outside_repo_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "outside-template-final-symlink"
  outside_dockerfile="$TEST_ROOT/outside-template-symlink.Dockerfile"
  cp "$FIXTURE_DIR/docker/Dockerfile" "$outside_dockerfile"
  ln -s "$outside_dockerfile" "$FIXTURE_DIR/docker/Dockerfile.external"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Dockerfile must stay inside repository: docker/Dockerfile.external"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "repository template Dockerfile symlinks resolving outside the repository are rejected"
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

test_subdirectory_context_requires_effective_dockerignore() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "subdirectory-context-missing-dockerignore"
  mkdir -p "$FIXTURE_DIR/app-context"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
CONTEXT=app-context
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains ".dockerignore is required before validating a public build context"
  assert_output_contains "Missing build-context ignore file: app-context/.dockerignore"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "subdirectory contexts require their effective build-context .dockerignore"
}

test_subdirectory_context_dockerignore_patterns_are_enforced() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "subdirectory-context-dockerignore"
  mkdir -p "$FIXTURE_DIR/app-context"
  grep -Fxv -- "*.key" "$FIXTURE_DIR/.dockerignore" > "$FIXTURE_DIR/app-context/.dockerignore"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
CONTEXT=app-context
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains ".dockerignore is missing required pattern: *.key"
  assert_output_contains "Checked build-context ignore file: app-context/.dockerignore"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "subdirectory contexts enforce required patterns on the effective .dockerignore"
}

test_credential_dockerignore_patterns_are_enforced() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "dockerignore-credentials"
  grep -Fxv -- "*.pem" "$FIXTURE_DIR/.dockerignore" > "$FIXTURE_DIR/.dockerignore.tmp"
  mv "$FIXTURE_DIR/.dockerignore.tmp" "$FIXTURE_DIR/.dockerignore"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains ".dockerignore is missing required pattern: *.pem"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "credential .dockerignore patterns are enforced"
}

test_required_oci_label_bindings_are_enforced() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "oci-labels"
  grep -Fv -- 'org.opencontainers.image.source="${OCI_SOURCE}"' \
    "$FIXTURE_DIR/docker/Dockerfile" > "$FIXTURE_DIR/docker/Dockerfile.tmp"
  mv "$FIXTURE_DIR/docker/Dockerfile.tmp" "$FIXTURE_DIR/docker/Dockerfile"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  expected_output='Dockerfile is missing required OCI label binding: '
  expected_output="${expected_output}"'org.opencontainers.image.source="${OCI_SOURCE}"'
  assert_output_contains \
    "$expected_output"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "required OCI label bindings are enforced before docker buildx bake"
}

test_alternate_template_oci_label_bindings_are_enforced() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "alternate-template-oci-labels"
  grep -Fv -- 'org.opencontainers.image.source="${OCI_SOURCE}"' \
    "$FIXTURE_DIR/docker/Dockerfile.multistage" \
    > "$FIXTURE_DIR/docker/Dockerfile.multistage.tmp"
  mv "$FIXTURE_DIR/docker/Dockerfile.multistage.tmp" \
    "$FIXTURE_DIR/docker/Dockerfile.multistage"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  expected_output='Dockerfile is missing required OCI label binding: '
  expected_output="${expected_output}"'org.opencontainers.image.source="${OCI_SOURCE}"'
  assert_output_contains "$expected_output"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "alternate template Dockerfiles must keep required OCI label bindings"
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
  assert_output_contains \
    "docs/build-contract.md is required before validating supply-chain build guidance"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "build contract guidance is required before docker buildx bake"
}

test_build_contract_security_guidance_is_enforced() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "build-contract-guidance"
  grep -Fv -- "BuildKit secret" "$FIXTURE_DIR/docs/build-contract.md" \
    > "$FIXTURE_DIR/docs/build-contract.md.tmp"
  mv "$FIXTURE_DIR/docs/build-contract.md.tmp" "$FIXTURE_DIR/docs/build-contract.md"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains \
    "docs/build-contract.md is missing required security guidance: BuildKit secret"
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
  assert_file_contains "$FIXTURE_DIR/docker.log" \
    "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>"
  pass "remote contexts skip local directory checks and still print the bake plan"
}

test_git_ssh_remote_context_skips_local_directory_check() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "git-ssh-remote-context"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
CONTEXT=git@github.com:example/app.git
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 0
  assert_output_contains "No-push build plan validation passed for example-app:0.1.0"
  assert_file_contains "$FIXTURE_DIR/docker.log" "CONTEXT=git@github.com:example/app.git"
  assert_file_contains "$FIXTURE_DIR/docker.log" \
    "args: <buildx> <bake> <--file> <buildx/docker-bake.hcl> <--print>"
  pass "git SSH remote contexts skip local directory checks and still print the bake plan"
}

install_docker_stub
test_success_uses_no_push_bake_plan
test_no_push_bake_plan_requires_cache_only_output
test_attestation_controls_are_visible_in_no_push_bake_plan
test_missing_sbom_attestation_is_rejected
test_disabled_provenance_attestation_is_rejected
test_unsupported_attestation_controls_are_rejected_before_bake
test_secret_like_metadata_is_rejected_before_bake
test_multistage_template_satisfies_oci_gate
test_latest_base_image_default_is_rejected_before_bake
test_untagged_base_image_default_is_rejected_before_bake
test_alternate_template_latest_base_image_is_rejected_before_bake
test_push_true_is_rejected_before_bake
test_missing_local_context_is_rejected_before_bake
test_parent_context_is_rejected_before_bake
test_dockerfile_outside_repo_is_rejected_before_bake
test_absolute_in_repo_context_and_dockerfile_are_allowed
test_absolute_context_outside_repo_is_rejected_before_bake
test_context_symlink_outside_repo_is_rejected_before_bake
test_context_symlink_inside_repo_is_allowed
test_absolute_dockerfile_outside_repo_is_rejected_before_bake
test_dockerfile_symlinked_directory_outside_repo_is_rejected_before_bake
test_dockerfile_final_symlink_outside_repo_is_rejected_before_bake
test_repository_template_symlink_outside_repo_is_rejected_before_bake
test_explicit_missing_config_file_is_rejected_before_bake
test_required_dockerignore_patterns_are_enforced
test_subdirectory_context_requires_effective_dockerignore
test_subdirectory_context_dockerignore_patterns_are_enforced
test_credential_dockerignore_patterns_are_enforced
test_required_oci_label_bindings_are_enforced
test_alternate_template_oci_label_bindings_are_enforced
test_build_contract_is_required_before_bake
test_build_contract_security_guidance_is_enforced
test_remote_context_skips_local_directory_check
test_git_ssh_remote_context_skips_local_directory_check

printf '1..%s\n' "$TESTS_RUN"
