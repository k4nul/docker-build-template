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

assert_file_not_exists() {
  file_path=$1
  if [ -e "$file_path" ]; then
    fail "expected $file_path not to exist"
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
  printf 'OCI_CREATED=%s\n' "${OCI_CREATED-}"
} >> "$DOCKER_STUB_LOG"

if [ "$#" -eq 5 ] &&
  [ "$1" = "buildx" ] &&
  [ "$2" = "bake" ] &&
  [ "$3" = "--file" ] &&
  [ "$4" = "buildx/docker-bake.hcl" ] &&
  [ "$5" = "--print" ]; then
  stub_image_ref="${REGISTRY-}${IMAGE_NAME-}:${IMAGE_TAG-}"
  stub_context=${CONTEXT-}
  stub_oci_title=${OCI_TITLE-}
  if [ "${IMAGE_NAME-}" = "wrong-image-app" ]; then
    stub_image_ref="registry.example.com/team/unexpected-app:${IMAGE_TAG-}"
  fi
  if [ "${IMAGE_NAME-}" = "wrong-context-app" ]; then
    stub_context=unexpected-context
  fi
  if [ "${IMAGE_NAME-}" = "wrong-title-app" ]; then
    stub_oci_title="Unexpected title"
  fi
  printf '{\n'
  printf '  "target": {\n'
  printf '    "default": {\n'
  printf '      "context": "%s",\n' "$stub_context"
  printf '      "dockerfile": "%s",\n' "${DOCKERFILE-}"
  printf '      "args": {\n'
  printf '        "OCI_TITLE": "%s",\n' "$stub_oci_title"
  printf '        "OCI_DESCRIPTION": "%s",\n' "${OCI_DESCRIPTION-}"
  printf '        "OCI_SOURCE": "%s",\n' "${OCI_SOURCE-}"
  printf '        "OCI_REVISION": "%s",\n' "${OCI_REVISION-}"
  printf '        "OCI_CREATED": "%s",\n' "${OCI_CREATED-}"
  printf '        "OCI_LICENSES": "%s"\n' "${OCI_LICENSES-}"
  printf '      },\n'
  printf '      "tags": ["%s"],\n' "$stub_image_ref"
  printf '      "platforms": ['
  old_ifs=$IFS
  IFS=,
  first_platform=true
  for platform in ${PLATFORMS-}; do
    IFS=$old_ifs
    if [ "$first_platform" = true ]; then
      first_platform=false
    else
      printf ', '
    fi
    printf '"%s"' "$platform"
    IFS=,
  done
  IFS=$old_ifs
  printf '],\n'
  if [ "${SBOM-}" = "true" ] || [ "${PROVENANCE-}" != "false" ] || \
    [ "${IMAGE_NAME-}" = "unexpected-provenance-app" ]; then
    printf '      "attest": [\n'
    if [ "${SBOM-}" = "true" ] && [ "${IMAGE_NAME-}" != "missing-sbom-app" ]; then
      printf '        {"type": "sbom"}'
      if [ "${PROVENANCE-}" != "false" ]; then
        printf ',\n'
      else
        printf '\n'
      fi
    fi
    if [ "${IMAGE_NAME-}" = "unexpected-provenance-app" ]; then
      printf '        {"type": "provenance"}\n'
    elif [ "${PROVENANCE-}" = "mode=min" ]; then
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
  if [ "${IMAGE_NAME-}" != "missing-output-app" ]; then
    printf '      ,"output": [{"type": "cacheonly"}]\n'
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
      BAKE_PLAN_OUTPUT="${VALIDATOR_BAKE_PLAN_OUTPUT:-}" \
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
OCI_CREATED=2026-06-15T12:34:56Z
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
  assert_file_contains "$FIXTURE_DIR/docker.log" "OCI_CREATED=2026-06-15T12:34:56Z"
  pass "no-push validation exports settings and checks resolved plan identity and metadata"
}

test_mismatched_bake_plan_image_tag_is_rejected() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "mismatched-bake-plan-image-tag"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
REGISTRY=registry.example.com/team/
IMAGE_NAME=wrong-image-app
IMAGE_TAG=1.2.3
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Buildx bake plan image tag does not match registry.example.com/team/wrong-image-app:1.2.3"
  pass "no-push validation rejects a Bake plan with a mismatched image tag"
}

test_mismatched_bake_plan_context_and_metadata_are_rejected() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "mismatched-bake-plan-context"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
IMAGE_NAME=wrong-context-app
CONTEXT=.
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Buildx bake plan context does not match CONTEXT=."

  make_fixture "mismatched-bake-plan-metadata"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
IMAGE_NAME=wrong-title-app
OCI_TITLE=Expected title
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Buildx bake plan OCI_TITLE does not match the resolved build setting"
  pass "no-push validation rejects Bake plans with mismatched context or OCI metadata"
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

test_config_aware_bake_plan_can_be_written_for_review() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "bake-plan-review-output"
  review_output="$FIXTURE_DIR/out/review-bake-plan.json"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
IMAGE_NAME=review-output-app
SBOM=true
PROVENANCE=mode=min
EOF

  VALIDATOR_BAKE_PLAN_OUTPUT=$review_output
  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"
  VALIDATOR_BAKE_PLAN_OUTPUT=

  assert_status 0
  assert_output_contains "Wrote config-aware Buildx bake plan to $review_output"
  assert_file_contains "$review_output" '"type": "cacheonly"'
  assert_file_contains "$review_output" '"type": "sbom"'
  assert_file_contains "$review_output" '"type": "provenance", "mode": "min"'
  pass "config-aware bake plans can be written as review artifacts"
}

test_config_aware_bake_plan_can_be_written_to_stdout() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "bake-plan-review-stdout"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
IMAGE_NAME=stdout-review-app
SBOM=true
PROVENANCE=mode=max
EOF

  VALIDATOR_BAKE_PLAN_OUTPUT=-
  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"
  VALIDATOR_BAKE_PLAN_OUTPUT=

  assert_status 0
  assert_output_contains '"type": "cacheonly"'
  assert_output_contains '"type": "sbom"'
  assert_output_contains '"type": "provenance", "mode": "max"'
  assert_output_contains "No-push build plan validation passed for stdout-review-app:0.1.0"
  pass "config-aware bake plans can be written to stdout for review"
}

test_failed_bake_plan_does_not_write_review_output() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "failed-bake-plan-review-output"
  review_output="$FIXTURE_DIR/out/failed-bake-plan.json"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
IMAGE_NAME=missing-sbom-app
SBOM=true
PROVENANCE=false
EOF

  VALIDATOR_BAKE_PLAN_OUTPUT=$review_output
  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"
  VALIDATOR_BAKE_PLAN_OUTPUT=

  assert_status 2
  assert_output_contains "Buildx bake plan is missing SBOM attestation while SBOM=true"
  assert_file_not_exists "$review_output"
  pass "failed bake plans are not persisted as review artifacts"
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

test_control_character_metadata_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "control-character-metadata"

  printf 'PUSH=false\nOCI_DESCRIPTION=Unsafe\tmetadata\n' > "$FIXTURE_DIR/config/test.env"

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "OCI_DESCRIPTION must not contain control characters"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "control-character metadata is rejected before docker buildx bake"
}

test_newline_environment_metadata_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "newline-environment-metadata"
  newline_description='Unsafe
metadata'

  printf 'PUSH=false\n' > "$FIXTURE_DIR/config/test.env"

  OCI_DESCRIPTION="$newline_description" \
    run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "OCI_DESCRIPTION must not contain control characters"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "newline environment metadata is rejected before docker buildx bake"
}

test_nul_config_metadata_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "nul-config-metadata"

  printf 'PUSH=false\nOCI_DESCRIPTION=Unsafe\000metadata\n' > "$FIXTURE_DIR/config/test.env"

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Config file must not contain NUL bytes"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "NUL config metadata is rejected before shell parsing or docker buildx bake"
}

test_remote_context_userinfo_is_rejected_before_bake() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "remote-context-userinfo"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
CONTEXT=https://user:token@example.com/private/repository.git
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "CONTEXT must not include URL userinfo or credentials"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "credentialed remote contexts are rejected before docker buildx bake"
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

test_config_env_glob_dockerignore_pattern_is_enforced() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "dockerignore-config-env-glob"
  grep -Fxv -- "config/*.env" "$FIXTURE_DIR/.dockerignore" > "$FIXTURE_DIR/.dockerignore.tmp"
  mv "$FIXTURE_DIR/.dockerignore.tmp" "$FIXTURE_DIR/.dockerignore"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains ".dockerignore is missing required pattern: config/*.env"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "config env globs are required for arbitrary CONFIG_FILE hygiene"
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

test_creation_metadata_bindings_are_enforced_for_all_templates() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "created-label-primary-template"
  grep -Fv -- 'org.opencontainers.image.created="${OCI_CREATED}"' \
    "$FIXTURE_DIR/docker/Dockerfile" > "$FIXTURE_DIR/docker/Dockerfile.tmp"
  mv "$FIXTURE_DIR/docker/Dockerfile.tmp" "$FIXTURE_DIR/docker/Dockerfile"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains 'Dockerfile is missing required OCI label binding: org.opencontainers.image.created="${OCI_CREATED}"'
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"

  make_fixture "created-argument-alternate-template"
  grep -Fv -- 'ARG OCI_CREATED="1970-01-01T00:00:00Z"' \
    "$FIXTURE_DIR/docker/Dockerfile.multistage" > "$FIXTURE_DIR/docker/Dockerfile.multistage.tmp"
  mv "$FIXTURE_DIR/docker/Dockerfile.multistage.tmp" \
    "$FIXTURE_DIR/docker/Dockerfile.multistage"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains "Dockerfile is missing required OCI metadata argument: OCI_CREATED"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "creation metadata bindings are enforced for both template Dockerfiles"
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
  pass "remote contexts skip local directory checks and still check the bake plan"
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
  pass "git SSH remote contexts skip local directory checks and still check the bake plan"
}

test_remote_context_still_requires_template_dockerignore() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "remote-context-missing-dockerignore"
  rm "$FIXTURE_DIR/.dockerignore"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
CONTEXT=https://github.com/example/app.git
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains ".dockerignore is required before validating a public build context"
  assert_output_contains "Missing build-context ignore file: .dockerignore"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "remote contexts still require the template root .dockerignore contract"
}

test_remote_context_still_enforces_template_dockerignore_patterns() {
  TESTS_RUN=$((TESTS_RUN + 1))
  make_fixture "remote-context-dockerignore-patterns"
  grep -Fxv -- ".codex" "$FIXTURE_DIR/.dockerignore" > "$FIXTURE_DIR/.dockerignore.tmp"
  mv "$FIXTURE_DIR/.dockerignore.tmp" "$FIXTURE_DIR/.dockerignore"

  cat > "$FIXTURE_DIR/config/test.env" <<'EOF'
CONTEXT=git@github.com:example/app.git
PUSH=false
EOF

  run_validator "$FIXTURE_DIR" "$FIXTURE_DIR/config/test.env"

  assert_status 2
  assert_output_contains ".dockerignore is missing required pattern: .codex"
  assert_output_contains "Checked build-context ignore file: .dockerignore"
  assert_no_docker_calls "$FIXTURE_DIR/docker.log"
  pass "remote contexts still enforce required template .dockerignore patterns"
}

install_docker_stub
test_success_uses_no_push_bake_plan
test_mismatched_bake_plan_image_tag_is_rejected
test_mismatched_bake_plan_context_and_metadata_are_rejected
test_no_push_bake_plan_requires_cache_only_output
test_attestation_controls_are_visible_in_no_push_bake_plan
test_config_aware_bake_plan_can_be_written_for_review
test_config_aware_bake_plan_can_be_written_to_stdout
test_failed_bake_plan_does_not_write_review_output
test_missing_sbom_attestation_is_rejected
test_disabled_provenance_attestation_is_rejected
test_unsupported_attestation_controls_are_rejected_before_bake
test_secret_like_metadata_is_rejected_before_bake
test_control_character_metadata_is_rejected_before_bake
test_newline_environment_metadata_is_rejected_before_bake
test_nul_config_metadata_is_rejected_before_bake
test_remote_context_userinfo_is_rejected_before_bake
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
test_config_env_glob_dockerignore_pattern_is_enforced
test_subdirectory_context_requires_effective_dockerignore
test_subdirectory_context_dockerignore_patterns_are_enforced
test_credential_dockerignore_patterns_are_enforced
test_required_oci_label_bindings_are_enforced
test_alternate_template_oci_label_bindings_are_enforced
test_creation_metadata_bindings_are_enforced_for_all_templates
test_build_contract_is_required_before_bake
test_build_contract_security_guidance_is_enforced
test_remote_context_skips_local_directory_check
test_git_ssh_remote_context_skips_local_directory_check
test_remote_context_still_requires_template_dockerignore
test_remote_context_still_enforces_template_dockerignore_patterns

printf '1..%s\n' "$TESTS_RUN"
